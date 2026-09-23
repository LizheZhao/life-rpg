import Foundation

/// Which day of a period a day is (`PLAN.md` §5).
///
/// The first three days hold the tier down to `low`, which is what makes the day's composition
/// easier and swaps routines for their downgrade version — there is no separate cycle rule
/// anywhere else. Counting is by **calendar days from the day the round started**, not by how
/// many flow entries were logged: a day missed in the app still counts as day 2.
public enum Cycle {
    /// A flow day this far apart (or closer) still belongs to the same round. One missing day in
    /// the middle is a missed log, not a new period.
    public static let gapTolerance = 1
    /// How many days a round is counted for once logging stops — the days this rule is about.
    public static let earlyDays = 3

    /// The day of the period `dayKey` falls on, 1-based, or nil when it is outside one.
    ///
    /// `flowDays` are the days with a `menstrualFlow` entry other than "none"; the app reads a
    /// couple of weeks of them. A day with flow always counts. A day **without** one counts only
    /// while it is still inside the first `earlyDays` of a round that has started, so a period
    /// that was logged once and then forgotten doesn't hold the tier down indefinitely.
    public static func day(on dayKey: String, flowDays: Set<String>,
                           in timeZone: TimeZone = .current) -> Int? {
        let earlier = flowDays.filter { $0 <= dayKey }
        guard let latest = earlier.max() else { return nil }

        var start = latest
        while let previous = earlier
            .filter({ $0 < start })
            .max(by: { $0 < $1 }),
            let gap = DayKey.daysBetween(previous, start, in: timeZone),
            gap <= gapTolerance + 1 {
            start = previous
        }

        guard let offset = DayKey.daysBetween(start, dayKey, in: timeZone), offset >= 0 else { return nil }
        let day = offset + 1
        if flowDays.contains(dayKey) { return day }
        return day <= earlyDays ? day : nil
    }
}
