import Foundation

/// What a day looked like, reduced to what the editor's "Ask me something" request reads
/// (`JournalAsk`).
///
/// Built from history rows only, like `DayRecord`, and ignoring `replaced` rows the way every
/// other reader of them does. Ratings are matched to an item through `questID`, the link
/// `QuestRating` keeps to the completion that prompted it, so a rating filed from the library
/// page (no `questID`) says nothing about the day.
public struct JournalSignals: Equatable, Sendable {
    /// One thing done that day.
    public struct Item: Equatable, Sendable {
        public let subject: JournalSubject
        /// The newest rating of this completion, -2...2.
        public let rating: Int?
        public let completedAt: Date?
        public let isChoice: Bool
        /// A routine done on its light version (`RoutineOccurrence.usedDegraded`); the subject's text
        /// is then the light version's.
        public let isLight: Bool
        /// What the completion paid: `DailyQuest.points`, `RoutineOccurrence.awardedPoints`, 0 when
        /// none was recorded.
        public let coins: Int
        /// A quest's slot; nil for a routine.
        public var difficulty: Difficulty? = nil
        /// A routine done before the day it was due (flexible do-ahead).
        public var isAhead = false
    }

    /// The week's epic as it stands on the day. It is kept out of `completed` and `leftOpen`: it
    /// runs for a week, so "done today" and "not done yet" each need its days to mean anything.
    public struct EpicStatus: Equatable, Sendable {
        public enum Progress: Equatable, Sendable {
            /// Finished on this day, with this many days still to go before its last day.
            case doneToday(daysToSpare: Int)
            /// Finished on an earlier day of its run.
            case doneEarlier
            /// Not finished; this many days left after this one.
            case open(daysLeft: Int)
        }

        public let text: String
        public let progress: Progress
        /// What it paid, when it was finished on this day; 0 otherwise.
        public let coins: Int
    }

    public let dayKey: String
    public let tier: Tier
    /// Everything completed that day, oldest first.
    public let completed: [Item]
    /// Routines to ask about without blame, most recently due first: still open in round day 2 or
    /// 3, or closed by the settlement that opened this day. Never one that is still open today.
    public let skipped: [JournalSubject]
    /// Quests asked and routines due on this day that are still not done, skipped or swapped away.
    /// Quests first. The hidden quest is a bonus, not something left undone. Routines already
    /// overdue are `skipped`, never here.
    public let leftOpen: [JournalSubject]
    /// The epic live on this day, done or not; nil when none covers it.
    public let epic: EpicStatus?

    /// Everything finished that day, an epic finished that day included.
    public var completedCount: Int {
        if case .doneToday = epic?.progress { return completed.count + 1 }
        return completed.count
    }

    /// The coins the day's completions paid, summed from the items and an epic finished that day.
    public var coinsEarned: Int { completed.reduce(0) { $0 + $1.coins } + (epic?.coins ?? 0) }

    /// The item to ask about as a good moment: the highest rating of 1 or more, the latest winning
    /// a tie. A choice item is asked about as a choice instead, so one thing is never asked twice.
    public var bestRated: Item? {
        completed
            .filter { !$0.isChoice && ($0.rating ?? 0) >= 1 }
            .max { ($0.rating!, $0.completedAt ?? .distantPast, $1.subject.text)
                 < ($1.rating!, $1.completedAt ?? .distantPast, $0.subject.text) }
    }

    /// What marks a quest as one of picking, choosing or noticing, matched against its text,
    /// case-insensitively.
    static let choiceWords = ["photo", "photograph", "picture", "pick", "choose", "notice", "look at"]

    public static func isChoice(_ text: String) -> Bool {
        let lower = text.lowercased()
        return choiceWords.contains(where: lower.contains)
    }

