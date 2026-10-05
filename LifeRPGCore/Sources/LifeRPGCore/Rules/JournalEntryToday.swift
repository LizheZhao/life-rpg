import Foundation

/// What the Today page says about the day's entry: the book icon's badge, the "Write about today"
/// card's copy and when the card shows.
public enum JournalEntryToday {
    public enum State: Equatable, Sendable {
        /// No row: nothing was written, or it was cleared.
        case none
        case draft(words: Int)
        case done(words: Int)
    }

    /// The mark on the book icon.
    public enum IconBadge: Equatable, Sendable {
        case none, dot, check
    }

    /// The card shows from this hour of the evening, and until the day rolls over at
    /// `LifeCalendar.dayStartHour`.
    public static let cardStartHour = 20

    public static func state(of entry: JournalEntry?) -> State {
        guard let entry else { return .none }
        return entry.isDone ? .done(words: entry.wordCount) : .draft(words: entry.wordCount)
    }

    /// A dot for a draft with words in it, a check once done, nothing otherwise.
    public static func iconBadge(_ state: State) -> IconBadge {
        switch state {
        case .none: .none
        case .draft(let words): words > 0 ? .dot : .none
        case .done: .check
        }
    }

    /// "Start writing", "Keep going · N words", "Written · N words". English only: the spec gives no
    /// Chinese for the card.
    public static func cardCopy(_ state: State) -> String {
        func words(_ n: Int) -> String { n == 1 ? "1 word" : "\(n) words" }
        return switch state {
        case .none: "Start writing"
        case .draft(let n): "Keep going \u{00B7} \(words(n))"
        case .done(let n): "Written \u{00B7} \(words(n))"
        }
    }

    /// The card's line under its title.
    public static let cardSubtitle = "A blank page. Pull in a question whenever you want one."

    /// The newest entry before `today`, for "Last night · 412 words" on the card while today
    /// has no row. `days` is `JournalEntryHistory.days`.
    public struct LastNight: Equatable, Sendable {
        public let dayKey: String
        public let words: Int

        public var text: String { "Last night \u{00B7} \(JournalPageText.words(words))" }
    }

    public static func lastNight(in days: [JournalEntryDay], today: String) -> LastNight? {
        days.filter { $0.dayKey < today }.max { $0.dayKey < $1.dayKey }
            .map { LastNight(dayKey: $0.dayKey, words: $0.wordCount) }
    }

    /// Evening, in the user's own hours: from 20:00 until the 05:00 rollover (hours 20 to 23 and 0 to 4).
    /// The one clock rule behind the card, the editor's date line and every "tonight" label.
    public static func isEvening(now: Date, timeZone: TimeZone = .current) -> Bool {
        let hour = LifeCalendar.gregorian(timeZone).component(.hour, from: now)
        return hour >= cardStartHour || hour < LifeCalendar.dayStartHour
    }

    /// "tonight" in the evening, "today" by day: how the day's own entry is named.
    public static func moment(now: Date, timeZone: TimeZone = .current) -> String {
        isEvening(now: now, timeZone: timeZone) ? "tonight" : "today"
    }

    /// Whether the card shows: in the evening, and at any hour once the day is cleared.
    public static func cardVisible(now: Date, timeZone: TimeZone = .current, allCleared: Bool) -> Bool {
        allCleared || isEvening(now: now, timeZone: timeZone)
    }

    /// The Trends card's button.
    public static func writeButtonTitle(now: Date, timeZone: TimeZone = .current) -> String {
        "Write \(moment(now: now, timeZone: timeZone))'s entry"
    }

    /// Whether `dayKey` has been played out: at least one thing to do, and none of it still open
    /// (open is not completed and not skipped). Counted like `DayService.hiddenUnlocked`: a
    /// replaced quest or routine is not the day's ask, the hidden quest (drawn only after the clear),
    /// the weekly epic and routines that never gate the day (`countsForClear == false`) do not
    /// count, and routines are those due on `dayKey`.
    public static func allCleared(quests: [DailyQuest], occurrences: [RoutineOccurrence], dayKey: String) -> Bool {
        let asked = quests.filter { $0.dayKey == dayKey && !$0.replaced && !$0.isHiddenSlot && $0.slot != .epic }
        let due = occurrences.filter { $0.dueDayKey == dayKey && !$0.isReplaced && $0.countsForClear }
        guard !asked.isEmpty || !due.isEmpty else { return false }
        return asked.allSatisfy { $0.completedAt != nil }
            && due.allSatisfy { $0.completedDayKey != nil || $0.skipped }
    }
}
