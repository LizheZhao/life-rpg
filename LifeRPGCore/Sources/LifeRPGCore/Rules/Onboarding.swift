import Foundation
import SwiftData

/// When the first-launch intro is shown: to someone new, on a phone with no record of the app
/// being used. A restored backup or a phone already in use skips it; erasing every record (a new
/// person starting) clears the app's flag, so the intro comes back.
public enum Onboarding {
    /// The person has used the app here: a quest or routine finished, or a day written. A drawn
    /// day, scheduled routines and the opening balance are the app's doing, so they don't count.
    public static func hasHistory(in context: ModelContext) throws -> Bool {
        if try context.fetchCount(FetchDescriptor<DailyQuest>(predicate: #Predicate { $0.completedAt != nil })) > 0 {
            return true
        }
        if try context.fetchCount(FetchDescriptor<RoutineOccurrence>(predicate: #Predicate { $0.completedDayKey != nil })) > 0 {
            return true
        }
        return try context.fetch(FetchDescriptor<JournalEntry>()).contains { !$0.document.isEmpty }
    }

    /// `introDone` is the app's flag: set when the intro is finished or skipped for history.
    public static func shouldShow(introDone: Bool, in context: ModelContext) throws -> Bool {
        guard !introDone else { return false }
        return try !hasHistory(in: context)
    }
}
