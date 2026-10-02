import Foundation

// Plain values for the Today page, built from the rows its queries already hold. Every number and
// note here is another rule's output (`Scoring`, `Completion`, `Epic`, `Economy`, `Schedule`); this
// file only chooses the words and the shape, so a view renders a state and decides nothing.

/// Number and date wording shared by the states below.
public enum PresentationText {
    /// `5–15`, or `12` when the span is a single value.
    public static func range(_ range: ClosedRange<Int>) -> String {
        range.lowerBound == range.upperBound ? "\(range.lowerBound)" : "\(range.lowerBound)–\(range.upperBound)"
    }

    /// `5 to 15 coins`, for VoiceOver.
    public static func spokenRange(_ range: ClosedRange<Int>) -> String {
        range.lowerBound == range.upperBound ? "\(range.lowerBound) coins"
                                             : "\(range.lowerBound) to \(range.upperBound) coins"
    }

    private static let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// `Sun Oct 4` for `"2026-10-04"`; a malformed key comes back unchanged.
    public static func shortDate(_ dayKey: String, in timeZone: TimeZone = .current) -> String {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]),
              let weekday = DayKey.weekday(of: dayKey, in: timeZone) else { return dayKey }
        return "\(weekdays[weekday.rawValue - 1]) \(months[parts[1] - 1]) \(parts[2])"
    }

    static func coins(_ n: Int) -> String { "\(n) coins" }
}

/// One small label on a card. `payout` is the number the card is about, `clay` the overdue one.
public struct PillState: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case payout, plain, clay }
    public let text: String
    public let kind: Kind

    public init(_ text: String, _ kind: Kind) {
        self.text = text
        self.kind = kind
    }
}

/// The tint of a tile: the difficulty, or what makes it special.
public enum QuestTint: Equatable, Sendable {
    case trivial, easy, medium, hard, hidden, epic

    init(_ difficulty: Difficulty) {
        switch difficulty {
        case .trivial: self = .trivial
        case .easy: self = .easy
        case .medium: self = .medium
        case .hard: self = .hard
        case .epic: self = .epic
        }
    }
}

// MARK: - quest tiles

public struct QuestCardState: Equatable, Identifiable, Sendable {
    public enum Layout: Equatable, Sendable { case tile, hidden, trivialGroup }

    public struct Item: Equatable, Sendable {
        public let text: String
        public let variant: String?
        public let isDone: Bool

        public init(text: String, variant: String?, isDone: Bool) {
            self.text = text
            self.variant = variant
            self.isDone = isDone
        }
    }

    public let id: UUID
    public let layout: Layout
    public let title: String
    /// The drawn value of a parameterized template, or "n of 3 done" on the trivial group.
    public let subtitle: String?
    public let doodle: DoodleKey
    public let tint: QuestTint
    public let rangeText: String
    public let awardedPoints: Int?
    public let launchURL: URL?
    public let items: [Item]
    public let accessibilityLabel: String
    public let accessibilityValue: String

    public var isDone: Bool { awardedPoints != nil }
    /// What the pill says: the span it can pay, then what it did pay.
    public var pillText: String { awardedPoints.map { "+\($0)" } ?? rangeText }

