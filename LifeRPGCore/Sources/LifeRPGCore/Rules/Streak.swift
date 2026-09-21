import Foundation
import SwiftData

/// Consecutive days with **at least one random quest completed** (`PLAN.md` §3).
///
/// Regular slots, the T group and hidden all count; routines and the epic do not. Nothing is
/// stored — the run is recomputed from the completed `DailyQuest` rows, so a correction to
/// history can never leave a stale counter behind.
public enum Streak {
    /// Days that count, newest first is irrelevant — this is the set the walk-back uses.
    ///
    /// The rule lives **only** here. The today page hands in its own `@Query` array rather than
    /// re-filtering, so the HUD's number and Core's number cannot drift apart.
    public static func completedDayKeys(_ quests: [DailyQuest]) -> Set<String> {
        Set(quests
            .filter { $0.completedAt != nil && $0.slot != .epic && !$0.replaced }
            .map(\.dayKey))
    }

    public static func completedDayKeys(_ context: ModelContext) throws -> Set<String> {
        completedDayKeys(try context.fetch(
            FetchDescriptor<DailyQuest>(predicate: #Predicate { $0.completedAt != nil })))
    }

    public static func current(_ context: ModelContext, today: String,
                               in timeZone: TimeZone = .current) throws -> Int {
        current(days: try completedDayKeys(context), today: today, in: timeZone)
    }

    /// Walks back from today. If today has no completion yet the run is measured from yesterday,
    /// so the number doesn't read 0 all morning and then jump back up in the evening; it only
    /// breaks once a whole day has passed with nothing done.
    public static func current(days: Set<String>, today: String,
                               in timeZone: TimeZone = .current) -> Int {
        var cursor = today
        if !days.contains(cursor) {
            guard let yesterday = DayKey.adding(-1, to: today, in: timeZone) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor), count < 3660 {
            count += 1
            guard let previous = DayKey.adding(-1, to: cursor, in: timeZone) else { break }
            cursor = previous
        }
        return count
    }
}
