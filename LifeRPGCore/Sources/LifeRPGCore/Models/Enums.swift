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

public enum RecurrenceKind: String, Codable, CaseIterable, Sendable {
    case weekly, everyNDays, monthly, nthWeekdayOfMonth, everyNWeeksOnWeekday
}

/// What a rating or comment is attached to. `QuestTemplate` and `RoutineTask` ids live in separate
/// tables, so the kind is what tells the two apart when exporting or looking one up.
public enum FeedbackTarget: String, Codable, CaseIterable, Sendable {
    case quest, routine
}
