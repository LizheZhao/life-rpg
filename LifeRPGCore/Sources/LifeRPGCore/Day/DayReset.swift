import Foundation
import SwiftData

/// Reopening, or resetting, a day that was already played.
///
/// **This is a debug tool and nothing on the today page reaches it.** `PLAN.md` §3 makes completion
/// final on purpose — a reversible tick turns the points roll into something you can re-roll until
/// the number is good, and the whole economy rests on that not being possible. This exists so the
/// reveal animation and the scoring rules can be exercised more than once a day while they are
/// being built, and it lives behind the debug page for the same reason the raw store export lives
/// behind the startup error screen.
///
/// It is a genuine undo, not a partial one: the ledger entries that paid for those quests are
/// deleted, so the balance goes back to what it was rather than keeping points for work that is
/// now marked undone.
public enum DayReset {
    /// What `reset` took away.
    public struct Reset: Equatable, Sendable {
        public var quests = 0
        public var occurrences = 0
        public var reopened = 0
        public var ledgerEntries = 0
        public var feedback = 0

        public var description: String {
            "Reset: removed \(quests) quest(s) and \(occurrences) routine(s), reopened \(reopened), "
            + "deleted \(ledgerEntries) ledger entr(ies) and \(feedback) rating/note(s); the day was generated again"
        }
    }

    /// Puts the day back as if it had just been opened, and generates it again.
    ///
    /// Everything dated `dayKey` goes — the random slots (replaced and rerolled ones included), the
    /// routines due that day and the extras added to it, a session done ahead that day, and the day's
    /// record — together with every ledger entry and every rating or note that points at one of
    /// them. What was only *done* that day is reopened rather than removed: the week's epic, which is
    /// not redrawn, and a routine from an earlier round that was made up that day. Cooldown stamps
    /// the day set are given back, and a routine's last completion is recomputed from what is left.
    ///
    /// Other days stay as they are. So do the entries the day's opening made about the day before
    /// (a penalty or a skip is dated the day it was judged, but is booked against the earlier
    /// occurrence, so deleting it would charge that occurrence again). The day keeps the tier it had.
    ///
    /// Known limit: a routine from an earlier round that was *swapped* that day is not undone, as its
    /// replacement carries the earlier due day.
    @discardableResult
    public static func reset(_ context: ModelContext, dayKey: String, now: Date,
                             in timeZone: TimeZone = .current,
                             rng: inout some RandomNumberGenerator) throws -> Reset {
        var result = Reset()
        let quests = try context.fetch(FetchDescriptor<DailyQuest>())
        let occurrences = try context.fetch(FetchDescriptor<RoutineOccurrence>())
        let ledger = try context.fetch(FetchDescriptor<LedgerEntry>())
        let dayContext = try DayService.dailyContext(for: dayKey, in: context)
        let inputs = dayContext.map { c -> DayInputs in
            var i = DayInputs(tier: c.tier, cycleDay: c.cycleDay, energy: c.energy, readiness: c.readiness)
            i.hrv = c.hrv; i.sleepHours = c.sleepHours; i.restingHR = c.restingHR
            return i
        }
        var affected = Set<UUID>()
        let isEpic = { (q: DailyQuest) in q.slot == .epic && !q.isHiddenSlot }

        for q in quests where q.dayKey == dayKey && !isEpic(q) {
            affected.insert(q.id)
            context.delete(q)
            result.quests += 1
        }
        // The epic lives all week and is not redrawn; if it was done today, it is open again.
        let questKind = Economy.Kind.quest.rawValue
        for q in quests where isEpic(q) && q.points != nil
            && ledger.contains(where: { $0.refID == q.id && $0.dayKey == dayKey && $0.kind == questKind }) {
            q.points = nil
            q.completedAt = nil
            affected.insert(q.id)
            result.reopened += 1
        }

        var deleted = Set<UUID>(), routinesTouched = Set<UUID>()
        for o in occurrences {
            let dueToday = o.dueDayKey == dayKey
            let doneAheadToday = o.completedDayKey == dayKey && o.dueDayKey > dayKey
            if dueToday || doneAheadToday {
                affected.insert(o.id); deleted.insert(o.id)
                if let id = o.routineID { routinesTouched.insert(id) }
                context.delete(o)
                result.occurrences += 1
            } else if o.completedDayKey == dayKey {
                // An earlier round, made up today: it is open again, still owing what it owed.
                o.completedDayKey = nil; o.awardedPoints = nil; o.completedAt = nil
                affected.insert(o.id)
                if let id = o.routineID { routinesTouched.insert(id) }
                result.reopened += 1
            }
        }
        // What a deleted occurrence stood in for comes back.
        for o in occurrences where o.replacedByID.map(deleted.contains) == true {
            o.skipped = false
            o.replacedByID = nil
        }

        for entry in ledger where entry.refID.map(affected.contains) == true {
            context.delete(entry)
            result.ledgerEntries += 1
        }
        for r in try context.fetch(FetchDescriptor<QuestRating>()) where r.questID.map(affected.contains) == true {
            context.delete(r); result.feedback += 1
        }
        for c in try context.fetch(FetchDescriptor<QuestComment>()) where c.questID.map(affected.contains) == true {
            context.delete(c); result.feedback += 1
        }
        if let dayContext { context.delete(dayContext) }

        // Cooldowns the day started, and the routines' last completion.
        for t in try context.fetch(FetchDescriptor<QuestTemplate>()) {
            if t.lastCompletedDayKey == dayKey { t.lastCompletedDayKey = nil }
            if t.lastServedDayKey == dayKey { t.lastServedDayKey = nil }
        }
        for r in try context.fetch(FetchDescriptor<RoutineTask>()) where routinesTouched.contains(r.id) {
            r.lastCompletedDayKey = occurrences
                .filter { $0.routineID == r.id && !deleted.contains($0.id) }
                .compactMap(\.completedDayKey).max()
        }
        try Affinity.sync(context)
        try context.save()

        // The day, generated again from the same body inputs.
        _ = try DayService.ensureToday(context, now: now, in: timeZone, inputs: inputs ?? DayInputs(), rng: &rng)
        return result
    }

