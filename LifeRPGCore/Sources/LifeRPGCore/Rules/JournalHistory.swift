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

    public var id: String { dayKey }
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
                                  text: JournalComposer.text(turns: ordered, language: language))
            }
    }

    static func preview(of answer: String) -> String {
        let line = answer.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return line.count > previewLength ? String(line.prefix(previewLength)) + "…" : line
    }
}
