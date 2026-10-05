import Foundation

/// The all-entries page: the header lines, the dark "Tonight" card, and the entries newest first in
/// month sections. A pure function of the day snapshots and the query, so the view only places it.
public enum JournalEntriesList {
    /// One entry's row: the day at the left, the first thing written, how much, and a tag when the
    /// entry has prompt blocks.
    public struct Row: Equatable, Sendable {
        public let dayKey: String
        public let dayNumber: Int
        public let weekday: String
        public let preview: String
        public let words: String
        public let promptTag: String?
    }

    public struct Section: Equatable, Sendable {
        public let monthKey: String
        /// "October", or "October 2025" for a month of another year than today's.
        public let label: String
        public let rows: [Row]
    }

    /// Today's entry while it is still a draft: shown as the dark card at the top, and not again as a row.
    public struct Tonight: Equatable, Sendable {
        public let dayKey: String
        public let detail: String
    }

    public struct Page: Equatable, Sendable {
        public let subtitle: String
        public let tonight: Tonight?
        public let sections: [Section]
        /// What to say when there is nothing to list: no entries, or none that match the query.
        public let emptyText: String?
    }

    /// `days` is `JournalEntryHistory.days`. A blank query lists everything; otherwise the dark card is
    /// set aside and every match is a row, today's draft included.
    public static func page(days: [JournalEntryDay], today: String, query: String,
                            language: JournalLanguage = .system, timeZone: TimeZone = .current) -> Page {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let searching = !needle.isEmpty
        let streak = JournalTrends.Writing(days: days, range: JournalTrends.DayRange(first: "0001-01-01", last: today),
                                           timeZone: timeZone).writingStreak(asOf: today)

        var tonight: Tonight?
        var listed = days
        if searching {
            listed = days.filter { $0.matches(needle) }
        } else if let draft = days.first(where: { $0.dayKey == today && !$0.isDone }) {
            tonight = Tonight(dayKey: draft.dayKey,
                              detail: "\(JournalPageText.words(draft.wordCount)) \u{00B7} keep going")
            listed = days.filter { $0.dayKey != today }
        }

        let sections = JournalEntryHistory.monthGroups(listed).map { group in
            Section(monthKey: group.monthKey,
                    label: monthLabel(group.monthKey, today: today, language: language, timeZone: timeZone),
                    rows: group.days.map { row($0, language: language, timeZone: timeZone) })
        }
        let empty: String? = sections.isEmpty && tonight == nil
            ? (searching ? "No entries match \u{201C}\(needle)\u{201D}." : "Nothing written yet.") : nil
        return Page(subtitle: subtitle(entries: days.count, streak: streak), tonight: tonight,
                    sections: sections, emptyText: empty)
    }

    /// "57 entries · 16 night streak"; a streak of 0 is left out rather than announced.
    public static func subtitle(entries: Int, streak: Int) -> String {
        guard entries > 0 else { return "No entries yet" }
        let count = "\(entries) \(entries == 1 ? "entry" : "entries")"
        return streak > 0 ? "\(count) \u{00B7} \(streak) night streak" : count
    }

    /// The calendar card's line under "All journal entries".
    public static func cardLine(entries: Int) -> String {
        entries > 0 ? "\(entries) \(entries == 1 ? "entry" : "entries"), newest first" : "Nothing written yet"
    }

    private static func row(_ day: JournalEntryDay, language: JournalLanguage, timeZone: TimeZone) -> Row {
        Row(dayKey: day.dayKey,
            dayNumber: Int(day.dayKey.suffix(2)) ?? 0,
            weekday: JournalPageText.format(dayKey: day.dayKey, template: "EEE", language: language, timeZone: timeZone),
            preview: day.preview,
            words: JournalPageText.words(day.wordCount),
            promptTag: day.promptCount > 0 ? "\(day.promptCount) \(day.promptCount == 1 ? "prompt" : "prompts")" : nil)
    }

    private static func monthLabel(_ monthKey: String, today: String, language: JournalLanguage,
                                   timeZone: TimeZone) -> String {
        let sameYear = monthKey.prefix(4) == today.prefix(4)
        return JournalPageText.format(dayKey: monthKey + "-01", template: sameYear ? "MMMM" : "MMMMy",
                                      language: language, timeZone: timeZone)
    }
}