    public struct Result: Equatable, Sendable {
        public var questsReopened: Int
        public var hiddenRemoved: Int
        public var ledgerEntriesDeleted: Int

        public var description: String {
            "Reopened \(questsReopened) quest(s), removed \(hiddenRemoved) hidden, "
            + "deleted \(ledgerEntriesDeleted) ledger entr(ies)"
        }
    }

    @discardableResult
    public static func reopen(_ context: ModelContext, dayKey: String) throws -> Result {
        var result = Result(questsReopened: 0, hiddenRemoved: 0, ledgerEntriesDeleted: 0)
        let quests = try DayService.quests(on: dayKey, in: context)
        let questIDs = Set(quests.map(\.id))

        for entry in try context.fetch(FetchDescriptor<LedgerEntry>())
        where entry.refID.map(questIDs.contains) == true {
            context.delete(entry)
            result.ledgerEntriesDeleted += 1
        }

        for quest in quests {
            // The completion stamp on the template came from this very day, so clearing it puts
            // the cooldown back where it was. Read before the row is deleted below.
            for template in try Completion.templates(of: quest, in: context)
            where template.lastCompletedDayKey == dayKey {
                template.lastCompletedDayKey = nil
            }

            if quest.isHiddenSlot {
                // The hidden slot is drawn at most once a day, keyed on the row existing at all —
                // so reopening it means removing the row, not clearing its fields.
                context.delete(quest)
                result.hiddenRemoved += 1
                continue
            }

            quest.points = nil
            quest.completedAt = nil
            quest.trivialDone = quest.trivialDone.map { _ in false }
            result.questsReopened += 1
        }

        try context.save()
        return result
    }
}
