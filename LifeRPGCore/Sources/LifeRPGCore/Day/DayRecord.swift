import Foundation
import SwiftData

/// Everything the day detail sheet shows about one past (or current) day (`PLAN.md` §9).
///
/// Built from history rows only — `DailyQuest`, `RoutineOccurrence`, `LedgerEntry`,
/// `QuestRating`, `DailyContext` — never from templates, so it reads the same after a template is
/// edited or deactivated.
public struct DayRecord {
    public struct QuestLine: Identifiable {
        public let quest: DailyQuest
        /// Ratings given right after this completion (`QuestRating.questID`), oldest first.
        public let ratings: [QuestRating]
        public var id: UUID { quest.id }
    }

    public enum RoutineStatus: Equatable, Sendable {
        case done
        case doneAhead(on: String)        // completed earlier in the week, before its due day
        case late(on: String)             // made up on day 2 or 3, at half pay
        case skipped                      // by hand, or automatically on day 4
        case notDone
    }

    public struct RoutineLine: Identifiable {
        public let occurrence: RoutineOccurrence
        public let status: RoutineStatus
        public let ratings: [QuestRating]
        public var id: UUID { occurrence.id }
    }

    public let dayKey: String
    public let context: DailyContext?
    /// The epic first, then the regular slots easiest first, then the hidden quest.
    public let quests: [QuestLine]
    /// Routines due on this day, whenever (or whether) they were done.
    public let routines: [RoutineLine]
    /// Routines completed on this day but due on another: late make-ups and flexible ones done
    /// ahead. Listed here as well, since this is the day the work (and the ledger entry) happened.
    public let completedForOtherDays: [RoutineLine]
    /// This day's ledger entries other than quest / routine payouts, which the lines above
    /// already show: redemptions, rerolls, penalties, skips, adjustments, the grant.
    public let otherLedger: [LedgerEntry]
    /// Ratings dated this day that aren't linked to any line above.
    public let otherRatings: [QuestRating]
    /// Net points booked to this day — every ledger entry with its `dayKey`, spending included.
    public let netPoints: Int

    public init(dayKey: String,
                quests: [DailyQuest],
                occurrences: [RoutineOccurrence],
                ledger: [LedgerEntry],
                ratings: [QuestRating],
                contexts: [DailyContext]) {
        self.dayKey = dayKey
        self.context = contexts.first { $0.dayKey == dayKey }

        let byQuestID = Dictionary(grouping: ratings.filter { $0.questID != nil }, by: { $0.questID! })
            .mapValues { $0.sorted { $0.timestamp < $1.timestamp } }

        func order(_ q: DailyQuest) -> Int {
            if q.slot == .epic { return -1 }
            if q.isHiddenSlot { return 99 }
            return Difficulty.allCases.firstIndex(of: q.slot) ?? 50
        }
        self.quests = quests
            .filter { $0.dayKey == dayKey }
            .sorted { (order($0), $0.textSnapshot) < (order($1), $1.textSnapshot) }
            .map { QuestLine(quest: $0, ratings: byQuestID[$0.id] ?? []) }

        func line(_ o: RoutineOccurrence) -> RoutineLine {
            RoutineLine(occurrence: o, status: Self.status(of: o), ratings: byQuestID[o.id] ?? [])
        }
        self.routines = occurrences
            .filter { $0.dueDayKey == dayKey }
            .sorted { $0.textSnapshot < $1.textSnapshot }
            .map(line)
        self.completedForOtherDays = occurrences
            .filter { $0.completedDayKey == dayKey && $0.dueDayKey != dayKey }
            .sorted { ($0.dueDayKey, $0.textSnapshot) < ($1.dueDayKey, $1.textSnapshot) }
            .map(line)

        let dayLedger = ledger.filter { $0.dayKey == dayKey }
        let payouts: Set<String> = [Economy.Kind.quest.rawValue, Economy.Kind.routine.rawValue]
        self.otherLedger = dayLedger
            .filter { !payouts.contains($0.kind) }
            .sorted { $0.timestamp < $1.timestamp }
        self.netPoints = Economy.balance(dayLedger)

        let linked = Set(self.quests.map(\.id) + self.routines.map(\.id) + self.completedForOtherDays.map(\.id))
        self.otherRatings = ratings
            .filter { $0.dayKey == dayKey && !($0.questID.map(linked.contains) ?? false) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    public static func status(of o: RoutineOccurrence) -> RoutineStatus {
        if o.skipped { return .skipped }
        guard let done = o.completedDayKey else { return .notDone }
        if done == o.dueDayKey { return .done }
        return done < o.dueDayKey ? .doneAhead(on: done) : .late(on: done)
    }

    /// Reads the rows for one day out of the store.
    public static func load(_ dayKey: String, in context: ModelContext) throws -> DayRecord {
        let quests = try context.fetch(FetchDescriptor<DailyQuest>(
            predicate: #Predicate { $0.dayKey == dayKey }))
        let occurrences = try context.fetch(FetchDescriptor<RoutineOccurrence>(
            predicate: #Predicate { $0.dueDayKey == dayKey || $0.completedDayKey == dayKey }))
        let ledger = try context.fetch(FetchDescriptor<LedgerEntry>(
            predicate: #Predicate { $0.dayKey == dayKey }))
        let contexts = try context.fetch(FetchDescriptor<DailyContext>(
            predicate: #Predicate { $0.dayKey == dayKey }))
        // A rating is linked by id, and can be dated a day after its completion (rated just past
        // midnight), so the small rating log is read whole rather than filtered by day.
        let ratings = try context.fetch(FetchDescriptor<QuestRating>())
        return DayRecord(dayKey: dayKey, quests: quests, occurrences: occurrences,
                         ledger: ledger, ratings: ratings, contexts: contexts)
    }
}
