import Foundation

/// The journal mark under a written day on the month calendar, darker when the entry is longer.
public enum JournalMarks {
    /// Below this many written days a third of them means nothing, so every written day is
    /// medium rather than one of them being called the longest.
    static let minimumDaysForShading = 3

    /// `dayKey` to 1...3 for every written day. The thirds are of all written days rather than the
    /// month on screen, so a day's shade does not change when the page moves to another month.
    public static func levels(days: [JournalDay]) -> [String: Int] {
        let words = days.map(\.wordCount)
        return Dictionary(days.map { day in
            let level = words.count < minimumDaysForShading
                ? 2
                // A written day always has a mark, even one that is all emoji and counts no words.
                : max(1, JournalTrends.Year.level(forWords: day.wordCount, among: words))
            return (day.dayKey, level)
        }, uniquingKeysWith: max)
    }
}
