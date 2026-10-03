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
/// Penalties are fixed on base — never scaled by tier or readiness. The base is the one the day
/// actually asked for: an occurrence sitting on its downgrade version is charged against that
/// version's points, because a walk is what was missed.
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
            charge(o, Scoring.overduePenalty(basePoints: o.effectiveBasePoints, roundDay: roundDay),
                   "overdue day \(roundDay)")
            if roundDay == Schedule.roundDays { skip(o) }
        }

        // Flexible routines: once, on Sunday.
        guard DayKey.weekday(of: dayKey, in: timeZone) == .sunday,
              let week = DayKey.weekKey(of: dayKey, in: timeZone) else { return }
        let settlement = weekly(routines, occurrences: occurrences, weekKey: week)
        for c in settlement.charges { charge(c.occurrence, c.points, c.note) }
        settlement.closing.forEach(skip)
    }

    /// What Sunday's flexible settlement will do to `weekKey`, computed from rows only — so the
    /// today page can show the bill before it lands, with the same rule that charges it.
    public struct Weekly {
        public struct Charge {
            public let occurrence: RoutineOccurrence
            public let points: Int
            public let note: String
        }
        /// One per session short of the target, charged against an open occurrence.
        public let charges: [Charge]
        /// Every open occurrence of the week, skipped once it is settled.
        public let closing: [RoutineOccurrence]

        /// What the charges come to — only the ones that are actually charged
        /// (`countsForClear = false` routines never are).
        public var total: Int { charges.filter(\.occurrence.countsForClear).map(\.points).reduce(0, +) }

        /// What is charged against this one occurrence, so a row can say it itself.
        public func points(for o: RoutineOccurrence) -> Int {
            charges.filter { $0.occurrence.id == o.id && $0.occurrence.countsForClear }
                .map(\.points).reduce(0, +)
        }
    }

    /// The target is `weeklyTarget`, capped by how many sessions actually came due that week; done
    /// sessions include ad-hoc ones picked from the routine (`Schedule.doneThisWeek`). A session
    /// swapped for something else (`isReplaced`) is no longer asked of you and drops out of both
    /// sides.
    public static func weekly(_ routines: [RoutineTask], occurrences: [RoutineOccurrence],
                              weekKey: String) -> Weekly {
        var charges: [Weekly.Charge] = []
        var closing: [RoutineOccurrence] = []
        for routine in routines where routine.flexibleWithinWeek {
            let thisWeek = occurrences
                .filter { $0.routineID == routine.id && $0.weekKey == weekKey && !$0.isReplaced }
                .sorted { $0.dueDayKey < $1.dueDayKey }
            guard !thisWeek.isEmpty else { continue }
            let done = Schedule.doneThisWeek(occurrences, routineID: routine.id, weekKey: weekKey)
            let shortfall = max(0, min(routine.weeklyTarget, thisWeek.count) - done)
            let open = thisWeek.filter(Schedule.isOpen)
            for o in open.prefix(shortfall) {
                charges.append(.init(occurrence: o,
                                     points: Scoring.flexibleShortfallPenalty(basePoints: o.effectiveBasePoints),
                                     note: "\(done)/\(routine.weeklyTarget) this week"))
            }
            closing += open
        }
        return Weekly(charges: charges, closing: closing)
    }
}
