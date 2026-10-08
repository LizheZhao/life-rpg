import Foundation

/// One quest / routine as a starter library (or a test fixture) describes it, before it becomes a row.
public struct SideQuestSeed: Equatable, Sendable {
    public var text: String
    public var difficulty: Difficulty
    public var hiddenEligible: Bool
    public var weekendOnly: Bool
    public var cooldownDays: Int?
    public var autoVerifyRule: String?
    public var launchURLString: String?
    public var variants: [String]
    public var isActive: Bool
    /// The starter library's key for the row, nil for a row that did not come from it.
    public var starterKey: String? = nil
}

public struct RoutineSeed: Equatable, Sendable {
    public var text: String
    public var kind: RecurrenceKind
    public var spec: String
    public var weeklyTarget: Int
    public var basePoints: Int
    public var difficulty: Difficulty
    public var flexibleWithinWeek: Bool
    public var countsForClear: Bool
    public var isActive: Bool
    /// The texts of the routines this one is a downgrade version of, `|`-separated in the CSV.
    /// Non-empty = never scheduled on its own; the importer turns these into `downgradeIDs` on
    /// each parent. Such a row may leave `frequency_kind` / `frequency_spec` empty.
    public var downgradeOf: [String]
    public var autoVerifyRule: String?
    public var launchURLString: String?
    public var starterKey: String? = nil
}

extension SideQuestSeed {
    /// Validated at parse time, so this never fails for a seed the parser returned.
    public var autoVerify: AutoVerifyRule? {
        autoVerifyRule.flatMap { try? AutoVerifyRule.parse($0) }
    }
}

extension RoutineSeed {
    /// Validated at parse time, so this never fails for a seed the parser returned.
    public var frequencySpec: FrequencySpec? {
        try? FrequencySpec.parse(kind: kind, spec: spec)
    }

    public var autoVerify: AutoVerifyRule? {
        autoVerifyRule.flatMap { try? AutoVerifyRule.parse($0) }
    }
}