    public init(_ quest: DailyQuest, tier: Tier) {
        let range = Scoring.payoutRange(quest, tier: tier)
        id = quest.id
        rangeText = PresentationText.range(range)
        awardedPoints = quest.points
        items = quest.trivialGroup.enumerated().map { index, text in
            let variant = quest.trivialVariants.indices.contains(index) ? quest.trivialVariants[index] : ""
            return Item(text: text,
                        variant: variant.isEmpty ? nil : variant,
                        isDone: quest.trivialDone.indices.contains(index) && quest.trivialDone[index])
        }

        if quest.isTrivialGroup {
            let ticked = items.filter(\.isDone).count
            layout = .trivialGroup
            tint = .trivial
            title = "Micro-actions"
            subtitle = "\(ticked) of \(items.count) done"
            doodle = .sparkle
            launchURL = nil
            accessibilityLabel = "Micro-actions: \(items.map(\.text).joined(separator: ", ")), "
                + PresentationText.spokenRange(range)
            accessibilityValue = quest.points.map { "done, \(PresentationText.coins($0)) earned" }
                ?? "\(ticked) of \(items.count) done"
            return
        }

        layout = quest.isHiddenSlot ? .hidden : .tile
        tint = quest.isHiddenSlot ? .hidden : QuestTint(quest.slot)
        title = quest.textSnapshot
        subtitle = quest.variantSnapshot.flatMap { $0.isEmpty ? nil : $0 }
        doodle = DoodleKey.forText(quest.textSnapshot)
        launchURL = quest.launchURLSnapshot.flatMap(URL.init(string:))
        let name = quest.isHiddenSlot ? "hidden quest" : quest.slot.rawValue
        accessibilityLabel = [title, subtitle, name, PresentationText.spokenRange(range)]
            .compactMap { $0 }.joined(separator: ", ")
        accessibilityValue = quest.points.map { "done, \(PresentationText.coins($0)) earned" } ?? "not done"
    }
}

/// A slot that is no longer today's ask, kept on the page as a record.
public struct ReplacedRowState: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let code: String
    public let title: String
    public let note: String

    public init(_ quest: DailyQuest) {
        id = quest.id
        code = quest.isTrivialGroup ? "T×3" : quest.slot.code
        title = quest.isTrivialGroup ? quest.trivialGroup.joined(separator: " · ") : quest.textSnapshot
        switch quest.replacedReason {
        case .replan: note = "Dropped — the day was re-planned"
        case .cancelled: note = "Cancelled"
        case .rerolled: note = "Rerolled away"
        case .adHoc: note = "Replaced"
        case .swapped: note = "Swapped"
        }
    }
}

// MARK: - routine rows

public struct RoutineRowState: Equatable, Identifiable, Sendable {
    /// Where the page lists the row: it only changes the notes and the overdue pill.
    public enum Placement: Equatable, Sendable { case today, overdue, thisWeek }

    /// A routine with a lighter version on offer today: which one is chosen and, while the row is
    /// still open, what the switch is called. Both versions pay the same, so no confirmation.
    public struct Version: Equatable, Sendable {
        public let note: String
        public let switchLabel: String?

        public init(note: String, switchLabel: String?) {
            self.note = note
            self.switchLabel = switchLabel
        }
    }

    public let id: UUID
    public let title: String
    public let doodle: DoodleKey
    public let pills: [PillState]
    public let notes: [String]
    public let version: Version?
    /// The notes as one caption line; the view lets it wrap only when it must.
    public var noteLine: String? { notes.isEmpty ? nil : notes.joined(separator: " · ") }
    public let overdueDay: Int?
    public let isDone: Bool
    public let isSkipped: Bool
    public let awardedPoints: Int?
    public let accessibilityLabel: String
    public let accessibilityValue: String

