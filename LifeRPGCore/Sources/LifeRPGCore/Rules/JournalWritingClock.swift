import Foundation

/// "Writing for N min" on the free-writing page: active time, accumulated from the moments the
/// user types, so a page left open on the desk does not keep counting.
///
/// The gap between two keystrokes is the time spent on the first one: the thought before the next
/// word is writing, a long pause is not. A gap counts in full up to `maxGapSeconds`, and a longer
/// one counts as `maxGapSeconds` and no more. Pure, so the caller keeps the total and the last
/// keystroke (the total is what `JournalTurn.writingSeconds` stores) and feeds both back in.
public enum JournalWritingClock {
    public static let maxGapSeconds = 30

    /// The total after a keystroke at `now`, and the moment to measure the next gap from. A first
    /// keystroke (`lastActivity` nil) adds nothing.
    ///
    /// The total is whole seconds, so a gap under `maxGapSeconds` adds its whole seconds and the
    /// fraction is carried by moving the returned moment forward by only those seconds. Otherwise
    /// typing a fifth of a second apart would round every gap to 0 and never count.
    public static func adding(activityAt now: Date, to total: Int,
                              lastActivity: Date?) -> (total: Int, lastActivity: Date) {
        guard let last = lastActivity else { return (total, now) }
        let gap = now.timeIntervalSince(last)
        // A clock set back is not time spent.
        guard gap > 0 else { return (total, now) }
        if gap >= Double(maxGapSeconds) { return (total + maxGapSeconds, now) }
        let whole = Int(gap)
        return (total + whole, last.addingTimeInterval(Double(whole)))
    }
}
