import Foundation
import SwiftData

/// The journal's inputs read from the store. The day's facts the question step reads
/// (`JournalSignals`) are built here from the same history rows `DayRecord` reads. Writing the
/// journal is `JournalEntries`; nothing here writes.
public enum JournalService {
    /// The day's facts, read from the history rows the same way `DayRecord` reads them.
    public static func signals(on dayKey: String, in context: ModelContext,
                               timeZone: TimeZone = .current) throws -> JournalSignals {
        let skipKind = Economy.Kind.skip.rawValue
        let flexible = Set(try context.fetch(FetchDescriptor<RoutineTask>()).filter(\.flexibleWithinWeek).map(\.id))
        return JournalSignals(
            dayKey: dayKey,
            quests: try DayService.quests(on: dayKey, in: context),
            occurrences: try context.fetch(FetchDescriptor<RoutineOccurrence>()),
            context: try DayService.dailyContext(for: dayKey, in: context),
            ratings: try context.fetch(FetchDescriptor<QuestRating>()),
            ledger: try context.fetch(FetchDescriptor<LedgerEntry>(
                predicate: #Predicate { $0.kind == skipKind && $0.dayKey == dayKey })),
            flexible: flexible,
            timeZone: timeZone)
    }
}
