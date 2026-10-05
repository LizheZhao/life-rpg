import Foundation

/// The words the editor and the reader put around the user's text. Every choice of what to say
/// (the date line, which tag is left out) is made here so the views only place strings.
public enum JournalPageText {
    /// "1 word", "412 words".
    public static func words(_ count: Int) -> String { "\(count) \(count == 1 ? "word" : "words")" }

    /// The writing page's heading: the day and the moment it is written in, "Sunday, October 4 · tonight".
    public static func writingHeading(dayKey: String, evening: Bool, language: JournalLanguage,
                                      timeZone: TimeZone = .current) -> String {
        let moment = language == .zhHans ? (evening ? "今晚" : "今天") : (evening ? "tonight" : "today")
        return "\(dateText(dayKey: dayKey, language: language, timeZone: timeZone)) · \(moment)"
    }

    /// The editor's date line: today's entry is "Sunday, October 4 · tonight", any other day
    /// is its weekday and date. `today` is the app day (`JournalEntries.entryDayKey`).
    public static func editorHeading(dayKey: String, today: String, language: JournalLanguage,
                                     timeZone: TimeZone = .current) -> String {
        dayKey == today ? writingHeading(dayKey: dayKey, evening: true, language: language, timeZone: timeZone)
                        : dateText(dayKey: dayKey, language: language, timeZone: timeZone)
    }

    /// The reader's heading for an entry: the day and the time it was last written, "Thursday, October 1 · 11:14 PM".
    public static func readingHeading(entry: JournalEntryDay, language: JournalLanguage,
                                      timeZone: TimeZone = .current) -> String {
        let clock = DateFormatter()
        clock.locale = locale(language)
        clock.timeZone = timeZone
        clock.timeStyle = .short
        clock.dateStyle = .none
        return "\(dateText(dayKey: entry.dayKey, language: language, timeZone: timeZone)) \u{00B7} \(clock.string(from: entry.writtenAt))"
    }

    /// The reading page's heading for a day with nothing written (none, or just cleared): the date alone.
    public static func dateHeading(dayKey: String, language: JournalLanguage, timeZone: TimeZone = .current) -> String {
        dateText(dayKey: dayKey, language: language, timeZone: timeZone)
    }

    /// The short date of a neighbour button: "Sep 30".
    public static func shortDate(dayKey: String, language: JournalLanguage, timeZone: TimeZone = .current) -> String {
        format(dayKey: dayKey, template: "MMMd", language: language, timeZone: timeZone)
    }

    /// The tags under the reader's heading: the user's words, what was done, what kind of day it was.
    /// "0 quests done" is left out (a quiet day is not a score), and so is a day with no context.
    /// With no facts (not read yet) only the words show.
    public static func chips(entry: JournalEntryDay, facts: JournalDayFacts?) -> [String] {
        var chips = [words(entry.wordCount)]
        guard let facts else { return chips }
        if facts.completed > 0 { chips.append("\(facts.completed) \(facts.completed == 1 ? "quest" : "quests") done") }
        if let tier = facts.tierText { chips.append(tier) }
        return chips
    }

    private static func dateText(dayKey: String, language: JournalLanguage, timeZone: TimeZone) -> String {
        format(dayKey: dayKey, template: "EEEEMMMMd", language: language, timeZone: timeZone)
    }

    private static func format(dayKey: String, template: String, language: JournalLanguage,
                               timeZone: TimeZone) -> String {
        guard let date = DayKey.date(dayKey, in: timeZone) else { return dayKey }
        let formatter = DateFormatter()
        formatter.locale = locale(language)
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    /// Fixed per language, like `LifeCalendar`: the region setting does not reorder the heading.
    private static func locale(_ language: JournalLanguage) -> Locale {
        Locale(identifier: language == .zhHans ? "zh_Hans_CN" : "en_US")
    }
}
