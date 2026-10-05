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

    public var completedCount: Int { completed.count }

    /// The coins the day's completions paid, summed from the items.
    public var coinsEarned: Int { completed.reduce(0) { $0 + $1.coins } }

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
    public init(dayKey: String,
                quests: [DailyQuest],
                occurrences: [RoutineOccurrence],
                context: DailyContext?,
                ratings: [QuestRating],
                ledger: [LedgerEntry] = [],
                flexible: Set<UUID> = [],
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
                  light: Bool, coins: Int?) -> Item {
            Item(subject: JournalSubject(kind: kind, id: id, text: text),
                 rating: newest[id]?.rating, completedAt: at,
                 isChoice: Self.isChoice(text), isLight: light, coins: coins ?? 0)
        }

        var done: [Item] = quests
            .filter { $0.dayKey == dayKey && !$0.replaced && $0.points != nil }
            .map { item(.quest, $0.id, $0.textSnapshot, at: $0.completedAt,
                        light: false, coins: $0.points) }
        done += occurrences
            .filter { $0.completedDayKey == dayKey && !$0.isReplaced }
            .map { item(.routine, $0.id, $0.displayText, at: $0.completedAt,
                        light: $0.usedDegraded && $0.degradedTextSnapshot != nil, coins: $0.awardedPoints) }
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
            .filter { $0.dayKey == dayKey && !$0.replaced && !$0.isHiddenSlot && $0.points == nil }
            .sorted { $0.textSnapshot < $1.textSnapshot }
            .map { JournalSubject(kind: .quest, id: $0.id, text: $0.textSnapshot) }
        let openRoutines = occurrences
            .filter { $0.dueDayKey == dayKey && $0.completedDayKey == nil && !$0.skipped && !$0.isReplaced }
            .sorted { $0.textSnapshot < $1.textSnapshot }
            .map { JournalSubject(kind: .routine, id: $0.id, text: $0.displayText) }
        self.leftOpen = openQuests + openRoutines
    }
}
