import Foundation

/// The summary line on the Today page's journal card.
public enum JournalToday {
    /// The most recent earlier day with writing, for "Last night · 412 words".
    public struct LastNight: Equatable, Sendable {
        public let dayKey: String
        public let words: Int
    }

    public enum Summary: Equatable, Sendable {
        /// Nothing written today. `lastNight` is the newest earlier day with writing, if any.
        case notStarted(lastNight: LastNight?)
        case written(words: Int)
    }

    /// `days` is `JournalHistory.days`: only days with writing are in it, so today being in it is
    /// today having written text.
    public static func summary(days: [JournalDay], today: String) -> Summary {
        if let day = days.first(where: { $0.dayKey == today }) { return .written(words: day.wordCount) }
        let last = days.filter { $0.dayKey < today }.max { $0.dayKey < $1.dayKey }
        return .notStarted(lastNight: last.map { LastNight(dayKey: $0.dayKey, words: $0.wordCount) })
    }
}
