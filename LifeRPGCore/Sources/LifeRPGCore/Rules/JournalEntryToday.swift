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

    /// From 20:00 local until the 05:00 rollover (hours 20 to 23 and 0 to 4), and at any hour once
    /// the day is cleared.
    public static func cardVisible(now: Date, timeZone: TimeZone = .current, allCleared: Bool) -> Bool {
        let hour = LifeCalendar.gregorian(timeZone).component(.hour, from: now)
        return allCleared || hour >= cardStartHour || hour < LifeCalendar.dayStartHour
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
