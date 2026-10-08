import Foundation
import SwiftData

/// Starting over: everything the use of the app recorded goes, the library the person built stays.
///
/// For whoever has been trying the app (the author's own test days, a friend's first week) and now
/// wants a clean start. History, ratings, notes, rewards and the journal are deleted; the library
/// keeps its rows, edits, archived and switched-off marks, but what the history had written onto it
/// (cooldown and "last drawn" days, the average rating's `affinity`) is reset, since those would
/// otherwise keep quests out of the pool for days after a fresh start. The opening balance is not
/// given here: the app does that on its next pass, like on a first launch.
public enum EraseRecords {
    public struct Result: Equatable, Sendable {
        public var dailyQuests = 0
        public var routineOccurrences = 0
        public var ledgerEntries = 0
        public var dayContexts = 0
        public var ratings = 0
        public var comments = 0
        public var rewards = 0
        public var journalEntries = 0
        public var journalTurns = 0

        public init() {}

        /// What the confirmation card says: what goes, and what stays.
        public var message: String {
            var gone: [String] = []
            func add(_ n: Int, _ one: String, _ many: String) { if n > 0 { gone.append("\(n) \(n == 1 ? one : many)") } }
            add(dailyQuests + routineOccurrences, "quest or routine record", "quest and routine records")
            add(ledgerEntries, "coin entry", "coin entries")
            add(ratings + comments, "rating or note", "ratings and notes")
            add(rewards, "reward", "rewards")
            add(journalEntries + journalTurns, "journal entry", "journal entries")
            let list = gone.isEmpty ? "There is nothing to erase." : "This erases " + gone.joined(separator: ", ") + "."
            return list + " Your library stays, with your edits. This can't be undone: output records to JSON first if you may want them back."
        }
    }

    /// What `erase` would remove, without removing it.
    public static func preview(in context: ModelContext) throws -> Result {
        var r = Result()
        r.dailyQuests = try context.fetchCount(FetchDescriptor<DailyQuest>())
        r.routineOccurrences = try context.fetchCount(FetchDescriptor<RoutineOccurrence>())
        r.ledgerEntries = try context.fetchCount(FetchDescriptor<LedgerEntry>())
        r.dayContexts = try context.fetchCount(FetchDescriptor<DailyContext>())
        r.ratings = try context.fetchCount(FetchDescriptor<QuestRating>())
        r.comments = try context.fetchCount(FetchDescriptor<QuestComment>())
        r.rewards = try context.fetchCount(FetchDescriptor<Reward>())
        r.journalEntries = try context.fetchCount(FetchDescriptor<JournalEntry>())
        r.journalTurns = try context.fetchCount(FetchDescriptor<JournalTurn>())
        return r
    }

    @discardableResult
    public static func erase(in context: ModelContext) throws -> Result {
        let counts = try preview(in: context)
        do {
            try deleteAll(DailyQuest.self, in: context)
            try deleteAll(RoutineOccurrence.self, in: context)
            try deleteAll(LedgerEntry.self, in: context)
            try deleteAll(DailyContext.self, in: context)
            try deleteAll(QuestRating.self, in: context)
            try deleteAll(QuestComment.self, in: context)
            try deleteAll(Reward.self, in: context)
            try deleteAll(JournalEntry.self, in: context)
            try deleteAll(JournalTurn.self, in: context)
            for t in try context.fetch(FetchDescriptor<QuestTemplate>()) {
                t.lastServedDayKey = nil; t.lastCompletedDayKey = nil; t.affinity = 0
            }
            for r in try context.fetch(FetchDescriptor<RoutineTask>()) { r.lastCompletedDayKey = nil }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return counts
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
        for row in try context.fetch(FetchDescriptor<T>()) { context.delete(row) }
    }
}
