import Foundation
import SwiftData

/// Completing a random quest: roll the points, write the ledger, start the template's cooldown.
///
/// **There is no undo.** Completion is final by design — the app is a single-user honesty system,
/// and a reversible checkbox turns the points roll into something you can re-roll until you like
/// the number. Everything here is therefore written once: the ledger entry is never deleted and
/// never reversed. A genuine mistake is corrected with a `kind = .adjust` entry.
public enum Completion {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case alreadyCompleted
        case trivialGroupIncomplete(remaining: Int)
        case indexOutOfRange
        case skipped
        /// The slot was taken over by an ad-hoc routine (`AdHoc.replace`).
        case replaced
        /// A flexible routine with nothing left to come due this week (or not flexible at all).
        case nothingAhead
        /// Before the due day, or after day 3 of the round (day 4 is the auto-skip).
        case outsideRound(dueDayKey: String, dayKey: String)

        public var description: String {
            switch self {
            case .alreadyCompleted: "already completed"
            case .trivialGroupIncomplete(let n): "\(n) item(s) of the T group still undone"
            case .indexOutOfRange: "no such T group item"
            case .skipped: "already skipped"
            case .replaced: "replaced by an ad-hoc routine"
            case .nothingAhead: "nothing left to do ahead this week"
            case .outsideRound(let due, let day): "due \(due), can't be completed on \(day)"
            }
        }
    }

    /// Completes a single-quest slot (or a T group whose three items are all ticked).
    /// Returns the points awarded.
    @discardableResult
    public static func complete(_ quest: DailyQuest,
                                tier: Tier,
                                in context: ModelContext,
                                now: Date = Date(),
                                source: SourceType = .manual,
                                rng: inout some RandomNumberGenerator) throws -> Int {
        guard quest.completedAt == nil else { throw Failure.alreadyCompleted }
        guard !quest.replaced else { throw Failure.replaced }
        if quest.isTrivialGroup {
            let remaining = quest.trivialDone.filter { !$0 }.count
            guard remaining == 0 else { throw Failure.trivialGroupIncomplete(remaining: remaining) }
        }

        let points = Scoring.questPoints(quest, tier: tier, rng: &rng)
        let templates = try templates(of: quest, in: context)
        let cooldownBefore = templates.map(\.lastCompletedDayKey)

        let sourceBefore = quest.sourceType
        quest.points = points
        quest.completedAt = now
        quest.sourceType = source
        for template in templates {
            template.lastCompletedDayKey = quest.dayKey        // cooldown counts from completion
        }
        let entry = Economy.record(context, kind: .quest, points: points, dayKey: quest.dayKey,
                                   refID: quest.id, note: quest.textSnapshot, now: now)

        do {
            try context.save()
        } catch {
            // Nothing counts as done until the row is on disk. Without this the quest would read
            // as completed in memory while the ledger entry that pays for it was never written —
            // the page shows "+23", the balance doesn't move, and a second tap throws
            // `alreadyCompleted` because the in-memory object already looks finished.
            quest.points = nil
            quest.completedAt = nil
            quest.sourceType = sourceBefore
            for (template, previous) in zip(templates, cooldownBefore) {
                template.lastCompletedDayKey = previous
            }
            context.delete(entry)
            throw error
        }
        return points
    }

    /// Ticks one item of a T group; the group scores only once all three are ticked, which is what
    /// `complete` then does. Returns the points if that tick finished the group.
    @discardableResult
    public static func tickTrivialItem(_ quest: DailyQuest,
                                       at index: Int,
                                       tier: Tier,
                                       in context: ModelContext,
                                       now: Date = Date(),
                                       rng: inout some RandomNumberGenerator) throws -> Int? {
        guard quest.completedAt == nil else { throw Failure.alreadyCompleted }
        guard !quest.replaced else { throw Failure.replaced }
        guard quest.trivialDone.indices.contains(index) else { throw Failure.indexOutOfRange }

        quest.trivialDone[index] = true
        do {
            guard quest.trivialDone.allSatisfy({ $0 }) else {
                try context.save()
                return nil
            }
            return try complete(quest, tier: tier, in: context, now: now, rng: &rng)
        } catch {
            quest.trivialDone[index] = false      // same rule: an unsaved tick is not a tick
            throw error
        }
    }

    /// What completing `occurrence` on `dayKey` pays, or nil when it can't be completed that day.
    ///
    /// A fixed routine: full on the due day, half as a late make-up on round day 2–3, closed from
    /// day 4. A flexible one: full on any day from its due day to the end of that week — moving it
    /// inside the week is the point, not lateness (`PLAN.md` §4).
    public static func routinePayout(_ occurrence: RoutineOccurrence, flexible: Bool,
                                     on dayKey: String, tier: Tier,
                                     in timeZone: TimeZone = .current) -> Int? {
        if flexible {
            guard occurrence.dueDayKey <= dayKey,
                  DayKey.weekKey(of: dayKey, in: timeZone) == occurrence.weekKey else { return nil }
            return Scoring.routinePoints(basePoints: occurrence.effectiveBasePoints, tier: tier, late: false)
        }
        guard let roundDay = Schedule.roundDay(due: occurrence.dueDayKey, on: dayKey, in: timeZone) else {
            return nil
        }
        return Scoring.routinePoints(basePoints: occurrence.effectiveBasePoints, tier: tier, late: roundDay > 1)
    }

    /// Completes a routine occurrence on `dayKey`, paying `routinePayout`. Returns the points.
    ///
    /// Also writes the routine's `lastCompletedDayKey` (what `everyNDays` counts from) and, for
    /// `everyNWeeksOnWeekday`, sets `anchorWeekKey` on the first completion ever — the cadence
    /// starts from the week you actually did it, not from an arbitrary date in the CSV.
    @discardableResult
    public static func completeRoutine(_ occurrence: RoutineOccurrence,
                                       on dayKey: String,
                                       tier: Tier,
                                       in context: ModelContext,
                                       now: Date = Date(),
                                       timeZone: TimeZone = .current,
                                       source: SourceType = .manual) throws -> Int {
        guard occurrence.completedDayKey == nil else { throw Failure.alreadyCompleted }
        guard !occurrence.skipped else { throw Failure.skipped }
        let routine = try routine(of: occurrence, in: context)
        guard let points = routinePayout(occurrence, flexible: routine?.flexibleWithinWeek ?? false,
                                         on: dayKey, tier: tier, in: timeZone) else {
            throw Failure.outsideRound(dueDayKey: occurrence.dueDayKey, dayKey: dayKey)
        }
        let lastCompletedBefore = routine?.lastCompletedDayKey
        let anchorBefore = routine?.anchorWeekKey
        let sourceBefore = occurrence.sourceType

        occurrence.completedDayKey = dayKey
        occurrence.completedAt = now
        occurrence.awardedPoints = points
        occurrence.sourceType = source
        routine.map { stamp($0, completedOn: dayKey, weekKey: occurrence.weekKey) }
        let entry = Economy.record(context, kind: .routine, points: points, dayKey: dayKey,
                                   refID: occurrence.id, note: occurrence.displayText, now: now)

        do {
            try context.save()
        } catch {
            // Same rule as `complete`: nothing is done until its ledger entry is on disk.
            occurrence.completedDayKey = nil
            occurrence.completedAt = nil
            occurrence.awardedPoints = nil
            occurrence.sourceType = sourceBefore
            routine?.lastCompletedDayKey = lastCompletedBefore
            routine?.anchorWeekKey = anchorBefore
            context.delete(entry)
            throw error
        }
        return points
    }

    /// Does a flexible routine ahead of its due day: creates the next occurrence still to come
    /// this week (`Schedule.aheadCandidates`) and completes it today, at full pay. When that day
    /// arrives the occurrence already exists, so it is neither created again nor counted as load.
    ///
    /// On a low day with a light version on offer, `light` says which version was done — there is
    /// no open occurrence to switch afterwards, so the choice is made here. The light version pays
    /// its own points; ignored when there is no light version.
    @discardableResult
    public static func completeAhead(_ routine: RoutineTask,
                                     on dayKey: String,
                                     tier: Tier,
                                     light: Bool = true,
                                     in context: ModelContext,
                                     now: Date = Date(),
                                     timeZone: TimeZone = .current) throws -> Int {
        let all = try context.fetch(FetchDescriptor<RoutineOccurrence>())
        guard let ahead = Schedule.aheadCandidates([routine], occurrences: all, on: dayKey, in: timeZone).first,
              let week = DayKey.weekKey(of: dayKey, in: timeZone) else { throw Failure.nothingAhead }

        let lastCompletedBefore = routine.lastCompletedDayKey
        let anchorBefore = routine.anchorWeekKey
        // No open occurrence exists yet, so the light-version choice is made here rather than
        // switched afterwards; `light: false` does the original even on a low day.
        let downgrade = light ? Degrade.pick(for: routine, tier: tier,
                                             in: try context.fetch(FetchDescriptor<RoutineTask>())) : nil
        let occurrence = RoutineOccurrence(routine: routine, dueDayKey: ahead.nextDueDayKey, weekKey: week,
                                           downgrade: downgrade)
        let points = Scoring.routinePoints(basePoints: occurrence.effectiveBasePoints, tier: tier, late: false)
        occurrence.completedDayKey = dayKey
        occurrence.completedAt = now
        occurrence.awardedPoints = points
        context.insert(occurrence)
        stamp(routine, completedOn: dayKey, weekKey: week)
        let entry = Economy.record(context, kind: .routine, points: points, dayKey: dayKey,
                                   refID: occurrence.id, note: occurrence.displayText, now: now)
        do {
            try context.save()
        } catch {
            routine.lastCompletedDayKey = lastCompletedBefore
            routine.anchorWeekKey = anchorBefore
            context.delete(occurrence)
            context.delete(entry)
            throw error
        }
        return points
    }

    /// What a completion writes back to the routine, however it was done: `lastCompletedDayKey`
    /// (what `everyNDays` counts from) and, the first time ever, the `everyNWeeksOnWeekday` anchor.
    static func stamp(_ routine: RoutineTask, completedOn dayKey: String, weekKey: String) {
        routine.lastCompletedDayKey = dayKey
        if routine.kind == .everyNWeeksOnWeekday, routine.anchorWeekKey == nil {
            routine.anchorWeekKey = weekKey
        }
    }

    static func routine(of occurrence: RoutineOccurrence, in context: ModelContext) throws -> RoutineTask? {
        guard let id = occurrence.routineID else { return nil }
        return try context.fetch(FetchDescriptor<RoutineTask>(predicate: #Predicate { $0.id == id })).first
    }

    /// The templates behind a quest — one, or the three of a T group. A template deleted since the
    /// draw simply drops out; the snapshot on the quest keeps the history readable either way.
    static func templates(of quest: DailyQuest, in context: ModelContext) throws -> [QuestTemplate] {
        let ids = quest.isTrivialGroup ? quest.trivialTemplateIDs : [quest.templateID].compactMap { $0 }
        guard !ids.isEmpty else { return [] }
        let wanted = Set(ids)
        return try context.fetch(FetchDescriptor<QuestTemplate>())
            .filter { wanted.contains($0.id) }
    }
}
