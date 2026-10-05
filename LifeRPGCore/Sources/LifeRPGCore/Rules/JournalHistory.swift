import Foundation

/// One day of the journal, as the reading page, the Today card, the calendar and Trends read it.
public struct JournalDay {
    public let dayKey: String
    /// Every turn of the day in index order, the safety line left out. Skipped and misfit turns
    /// stay: the page may show that a question was passed.
    public let turns: [JournalTurn]
    /// What `JournalComposer` makes of the day, the text that goes to Apple Journal.
    public let text: String
    /// The user's words in the day: `JournalWords.count` of every written answer. Not of `text`,
    /// whose title and question lines are not the user's, so the number agrees with the live count
    /// of the writing page.
    public let wordCount: Int
    /// When the day's last written turn was answered, which for free writing is the last save: the
    /// time the reading page shows.
    public let writtenAt: Date
    /// The active writing time of the day, summed over its turns (`JournalTurn.writingSeconds`).
    public let writingSeconds: Int

    /// The beginning of what the user wrote, on one line, for a card that shows a few lines. Cut
    /// at a word boundary when the cut has one past its first half (text with no spaces, as in
    /// Chinese, is cut at `limit` characters), with an ellipsis only when something was left out.
    public func excerpt(limit: Int) -> String {
        JournalExcerpt.cut(JournalComposer.written(turns).map(\.answer), limit: limit)
    }
}

/// The days that have something written, newest first. Pure, like the planner: the list is a
/// function of the turns it is given, so it can not disagree with what the journal composes.
public enum JournalHistory {
    /// A day appears when at least one turn of it is written (answered, not the safety line, not
    /// blank); a day of only skipped turns has nothing to read back and is left out.
    public static func days(from turns: [JournalTurn], language: JournalLanguage) -> [JournalDay] {
        Dictionary(grouping: turns, by: \.dayKey)
            .sorted { $0.key > $1.key }
            .compactMap { dayKey, rows in
                let ordered = rows.sorted { $0.index < $1.index }
                let written = JournalComposer.written(ordered)
                guard let last = written.last else { return nil }
                return JournalDay(dayKey: dayKey,
                                  turns: ordered.filter { $0.kind != .safety },
                                  text: JournalComposer.text(turns: ordered, language: language),
                                  wordCount: written.reduce(0) { $0 + JournalWords.count($1.answer) },
                                  writtenAt: last.answeredAt,
                                  writingSeconds: ordered.reduce(0) { $0 + $1.writingSeconds })
            }
    }

    /// The days either side of `dayKey` that have writing: the newest one older than it and the
    /// oldest one newer. `dayKey` itself need not be in `days`.
    public static func neighbors(of dayKey: String, in days: [JournalDay]) -> (previous: String?, next: String?) {
        let keys = days.map(\.dayKey)
        return (keys.filter { $0 < dayKey }.max(), keys.filter { $0 > dayKey }.min())
    }
}
