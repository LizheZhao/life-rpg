import Foundation
import SwiftData

/// Judging a day that has ended (`PLAN.md` §4, "Overdue penalty" and "Movable within the week").
/// Called by `DayService.catchUp` for every day in `[lastProcessed … yesterday]`, oldest first,
/// so a stretch of days the app was never opened is still judged day by day.
///
/// **Fixed routines** still open at the end of round day 1 / 2 / 3 are charged 50% / 75% / 100%
/// of base, each day separately; after day 3 the round ends and the occurrence is skipped (a
/// `skip` ledger entry dated day 4). A late make-up is simply no longer open when its day is
/// judged, so that day's deduction never happens and earlier ones stay.
///
/// **Flexible routines** are never charged daily. On Sunday the week is settled once: the target
/// is `weeklyTarget`, capped by how many occurrences actually came due that week; every missing
/// one costs 50% of base, charged against an open occurrence, and the open ones are skipped.
///
/// `countsForClear = false` routines are never charged, but their rounds still end.
/// Penalties are fixed on base — never scaled by tier or readiness.
///
/// Idempotent: a penalty is keyed on (occurrence, day) in the ledger and a skip on the flag, so
/// judging the same day twice changes nothing. Does not save; `ensureToday` saves once at the end.
public enum Overdue {
    public static func settle(_ dayKey: String, in context: ModelContext,
                              timeZone: TimeZone = .current, now: Date = Date()) throws {
        let routines = try context.fetch(FetchDescriptor<RoutineTask>())
        let flexible = Set(routines.filter(\.flexibleWithinWeek).map(\.id))
        let occurrences = try context.fetch(FetchDescriptor<RoutineOccurrence>())
        let penaltyKind = Economy.Kind.penalty.rawValue
        var charged = Set(try context.fetch(FetchDescriptor<LedgerEntry>(
            predicate: #Predicate { $0.kind == penaltyKind && $0.dayKey == dayKey })).compactMap(\.refID))
        guard let nextDay = DayKey.adding(1, to: dayKey, in: timeZone) else { return }

        func charge(_ o: RoutineOccurrence, _ points: Int, _ note: String) {
            guard o.countsForClear, points > 0, charged.insert(o.id).inserted else { return }
            Economy.record(context, kind: .penalty, points: -points, dayKey: dayKey,
                           refID: o.id, note: "\(o.textSnapshot) — \(note)", now: now)
            o.penaltyApplied += points
        }

        func skip(_ o: RoutineOccurrence) {
            guard !o.skipped else { return }
            o.skipped = true
            Economy.record(context, kind: .skip, points: 0, dayKey: nextDay,
                           refID: o.id, note: o.textSnapshot, now: now)
        }

        // Fixed routines: the daily ladder.
        for o in occurrences where Schedule.isOpen(o) && !Schedule.isFlexible(o, flexible) {
            guard let roundDay = Schedule.roundDay(due: o.dueDayKey, on: dayKey, in: timeZone) else { continue }
            charge(o, Scoring.overduePenalty(basePoints: o.basePoints, roundDay: roundDay),
                   "overdue day \(roundDay)")
            if roundDay == Schedule.roundDays { skip(o) }
        }

        // Flexible routines: once, on Sunday.
        guard DayKey.weekday(of: dayKey, in: timeZone) == .sunday,
              let week = DayKey.weekKey(of: dayKey, in: timeZone) else { return }
        for routine in routines where routine.flexibleWithinWeek {
            let thisWeek = occurrences
                .filter { $0.routineID == routine.id && $0.weekKey == week }
                .sorted { $0.dueDayKey < $1.dueDayKey }
            guard !thisWeek.isEmpty else { continue }
            let done = thisWeek.filter { $0.completedDayKey != nil }.count
            let shortfall = max(0, min(routine.weeklyTarget, thisWeek.count) - done)
            let open = thisWeek.filter(Schedule.isOpen)
            for o in open.prefix(shortfall) {
                charge(o, Scoring.flexibleShortfallPenalty(basePoints: o.basePoints),
                       "\(done)/\(routine.weeklyTarget) this week")
            }
            open.forEach(skip)
        }
    }
}
