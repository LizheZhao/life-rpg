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
}

public enum RecurrenceKind: String, Codable, CaseIterable, Sendable {
    case weekly, everyNDays, monthly, nthWeekdayOfMonth, everyNWeeksOnWeekday
}