    /// - Parameters:
    ///   - quests: any rows; those of `dayKey` count.
    ///   - occurrences: any rows. Done or due that day, plus the overdue and the just-settled ones.
    ///   - ledger: any rows; only this day's `skip` entries are read, which is what marks an
    ///     occurrence as given up on by the settlement that opened the day.
    ///   - flexible: the ids of flexible routines, which have no overdue ladder.
    ///   - epic: the epic live on the day (`Epic.current`). It was drawn on its own day, so the
    ///     day's quests only hold it on that day; nil falls back to an epic among `quests`.
    public init(dayKey: String,
                quests: [DailyQuest],
                occurrences: [RoutineOccurrence],
                context: DailyContext?,
                ratings: [QuestRating],
                ledger: [LedgerEntry] = [],
                flexible: Set<UUID> = [],
                epic: DailyQuest? = nil,
                timeZone: TimeZone = .current) {
        self.dayKey = dayKey
        self.tier = context?.tier ?? .normal

        var newest: [UUID: QuestRating] = [:]
        for rating in ratings {
            guard let id = rating.questID else { continue }
            if let seen = newest[id], seen.timestamp >= rating.timestamp { continue }
            newest[id] = rating
        }
        func item(_ kind: FeedbackTarget, _ id: UUID, _ text: String, at: Date?,
                  light: Bool, coins: Int?, difficulty: Difficulty? = nil, ahead: Bool = false) -> Item {
            Item(subject: JournalSubject(kind: kind, id: id, text: text),
                 rating: newest[id]?.rating, completedAt: at,
                 isChoice: Self.isChoice(text), isLight: light, coins: coins ?? 0,
                 difficulty: difficulty, isAhead: ahead)
        }

        var done: [Item] = quests
            .filter { $0.dayKey == dayKey && !$0.replaced && $0.points != nil && $0.slot != .epic }
            .map { item(.quest, $0.id, $0.textSnapshot, at: $0.completedAt,
                        light: false, coins: $0.points, difficulty: $0.slot) }
        done += occurrences
            .filter { $0.completedDayKey == dayKey && !$0.isReplaced }
            .map { item(.routine, $0.id, $0.displayText, at: $0.completedAt,
                        light: $0.usedDegraded && $0.degradedTextSnapshot != nil, coins: $0.awardedPoints,
                        ahead: $0.dueDayKey > dayKey) }
        self.completed = done.sorted { ($0.completedAt ?? .distantPast, $0.subject.text)
                                     < ($1.completedAt ?? .distantPast, $1.subject.text) }

        let skipKind = Economy.Kind.skip.rawValue
        let settled = Set(ledger.filter { $0.kind == skipKind && $0.dayKey == dayKey }.compactMap(\.refID))
        let given = occurrences.filter { o in
            guard !o.isReplaced else { return false }
            if Schedule.isOpen(o) {
                return !Schedule.isFlexible(o, flexible)
                    && (Schedule.roundDay(due: o.dueDayKey, on: dayKey, in: timeZone) ?? 0) >= 2
            }
            return Schedule.isMissed(o, settled: settled)
        }
        self.skipped = given
            .sorted { $0.dueDayKey == $1.dueDayKey ? $0.textSnapshot < $1.textSnapshot : $0.dueDayKey > $1.dueDayKey }
            .map { JournalSubject(kind: .routine, id: $0.id, text: $0.displayText) }

        let openQuests = quests
            .filter { $0.dayKey == dayKey && !$0.replaced && !$0.isHiddenSlot && $0.points == nil && $0.slot != .epic }
            .sorted { $0.textSnapshot < $1.textSnapshot }
            .map { JournalSubject(kind: .quest, id: $0.id, text: $0.textSnapshot) }
        let openRoutines = occurrences
            .filter { $0.dueDayKey == dayKey && $0.completedDayKey == nil && !$0.skipped && !$0.isReplaced }
            .sorted { $0.textSnapshot < $1.textSnapshot }
            .map { JournalSubject(kind: .routine, id: $0.id, text: $0.displayText) }
        self.leftOpen = openQuests + openRoutines

        let live = epic ?? quests.first { $0.slot == .epic && !$0.replaced && $0.dayKey == dayKey }
        self.epic = live.flatMap { Self.epicStatus($0, on: dayKey, in: timeZone) }
    }

    /// Where `epic` stands on `dayKey`, or nil when it does not cover that day. A completion after
    /// `dayKey` (a past day's entry) leaves it open on `dayKey`.
    static func epicStatus(_ epic: DailyQuest, on dayKey: String, in timeZone: TimeZone) -> EpicStatus? {
        guard epic.slot == .epic, !epic.replaced, epic.dayKey <= dayKey,
              let last = Epic.lastDayKey(of: epic, in: timeZone), dayKey <= last,
              let left = DayKey.daysBetween(dayKey, last, in: timeZone) else { return nil }
        let doneDay = epic.points == nil ? nil : epic.completedAt?.dayKey(in: timeZone)
        switch doneDay {
        case dayKey?:
            return EpicStatus(text: epic.textSnapshot, progress: .doneToday(daysToSpare: left), coins: epic.points ?? 0)
        case let day? where day < dayKey:
            return EpicStatus(text: epic.textSnapshot, progress: .doneEarlier, coins: 0)
        default:
            return EpicStatus(text: epic.textSnapshot, progress: .open(daysLeft: left), coins: 0)
        }
    }
}
