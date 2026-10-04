import Foundation

/// One day of the journal as the history list reads it.
public struct JournalDay: Identifiable {
    public let dayKey: String
    /// Every turn of the day in index order, the safety line left out. Skipped and misfit turns
    /// stay: the page may show that a question was passed.
    public let turns: [JournalTurn]
    /// The turns that make it into `text`, the same count `JournalProgress` shows.
    public let answeredCount: Int
    /// The first answer, on one line and cut to `JournalHistory.previewLength` characters.
    public let preview: String
    public let isClosed: Bool
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

    public var id: String { dayKey }

    /// The beginning of what the user wrote, on one line, for a card that shows a few lines. Cut
    /// at a word boundary when the cut has one past its first half (text with no spaces, as in
    /// Chinese, is cut at `limit` characters), with an ellipsis only when something was left out.
    public func excerpt(limit: Int) -> String {
        let line = JournalComposer.written(turns).map(\.answer).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard line.count > limit else { return line }
        let head = line.prefix(limit)
        var cut = head
        if !line[line.index(line.startIndex, offsetBy: limit)].isWhitespace,
           let space = head.lastIndex(of: " "), head.distance(from: head.startIndex, to: space) >= limit / 2 {
            cut = head[..<space]
        }
        let loose = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",;:-"))
        return String(cut).trimmingCharacters(in: loose) + "\u{2026}"
    }
}

/// The days that have something written, newest first. Pure, like the planner: the list is a
/// function of the turns it is given, so it can not disagree with what the journal composes.
public enum JournalHistory {
    public static let previewLength = 80

    /// A day appears when at least one turn of it is written (answered, not the safety line, not
    /// blank); a day of only skipped turns has nothing to read back and is left out.
    public static func days(from turns: [JournalTurn], language: JournalLanguage) -> [JournalDay] {
        Dictionary(grouping: turns, by: \.dayKey)
            .sorted { $0.key > $1.key }
            .compactMap { dayKey, rows in
                let ordered = rows.sorted { $0.index < $1.index }
                let written = JournalComposer.written(ordered)
                guard let first = written.first else { return nil }
                return JournalDay(dayKey: dayKey,
                                  turns: ordered.filter { $0.kind != .safety },
                                  answeredCount: written.count,
                                  preview: preview(of: first.answer),
                                  isClosed: JournalProgress.isClosed(ordered),
                                  text: JournalComposer.text(turns: ordered, language: language),
                                  wordCount: written.reduce(0) { $0 + JournalWords.count($1.answer) },
                                  writtenAt: written.last?.answeredAt ?? first.answeredAt,
                                  writingSeconds: ordered.reduce(0) { $0 + $1.writingSeconds })
            }
    }

    /// The days either side of `dayKey` that have writing: the newest one older than it and the
    /// oldest one newer. `dayKey` itself need not be in `days`.
    public static func neighbors(of dayKey: String, in days: [JournalDay]) -> (previous: String?, next: String?) {
        let keys = days.map(\.dayKey)
        return (keys.filter { $0 < dayKey }.max(), keys.filter { $0 > dayKey }.min())
    }

    static func preview(of answer: String) -> String {
        let line = answer.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return line.count > previewLength ? String(line.prefix(previewLength)) + "…" : line
    }
}
