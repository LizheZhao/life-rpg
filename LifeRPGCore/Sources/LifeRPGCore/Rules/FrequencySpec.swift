import Foundation

/// Gregorian weekday numbering, so the raw value matches `Calendar.component(.weekday,…)`.
public enum Weekday: Int, CaseIterable, Codable, Sendable, Comparable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    /// The CSV codes, strictly three letters: `TUES` or `SATURDAY` is a typo, not a synonym.
    public init?(code: String) {
        switch code.trimmingCharacters(in: .whitespaces).uppercased() {
        case "SUN": self = .sunday
        case "MON": self = .monday
        case "TUE": self = .tuesday
        case "WED": self = .wednesday
        case "THU": self = .thursday
        case "FRI": self = .friday
        case "SAT": self = .saturday
        default: return nil
        }
    }

    public var code: String {
        switch self {
        case .sunday: "SUN"
        case .monday: "MON"
        case .tuesday: "TUE"
        case .wednesday: "WED"
        case .thursday: "THU"
        case .friday: "FRI"
        case .saturday: "SAT"
        }
    }

    public var isWeekend: Bool { self == .saturday || self == .sunday }

    public static func < (a: Weekday, b: Weekday) -> Bool { a.rawValue < b.rawValue }
}

/// A `RoutineTask`'s `frequency_spec`, parsed. Storage keeps the raw string (`spec`); this is the
/// validated reading of it, so a typo fails loudly at import instead of the routine silently never
/// coming due.
public enum FrequencySpec: Equatable, Sendable {
    /// `"MON,THU"` — fixed weekdays, sorted and deduped.
    case weekly([Weekday])
    /// `"3"` — counted from the last completion.
    case everyNDays(Int)
    /// `"15"` — a day of the month; a month shorter than the day falls back to its last day.
    case monthly(day: Int)
    /// `"1:SAT"` / `"-1:SAT"` — first / last Saturday of the month.
    case nthWeekdayOfMonth(n: Int, weekday: Weekday)
    /// `"2:SAT"` — every n-th week on that weekday, counted from `anchorWeekKey`.
    case everyNWeeksOnWeekday(n: Int, weekday: Weekday)

    public static func parse(kind: RecurrenceKind, spec: String) throws -> FrequencySpec {
        let raw = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw FrequencyError(kind: kind, spec: spec, reason: "empty") }

        switch kind {
        case .weekly:
            var days: [Weekday] = []
            for piece in raw.split(separator: ",", omittingEmptySubsequences: false) {
                guard let day = Weekday(code: String(piece)) else {
                    throw FrequencyError(kind: kind, spec: spec,
                                         reason: "'\(piece.trimmingCharacters(in: .whitespaces))' is not a weekday code (SUN…SAT)")
                }
                guard !days.contains(day) else {
                    throw FrequencyError(kind: kind, spec: spec, reason: "\(day.code) listed twice")
                }
                days.append(day)
            }
            return .weekly(days.sorted())

        case .everyNDays:
            let n = try int(raw, kind: kind, spec: spec)
            guard n >= 1 else { throw FrequencyError(kind: kind, spec: spec, reason: "interval must be at least 1 day") }
            return .everyNDays(n)

        case .monthly:
            let day = try int(raw, kind: kind, spec: spec)
            guard (1...31).contains(day) else {
                throw FrequencyError(kind: kind, spec: spec, reason: "day of month must be 1…31")
            }
            return .monthly(day: day)

        case .nthWeekdayOfMonth:
            let (n, weekday) = try pair(raw, kind: kind, spec: spec)
            guard (1...5).contains(n) || n == -1 else {
                throw FrequencyError(kind: kind, spec: spec, reason: "n must be 1…5 or -1 (last)")
            }
            return .nthWeekdayOfMonth(n: n, weekday: weekday)

        case .everyNWeeksOnWeekday:
            let (n, weekday) = try pair(raw, kind: kind, spec: spec)
            guard n >= 1 else { throw FrequencyError(kind: kind, spec: spec, reason: "interval must be at least 1 week") }
            return .everyNWeeksOnWeekday(n: n, weekday: weekday)
        }
    }

    /// Round trip back to the CSV spelling.
    public var specString: String {
        switch self {
        case .weekly(let days): days.map(\.code).joined(separator: ",")
        case .everyNDays(let n): "\(n)"
        case .monthly(let day): "\(day)"
        case .nthWeekdayOfMonth(let n, let w): "\(n):\(w.code)"
        case .everyNWeeksOnWeekday(let n, let w): "\(n):\(w.code)"
        }
    }

    public var kind: RecurrenceKind {
        switch self {
        case .weekly: .weekly
        case .everyNDays: .everyNDays
        case .monthly: .monthly
        case .nthWeekdayOfMonth: .nthWeekdayOfMonth
        case .everyNWeeksOnWeekday: .everyNWeeksOnWeekday
        }
    }

    /// How many times this comes due in a normal week — the sanity check for `weekly_target`.
    public var nominalWeeklyCount: Int? {
        switch self {
        case .weekly(let days): days.count
        case .everyNWeeksOnWeekday(let n, _): n == 1 ? 1 : nil
        default: nil
        }
    }

    private static func int(_ raw: String, kind: RecurrenceKind, spec: String) throws -> Int {
        guard let n = Int(raw) else {
            throw FrequencyError(kind: kind, spec: spec, reason: "'\(raw)' is not a number")
        }
        return n
    }

    private static func pair(_ raw: String, kind: RecurrenceKind, spec: String) throws -> (Int, Weekday) {
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            throw FrequencyError(kind: kind, spec: spec, reason: "expected 'n:WEEKDAY'")
        }
        let n = try int(parts[0].trimmingCharacters(in: .whitespaces), kind: kind, spec: spec)
        guard let weekday = Weekday(code: String(parts[1])) else {
            throw FrequencyError(kind: kind, spec: spec,
                                 reason: "'\(parts[1].trimmingCharacters(in: .whitespaces))' is not a weekday code (SUN…SAT)")
        }
        return (n, weekday)
    }
}

public struct FrequencyError: Error, Equatable, CustomStringConvertible {
    public var kind: RecurrenceKind
    public var spec: String
    public var reason: String

    public var description: String { "\(kind.rawValue) spec '\(spec)': \(reason)" }
}