    /// - Parameters:
    ///   - routine: the template, for the frequency and auto-verify pills; nil for an ad-hoc one.
    ///   - quests, occurrences: the rows the page's queries hold, to name what an ad-hoc row replaced.
    public init(_ o: RoutineOccurrence, placement: Placement, routine: RoutineTask?, flexible: Bool,
                today: String, tier: Tier, level: Int,
                quests: [DailyQuest], occurrences: [RoutineOccurrence]) {
        let open = o.completedDayKey == nil && !o.skipped
        // The number `Completion.completeRoutine` will pay today (the late make-up for an overdue one).
        let pays = Completion.routinePayout(o, flexible: flexible, on: today, tier: tier, level: level)
        id = o.id
        title = o.displayText
        doodle = DoodleKey.forText(o.displayText)
        awardedPoints = o.awardedPoints
        isDone = o.awardedPoints != nil
        isSkipped = o.skipped
        overdueDay = open && placement == .overdue ? (Schedule.roundDay(due: o.dueDayKey, on: today) ?? 2) : nil

        var pills: [PillState] = []
        if let paid = o.awardedPoints {
            pills.append(PillState("+\(paid)", .payout))
        } else if o.skipped {
            pills.append(PillState("Skipped", .plain))
        } else if let pays {
            pills.append(PillState("+\(pays)", .payout))
        }
        if let frequency = Self.frequencyText(routine) { pills.append(PillState(frequency, .plain)) }
        if let rule = routine?.autoVerifyRule, !rule.isEmpty { pills.append(PillState("auto-verified", .plain)) }
        if o.usedDegraded { pills.append(PillState("light version", .plain)) }
        if let day = overdueDay { pills.append(PillState("overdue · day \(day)", .clay)) }
        self.pills = pills

        if o.degradedTextSnapshot != nil {
            version = Version(
                note: o.usedDegraded ? "Light version · \(o.textSnapshot)" : "Original · light version available",
                switchLabel: open ? (o.usedDegraded ? "Do original" : "Use light") : nil)
        } else {
            version = nil
        }

        var notes: [String] = []
        if open, placement == .thisWeek { notes.append("Not done · due \(o.dueDayKey)") }
        let added = o.dueDayKey == today ? "Added today" : "Added \(o.dueDayKey)"
        if let questID = o.replacesQuestID {
            let replaced = quests.first { $0.id == questID }
            notes.append("\(added) · replaces \(replaced.map(Self.slotText) ?? "a random slot")")
        } else if let replaced = occurrences.first(where: { $0.replacedByID == o.id }) {
            notes.append("Replaces \(replaced.displayText)")
        } else if o.routineID == nil {
            notes.append("\(added) · extra, no penalty")
        }
        // An extra (`AdHoc.add`) never gates by construction and says "extra" already.
        let isExtra = o.routineID == nil && o.replacesQuestID == nil && !occurrences.contains { $0.replacedByID == o.id }
        if !o.countsForClear, !isExtra { notes.append("Doesn't gate the hidden quest") }
        self.notes = notes

        accessibilityLabel = [title,
                              overdueDay.map { "overdue day \($0)" },
                              open ? pays.map { "pays \(PresentationText.coins($0))" } : nil]
            .compactMap { $0 }.joined(separator: ", ")
        accessibilityValue = o.awardedPoints.map { "done, \(PresentationText.coins($0)) earned" }
            ?? (o.skipped ? "skipped" : "not done")
    }

    private static func slotText(_ quest: DailyQuest) -> String {
        quest.isTrivialGroup ? quest.trivialGroup.joined(separator: " · ") : quest.textSnapshot
    }

    /// `Wed · Sat` for a fixed weekly routine, `2× a week` for a flexible one; other cadences
    /// (every N days, monthly) say nothing.
    private static func frequencyText(_ routine: RoutineTask?) -> String? {
        guard let routine else { return nil }
        if routine.flexibleWithinWeek { return "\(routine.weeklyTarget)× a week" }
        guard case .weekly(let days)? = try? FrequencySpec.parse(kind: routine.kind, spec: routine.spec) else {
            return nil
        }
        return days.map { $0.code.prefix(1) + $0.code.dropFirst().lowercased() }.joined(separator: " · ")
    }
}

// MARK: - epic

public struct EpicCardState: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let segmentsFilled: Int
    public let segmentsTotal: Int
    public let lastDayKey: String?
    public let detailText: String
    /// `detailText` without the day count, which the segments already show: for a narrow second line.
    public let shortDetailText: String
    public let extensionText: String?
    public let launchURL: URL?
    /// The span it can pay, then `+N` once it has.
    public let rewardRangeText: String
    public let awardedPoints: Int?
    public let accessibilityLabel: String
    public let accessibilityValue: String

    public var isDone: Bool { awardedPoints != nil }

    public init(_ epic: DailyQuest, today: String, tier: Tier, level: Int) {
        let range = Scoring.payoutRange(epic, tier: tier)
        let last = Epic.lastDayKey(of: epic)
        id = epic.id
        // The drawn value stays beside the wording, the way the confirmation reads it.
        title = [epic.textSnapshot, epic.variantSnapshot].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: " — ")
        launchURL = epic.launchURLSnapshot.flatMap(URL.init(string:))
        segmentsTotal = 7
        // Monday-first day of the week: the segments are the days of the week elapsed, so an
        // extended epic starts its bar over each week it runs into.
        let weekday = DayKey.weekday(of: today).map { ($0.rawValue + 5) % 7 + 1 } ?? 1
        segmentsFilled = epic.points != nil ? 7 : weekday
        lastDayKey = last
        awardedPoints = epic.points
        extensionText = epic.extensionCount > 0
            ? "extended \(epic.extensionCount)/\(Epic.maxExtensions(level: level))" : nil
        rewardRangeText = epic.points.map { "+\($0)" } ?? PresentationText.range(range)

        let details = ["day \(weekday) of 7", last.map { "until \(PresentationText.shortDate($0))" }, extensionText]
            .compactMap { $0 }
        detailText = details.joined(separator: " · ")
        shortDetailText = details.dropFirst().joined(separator: " · ")
        accessibilityLabel = "Weekly epic: \(title), \(PresentationText.spokenRange(range))"
        accessibilityValue = epic.points.map { "done, \(PresentationText.coins($0)) earned" }
            ?? "not done, \(details.joined(separator: ", "))"
    }
}

