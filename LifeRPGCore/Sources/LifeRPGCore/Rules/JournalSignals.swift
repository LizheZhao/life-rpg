import Foundation

/// What a day looked like, reduced to what the planner and the follow-up prompt read.
///
/// Built from history rows only, like `DayRecord`, and ignoring `replaced` rows the way every
/// other reader of them does. Ratings are matched to an item through `questID`, the link
/// `QuestRating` keeps to the completion that prompted it, so a rating filed from the library
/// page (no `questID`) says nothing about the day.
public struct JournalSignals: Equatable, Sendable {
    /// One thing done that day.
    public struct Item: Equatable, Sendable {
        public let subject: JournalSubject
        /// The value drawn from a parameterized quest (`DailyQuest.variantSnapshot`).
        public let variant: String?
        /// The newest rating of this completion, -2...2.
        public let rating: Int?
        public let completedAt: Date?
        public let isChoice: Bool
        public let isPhoto: Bool
    }

    public let dayKey: String
    public let tier: Tier
    /// Everything completed that day, oldest first.
    public let completed: [Item]
    /// Routines to ask about without blame, most recently due first: still open in round day 2 or
    /// 3, or closed by the settlement that opened this day. Never one that is still open today.
    public let skipped: [JournalSubject]
    /// The day's notes, oldest first.
    public let comments: [String]

    public var completedCount: Int { completed.count }

    /// Mean of the rated items, nil when none was rated.
    public var averageRating: Double? {
        let rated = completed.compactMap(\.rating)
        return rated.isEmpty ? nil : Double(rated.reduce(0, +)) / Double(rated.count)
    }

    /// The item to ask about as a good moment: the highest rating of 1 or more, the latest winning
    /// a tie. A choice item is asked about as a choice instead, so one thing is never asked twice.
    public var bestRated: Item? {
        completed
            .filter { !$0.isChoice && ($0.rating ?? 0) >= 1 }
            .max { ($0.rating!, $0.completedAt ?? .distantPast, $1.subject.text)
                 < ($1.rating!, $1.completedAt ?? .distantPast, $0.subject.text) }
    }

    /// The latest completed photo or choice item.
    public var choiceItem: Item? {
        completed.filter(\.isChoice)
            .max { ($0.completedAt ?? .distantPast, $1.subject.text) < ($1.completedAt ?? .distantPast, $0.subject.text) }
    }

    /// What marks a quest as a photo or a choice, matched against its text, case-insensitively.
    static let photoWords = ["photo", "photograph", "picture"]
    static let choiceWords = ["pick", "choose", "notice", "look at"]

    public static func isPhoto(_ text: String) -> Bool {
        let lower = text.lowercased()
        return photoWords.contains(where: lower.contains)
    }

    public static func isChoice(_ text: String) -> Bool {
        let lower = text.lowercased()
        return isPhoto(text) || choiceWords.contains(where: lower.contains)
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
                comments: [QuestComment],
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
        func item(_ kind: FeedbackTarget, _ id: UUID, _ text: String, variant: String?, at: Date?) -> Item {
            Item(subject: JournalSubject(kind: kind, id: id, text: text), variant: variant,
                 rating: newest[id]?.rating, completedAt: at,
                 isChoice: Self.isChoice(text), isPhoto: Self.isPhoto(text))
        }

        var done: [Item] = quests
            .filter { $0.dayKey == dayKey && !$0.replaced && $0.points != nil }
            .map { item(.quest, $0.id, $0.textSnapshot, variant: $0.variantSnapshot, at: $0.completedAt) }
        done += occurrences
            .filter { $0.completedDayKey == dayKey && !$0.isReplaced }
            .map { item(.routine, $0.id, $0.displayText, variant: nil, at: $0.completedAt) }
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

        self.comments = comments.filter { $0.dayKey == dayKey }
            .sorted { $0.timestamp < $1.timestamp }.map(\.comment)
    }
}
