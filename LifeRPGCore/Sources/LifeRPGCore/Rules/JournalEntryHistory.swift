import Foundation

/// One day's entry as the reader, the calendar and the entries list read it: a snapshot of the row,
/// with everything but the document derived from it.
public struct JournalEntryDay: Equatable, Sendable {
    public let dayKey: String
    public let document: JournalDocument
    public let isDone: Bool
    /// `JournalEntry.updatedAt`: the time the reader shows as written.
    public let writtenAt: Date
    /// `JournalEntry.createdAt`: when the day's entry was started, which is the hour Trends calls
    /// the usual one. Later edits do not move it.
    public let createdAt: Date

    /// `createdAt` left out reads as `writtenAt`, so a caller that only knows one time is not forced
    /// to invent a second.
    public init(dayKey: String, document: JournalDocument, isDone: Bool, writtenAt: Date, createdAt: Date? = nil) {
        self.dayKey = dayKey
        self.document = document
        self.isDone = isDone
        self.writtenAt = writtenAt
        self.createdAt = createdAt ?? writtenAt
    }

    public init(_ entry: JournalEntry) {
        self.init(dayKey: entry.dayKey, document: entry.document, isDone: entry.isDone,
                  writtenAt: entry.updatedAt, createdAt: entry.createdAt)
    }

    public var wordCount: Int { document.wordCount }
    public var promptCount: Int { document.promptCount }

    /// The two-line preview of a list row (`JournalDocument.preview`).
    public var preview: String { document.preview() }

    public func excerpt(limit: Int) -> String { document.excerpt(limit: limit) }

    /// What goes to Apple Journal (`JournalDocument.plainText`).
    public func plainText() -> String { document.plainText() }

    /// Whether `query` is in a text, an answer or a question, ignoring case and diacritics. A blank
    /// query matches everything.
    public func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return document.blocks.contains { block in
            if block.writtenText.range(of: needle, options: options) != nil { return true }
            guard case .prompt(_, let question, _, _, _) = block else { return false }
            return question.range(of: needle, options: options) != nil
        }
    }
}

/// The days that have an entry, newest first. Pure: the lists are a function of the rows they are
/// given.
public enum JournalEntryHistory {
    /// A month of the entries list: `monthKey` is `"2026-10"`.
    public struct MonthGroup: Equatable, Sendable {
        public let monthKey: String
        public let days: [JournalEntryDay]
    }

    /// An entry appears when something is written in it. A day that somehow has two rows shows the
    /// one saved last.
    public static func days(from entries: [JournalEntry]) -> [JournalEntryDay] {
        Dictionary(grouping: entries, by: \.dayKey)
            .compactMap { $0.value.max { $0.updatedAt < $1.updatedAt } }
            .map(JournalEntryDay.init)
            .filter { !$0.document.isEmpty }
            .sorted { $0.dayKey > $1.dayKey }
    }

    /// The days either side of `dayKey` that have an entry: the newest one older than it and the
    /// oldest one newer. `dayKey` itself need not be in `days`.
    public static func neighbors(of dayKey: String, in days: [JournalEntryDay]) -> (previous: String?, next: String?) {
        let keys = days.map(\.dayKey)
        return (keys.filter { $0 < dayKey }.max(), keys.filter { $0 > dayKey }.min())
    }

    /// `days` grouped by the month of their `dayKey`, newest month first and newest day first
    /// inside it.
    public static func monthGroups(_ days: [JournalEntryDay]) -> [MonthGroup] {
        Dictionary(grouping: days) { String($0.dayKey.prefix(7)) }
            .map { MonthGroup(monthKey: $0.key, days: $0.value.sorted { $0.dayKey > $1.dayKey }) }
            .sorted { $0.monthKey > $1.monthKey }
    }
}
