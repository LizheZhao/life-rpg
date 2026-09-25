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

    /// Missed days covered by a streak freeze. A `freeze` ledger entry is booked to the day it
    /// covers, so this is just their `dayKey`s.
    public static func frozenDayKeys(_ ledger: [LedgerEntry]) -> Set<String> {
        Set(ledger.filter { $0.kind == Economy.Kind.freeze.rawValue }.map(\.dayKey))
    }

    public static func frozenDayKeys(_ context: ModelContext) throws -> Set<String> {
        let kind = Economy.Kind.freeze.rawValue
        return frozenDayKeys(try context.fetch(
            FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.kind == kind })))
    }

    public static func current(_ context: ModelContext, today: String,
                               in timeZone: TimeZone = .current) throws -> Int {
        current(days: try completedDayKeys(context), frozen: try frozenDayKeys(context),
                today: today, in: timeZone)
    }

    /// Walks back from today. If today has no completion yet the run is measured from yesterday,
    /// so the number doesn't read 0 all morning and then jump back up in the evening; it only
    /// breaks once a whole day has passed with nothing done.
    ///
    /// A frozen day bridges the run without adding to it: the freeze keeps the streak from
    /// breaking (`PLAN.md` §3), it doesn't pretend the day was done.
    public static func current(days: Set<String>, frozen: Set<String> = [], today: String,
                               in timeZone: TimeZone = .current) -> Int {
        walk(days: days, frozen: frozen, today: today, in: timeZone).count
    }

    /// The missed day a freeze would cover right now, or nil.
    ///
    /// Decided with the user: a freeze is bought **after** the streak breaks, to patch it. It can
    /// only patch the day where the current run stops, and only when that is a single missed day
    /// with a completed day right behind it — one freeze covers one day, so a two-day gap stays
    /// broken.
    public static func repairableDay(days: Set<String>, frozen: Set<String> = [], today: String,
                                     in timeZone: TimeZone = .current) -> String? {
        guard let gap = walk(days: days, frozen: frozen, today: today, in: timeZone).stoppedAt,
              gap < today,
              let before = DayKey.adding(-1, to: gap, in: timeZone),
              days.contains(before) else { return nil }
        return gap
    }

    /// The run ending today (or yesterday), and the first day behind it that neither was done nor
    /// is frozen.
    private static func walk(days: Set<String>, frozen: Set<String>, today: String,
                             in timeZone: TimeZone) -> (count: Int, stoppedAt: String?) {
        var cursor = today
        if !days.contains(cursor) {
            guard let yesterday = DayKey.adding(-1, to: today, in: timeZone) else { return (0, nil) }
            cursor = yesterday
        }
        var count = 0
        var steps = 0
        while days.contains(cursor) || frozen.contains(cursor), steps < 3660 {
            if days.contains(cursor) { count += 1 }
            steps += 1
            guard let previous = DayKey.adding(-1, to: cursor, in: timeZone) else { return (count, nil) }
            cursor = previous
        }
        return (count, cursor)
    }
}
