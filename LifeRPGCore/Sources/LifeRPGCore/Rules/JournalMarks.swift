import Foundation

/// The journal mark under a written day on the month calendar, darker when the entry is longer.
public enum JournalMarks {
    /// The calendar glyph's shade for one entry, by fixed bands rather than by thirds of the days
    /// written: under 100 words is 1, 100 to 299 is 2, 300 and up is 3. A written entry always has a
    /// mark, even one that is all emoji and counts no words.
    public static func level(forWords words: Int) -> Int {
        words < 100 ? 1 : words < 300 ? 2 : 3
    }

    /// `dayKey` to 1...3 for every entry day.
    public static func levels(entryDays: [JournalEntryDay]) -> [String: Int] {
        Dictionary(entryDays.map { ($0.dayKey, level(forWords: $0.wordCount)) }, uniquingKeysWith: max)
    }
}
