import Foundation

/// Parsed readings of the raw strings the models store. All computed — nothing here changes the
/// stored schema. Each returns nil rather than a fallback when the string doesn't parse, so
/// callers can tell "not set" from "set to something unreadable"; `StoreAudit` reports the latter.
extension QuestTemplate {
    public var autoVerify: AutoVerifyRule? {
        autoVerifyRule.flatMap { try? AutoVerifyRule.parse($0) }
    }

    /// The template's own cooldown, or the difficulty default.
    public var effectiveCooldownDays: Int {
        cooldownDaysOverride ?? difficulty.cooldownDays
    }
}

extension DailyQuest {
    public var sourceType: SourceType {
        get { SourceType(rawValue: sourceTypeRaw) ?? .manual }
        set { sourceTypeRaw = newValue.rawValue }
    }
}

extension RoutineOccurrence {
    public var sourceType: SourceType {
        get { SourceType(rawValue: sourceTypeRaw) ?? .manual }
        set { sourceTypeRaw = newValue.rawValue }
    }
}

extension RoutineTask {
    public var frequency: FrequencySpec? {
        try? FrequencySpec.parse(kind: kind, spec: spec)
    }

    public var autoVerify: AutoVerifyRule? {
        autoVerifyRule.flatMap { try? AutoVerifyRule.parse($0) }
    }

    public var canDegrade: Bool {
        !(degradedText ?? "").isEmpty
    }
}
