import Foundation

/// The calendar's day sheet: what its header says, how far each section got, and when it opens.
public enum DaySheet {
    /// A section's `done / total`, in the title row.
    public struct Progress: Equatable, Sendable {
        public let done: Int
        public let total: Int

        public init(done: Int, total: Int) {
            self.done = done
            self.total = total
        }

        public var text: String { "\(done) / \(total) done" }
    }

    /// Done over what the day asked for. A routine swapped for an ad-hoc one is not the day's ask, and
    /// done is the check mark (`RecordMark`): on time, ahead or made up.
    public static func routineProgress(_ lines: [DayRecord.RoutineLine]) -> Progress {
        let asked = lines.filter { $0.status != .replaced }
        return Progress(done: asked.filter { RecordMark.mark(for: $0.status) == .done }.count, total: asked.count)
    }

    /// Completed over the quests that were drawn and not swapped, rerolled or cancelled away, the
    /// hidden one and the epic included when the day had them.
    public static func questProgress(_ lines: [DayRecord.QuestLine]) -> Progress {
        let asked = lines.filter { !$0.quest.replaced }
        return Progress(done: asked.filter { $0.quest.completedAt != nil }.count, total: asked.count)
    }

    public struct Header: Equatable, Sendable {
        public let weekday: String
        public let date: String
        public let coins: String
        /// "normal day"; nil for a day the app never generated a context for.
        public let dayType: String?
    }

    public static func header(dayKey: String, net: Int, tier: Tier?, language: JournalLanguage = .system,
                              timeZone: TimeZone = .current) -> Header {
        Header(weekday: JournalPageText.format(dayKey: dayKey, template: "EEEE", language: language, timeZone: timeZone),
               date: JournalPageText.format(dayKey: dayKey, template: "MMMMd", language: language, timeZone: timeZone),
               coins: coinsText(net),
               dayType: tier?.dayText)
    }

    /// "+120 coins", "0 coins", "-35 coins".
    public static func coinsText(_ net: Int) -> String {
        "\(net > 0 ? "+" : "")\(net) \(abs(net) == 1 ? "coin" : "coins")"
    }

    /// An empty day opens nothing: it needs a quest or routine, any ledger entry or rating, or an entry.
    public static func opens(_ record: DayRecord, hasEntry: Bool) -> Bool {
        hasEntry || !record.quests.isEmpty || !record.routines.isEmpty || !record.completedForOtherDays.isEmpty
            || !record.otherLedger.isEmpty || !record.otherRatings.isEmpty
    }

    /// Nothing is written about a day that has not happened.
    public static func canWrite(dayKey: String, today: String) -> Bool { dayKey <= today }

    public enum Section: Sendable { case routines, quests }

    /// Which sections are open: routines to start, quests closed. Held by the page for the session.
    public struct Sections: Equatable, Sendable {
        public var routinesOpen = true
        public var questsOpen = false

        public init() {}

        public mutating func toggle(_ section: Section) {
            switch section {
            case .routines: routinesOpen.toggle()
            case .quests: questsOpen.toggle()
            }
        }
    }

    public static let nothingWrittenTitle = "Nothing written"
    public static let writeLinkTitle = "Write about this day"
}
