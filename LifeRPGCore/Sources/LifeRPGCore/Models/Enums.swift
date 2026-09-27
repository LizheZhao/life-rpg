import Foundation

public enum Difficulty: String, Codable, CaseIterable, Sendable {
    case trivial, easy, medium, hard, epic

    /// Maps the CSV codes `T/E/M/H/EPIC`.
    public init?(csvCode: String) {
        switch csvCode.trimmingCharacters(in: .whitespaces).uppercased() {
        case "T": self = .trivial
        case "E": self = .easy
        case "M": self = .medium
        case "H": self = .hard
        case "EPIC": self = .epic
        default: return nil
        }
    }

    /// Inverse of `init?(csvCode:)` — also what the UI shows as the slot badge.
    public var code: String {
        switch self {
        case .trivial: "T"
        case .easy: "E"
        case .medium: "M"
        case .hard: "H"
        case .epic: "EPIC"
        }
    }

    public var range: ClosedRange<Int> {
        switch self {
        case .trivial: 4...4
        case .easy:    5...15
        case .medium:  12...30
        case .hard:    25...50
        case .epic:    60...150
        }
    }

    public var rerollBase: Int {
        switch self {
        case .trivial: 5
        case .easy: 10
        case .medium: 20
        case .hard: 30
        case .epic: 80
        }
    }

    public var cooldownDays: Int {
        switch self {
        case .trivial, .easy: 3
        case .medium: 7
        case .hard: 14
        case .epic: 0
        }
    }
}

public enum Intensity: String, Codable, CaseIterable, Sendable {
    case low, medium, high
}

public enum Tier: String, Codable, CaseIterable, Sendable {
    case veryLow, low, normal, high

    /// A low-energy day (`PLAN.md` §5): the 1.3× effort multiplier applies, and routines with a
    /// `degraded_text` are swapped for it. One rule for both.
    public var isLow: Bool { self == .low || self == .veryLow }
}

/// How a quest or routine was completed. Auto-verified ones — calendar workouts as well as
/// HealthKit mindful minutes — are all `healthKit`, as `PLAN.md` §5 names it.
public enum SourceType: String, Codable, CaseIterable, Sendable {
    case manual, healthKit
}

/// Why a random slot stopped being this day's ask. The row is kept either way — it is the record
/// that it was once asked of you — and full-clear, streak and the calendar skip it.
public enum ReplacedReason: String, Codable, CaseIterable, Sendable {
    /// An ad-hoc routine took the slot over (`PLAN.md` §3). You chose it, so the page shows it.
    case adHoc
    /// The day was re-planned after a fresh body reading and the new composition no longer has
    /// that slot (`PLAN.md` §5).
    case replan
    /// Paid to swap for a different draw (`Reroll.perform`). The replacement is a new row carrying
    /// `rerollCount + 1`; this one stays so the day's history still shows what was swapped away.
    case rerolled
    /// The epic, swapped by hand for one you picked from the library or wrote yourself
    /// (`Epic.replace`). Free, since an epic left undone costs nothing either.
    case swapped
    /// Bought off (`Redemption.cancel`): no longer asked of you, and no longer gating the clear,
    /// but it earned nothing and doesn't count toward the streak.
    case cancelled
}

public enum RecurrenceKind: String, Codable, CaseIterable, Sendable {
    case weekly, everyNDays, monthly, nthWeekdayOfMonth, everyNWeeksOnWeekday
}

/// What a rating or comment is attached to. `QuestTemplate` and `RoutineTask` ids live in separate
/// tables, so the kind is what tells the two apart when exporting or looking one up.
public enum FeedbackTarget: String, Codable, CaseIterable, Sendable {
    case quest, routine
}
