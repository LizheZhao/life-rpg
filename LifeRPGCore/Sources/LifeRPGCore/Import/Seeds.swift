import Foundation

public enum SeedError: Error, Equatable, CustomStringConvertible {
    case missingColumn(String)
    /// `reason` carries the parser's explanation for the specs that have one
    /// (`frequency_spec`, `auto_verify`); it stays nil for a plain bad value.
    case invalidValue(row: Int, column: String, value: String, reason: String? = nil)

    public var description: String {
        switch self {
        case .missingColumn(let c):
            "CSV is missing the '\(c)' column"
        case .invalidValue(let row, let column, let value, let reason):
            "line \(row), \(column) = '\(value)'" + (reason.map { ": \($0)" } ?? "")
        }
    }
}

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

public enum SeedParser {
    public static func sideQuests(csv: String) throws -> [SideQuestSeed] {
        let (header, rows) = CSV.records(csv)
        try require(["text", "difficulty", "hidden_eligible", "weekend_only"], in: header)
        return try rows.enumerated().map { i, r in
            let line = i + 2   // 1-based, after header
            let f = Fields(row: r, line: line)
            return SideQuestSeed(
                text: try f.nonEmpty("text"),
                difficulty: try f.difficulty(),
                hiddenEligible: try f.bool("hidden_eligible", default: false),
                weekendOnly: try f.bool("weekend_only", default: false),
                cooldownDays: try f.optionalInt("cooldown_days"),
                autoVerifyRule: try f.autoVerifyRule(),
                launchURLString: f.optional("launch_url"),
                variants: f.optional("variants").map {
                    $0.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                } ?? [],
                isActive: try f.bool("is_active", default: true)
            )
        }
    }

    public static func routines(csv: String) throws -> [RoutineSeed] {
        let (header, rows) = CSV.records(csv)
        try require(["text", "frequency_kind", "frequency_spec", "base_points", "difficulty"], in: header)
        return try rows.enumerated().map { i, r in
            let line = i + 2
            let f = Fields(row: r, line: line)
            let downgradeOf = f.list("downgrade_of")
            // A downgrade version is never scheduled on its own, so it needs no frequency — and
            // a frequency it was given would be data nothing reads. Everything else is parsed
            // and validated the same way, because it is completed and paid like any routine.
            guard downgradeOf.isEmpty else {
                return RoutineSeed(
                    text: try f.nonEmpty("text"),
                    kind: .weekly, spec: "", weeklyTarget: 1,
                    basePoints: try f.int("base_points"),
                    difficulty: try f.difficulty(),
                    flexibleWithinWeek: try f.bool("flexible_within_week", default: false),
                    countsForClear: try f.bool("counts_for_clear", default: true),
                    isActive: try f.bool("is_active", default: true),
                    downgradeOf: downgradeOf,
                    autoVerifyRule: try f.autoVerifyRule(),
                    launchURLString: f.optional("launch_url")
                )
            }
            let kindRaw = f.value("frequency_kind")
            guard let kind = RecurrenceKind(rawValue: kindRaw) else {
                throw SeedError.invalidValue(row: line, column: "frequency_kind", value: kindRaw)
            }
            // Parsed here purely to validate: an unparseable spec would otherwise never come due
            // — no penalty, no error, no row on the today page.
            let frequency = try f.frequency(kind: kind)
            return RoutineSeed(
                text: try f.nonEmpty("text"),
                kind: kind,
                spec: try f.nonEmpty("frequency_spec"),
                weeklyTarget: try f.weeklyTarget(frequency),
                basePoints: try f.int("base_points"),
                difficulty: try f.difficulty(),
                flexibleWithinWeek: try f.bool("flexible_within_week", default: false),
                countsForClear: try f.bool("counts_for_clear", default: true),
                isActive: try f.bool("is_active", default: true),
                downgradeOf: [],
                autoVerifyRule: try f.autoVerifyRule(),
                launchURLString: f.optional("launch_url")
            )
        }
    }

    private static func require(_ columns: [String], in header: [String]) throws {
        for c in columns where !header.contains(c) { throw SeedError.missingColumn(c) }
    }
}

private struct Fields {
    let row: [String: String]
    let line: Int

    func value(_ column: String) -> String {
        (row[column] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func optional(_ column: String) -> String? {
        let v = value(column)
        return v.isEmpty ? nil : v
    }

    func nonEmpty(_ column: String) throws -> String {
        guard let v = optional(column) else { throw invalid(column) }
        return v
    }

    func int(_ column: String) throws -> Int {
        guard let v = Int(value(column)) else { throw invalid(column) }
        return v
    }

    func optionalInt(_ column: String) throws -> Int? {
        guard optional(column) != nil else { return nil }
        return try int(column)
    }

    func bool(_ column: String, default fallback: Bool) throws -> Bool {
        switch value(column).uppercased() {
        case "": return fallback
        case "TRUE": return true
        case "FALSE": return false
        default: throw invalid(column)
        }
    }

    /// A `|`-separated list; empty entries are dropped. `|` rather than a comma because several
    /// routine texts contain commas.
    func list(_ column: String) -> [String] {
        value(column).split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func difficulty() throws -> Difficulty {
        guard let d = Difficulty(csvCode: value("difficulty")) else { throw invalid("difficulty") }
        return d
    }

    func frequency(kind: RecurrenceKind) throws -> FrequencySpec {
        let raw = value("frequency_spec")
        do {
            return try FrequencySpec.parse(kind: kind, spec: raw)
        } catch let error as FrequencyError {
            throw SeedError.invalidValue(row: line, column: "frequency_spec",
                                         value: raw, reason: error.reason)
        }
    }

    func weeklyTarget(_ frequency: FrequencySpec) throws -> Int {
        let target = try optionalInt("weekly_target") ?? 1
        guard target >= 1 else {
            throw invalid("weekly_target", reason: "must be at least 1")
        }
        // A target above the number of days the spec offers can never be met, so the routine
        // would report a shortfall every single Sunday. A lower target is legitimate
        // (three slots offered, two required), so only the upper bound is checked.
        if let available = frequency.nominalWeeklyCount, target > available {
            throw invalid("weekly_target",
                          reason: "spec '\(frequency.specString)' only comes due \(available)x a week")
        }
        return target
    }

    func autoVerifyRule() throws -> String? {
        guard let raw = optional("auto_verify") else { return nil }
        do {
            _ = try AutoVerifyRule.parse(raw)
        } catch let error as AutoVerifyError {
            throw SeedError.invalidValue(row: line, column: "auto_verify",
                                         value: raw, reason: error.reason)
        }
        return raw
    }

    private func invalid(_ column: String, reason: String? = nil) -> SeedError {
        .invalidValue(row: line, column: column, value: value(column), reason: reason)
    }
}