// MARK: - level card

public struct LevelCardState: Equatable, Sendable {
    public struct Goal: Equatable, Sendable {
        public let name: String
        public let text: String
        public let fraction: Double
        public let ready: Bool

        public init(name: String, text: String, fraction: Double, ready: Bool) {
            self.name = name
            self.text = text
            self.fraction = fraction
            self.ready = ready
        }
    }

    public let level: Int
    public let balance: Int
    public let pointsToNext: Int
    public let filledDots: Int
    public let dotCount: Int
    public let streakText: String?
    public let tierText: String
    public let slotsText: String
    public let goal: Goal?
    public let accessibilityLabel: String
    public let accessibilityValue: String

    /// Negative is shown in clay rather than clamped to zero: more honest.
    public var isNegative: Bool { balance < 0 }

    public init(totalEarned: Int, balance: Int, streak: Int, tier: Tier, randomSlots: Int,
                goal progress: SavingsGoal.Progress?) {
        level = Economy.level(totalEarned: totalEarned)
        self.balance = balance
        pointsToNext = Economy.pointsToNextLevel(totalEarned: totalEarned)
        dotCount = 20
        filledDots = Economy.levelDots(totalEarned: totalEarned, count: 20)
        streakText = streak > 0 ? "\(streak) day streak" : nil
        switch tier {
        case .veryLow: tierText = "very low day"
        case .low: tierText = "low day"
        case .normal: tierText = "normal day"
        case .high: tierText = "high day"
        }
        slotsText = "\(randomSlots) random slot\(randomSlots == 1 ? "" : "s")"
        goal = progress.map { goal in
            let text: String
            if goal.ready {
                text = "ready to redeem"
            } else if let weeks = goal.weeksLeft {
                text = "\(max(0, goal.balance)) / \(goal.price) · ~\(weeks) wk"
            } else {
                text = "\(max(0, goal.balance)) / \(goal.price)"
            }
            return Goal(name: goal.name, text: text, fraction: goal.fraction, ready: goal.ready)
        }
        accessibilityLabel = "Level \(level), \(pointsToNext) coins to level \(level + 1)"
        accessibilityValue = ["\(balance) coins", streakText, tierText, slotsText,
                              self.goal.map { "\($0.name), \($0.text)" }]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

// MARK: - greeting

public struct TodayGreeting: Equatable, Sendable {
    /// `Fri · Oct 2 · 12 day streak`, the streak part left out at zero.
    public let handLine: String
    public let salutation: String

    /// `hour` is the wall clock's, not the app day's: the 05:00 day boundary does not apply to a
    /// greeting, so 02:00 still says morning.
    public init(dayKey: String, hour: Int, streak: Int) {
        let date = PresentationText.shortDate(dayKey).split(separator: " ")
        let day = date.count == 3 ? "\(date[0]) · \(date[1]) \(date[2])" : dayKey
        handLine = streak > 0 ? "\(day) · \(streak) day streak" : day
        salutation = switch hour {
        case ..<12: "Good morning,"
        case ..<18: "Good afternoon,"
        default: "Good evening,"
        }
    }
}
