import Foundation

/// A parsed `auto_verify` rule. As with `frequency_spec`, a typo here would otherwise just mean
/// auto-verification quietly never fires, so the string is validated at import.
public enum AutoVerifyRule: Equatable, Sendable {
    /// `"mindful:15"` — HealthKit mindful minutes that day, several sessions accumulate.
    case mindful(minutes: Int)
    /// `"calendar_workout:30"` — a calendar event of at least that many minutes that day.
    case calendarWorkout(minutes: Int)
    /// `"calendar_workout_weekly:4"` — that many qualifying events within the ISO week.
    case calendarWorkoutWeekly(sessions: Int)

    public static func parse(_ raw: String) throws -> AutoVerifyRule {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            throw AutoVerifyError(rule: raw, reason: "expected 'name:number'")
        }
        let name = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
        guard let n = Int(parts[1].trimmingCharacters(in: .whitespaces)), n >= 1 else {
            throw AutoVerifyError(rule: raw, reason: "'\(parts[1])' is not a positive number")
        }
        switch name {
        case "mindful": return .mindful(minutes: n)
        case "calendar_workout": return .calendarWorkout(minutes: n)
        case "calendar_workout_weekly": return .calendarWorkoutWeekly(sessions: n)
        default:
            throw AutoVerifyError(rule: raw, reason: "unknown rule '\(name)'")
        }
    }

    public var ruleString: String {
        switch self {
        case .mindful(let m): "mindful:\(m)"
        case .calendarWorkout(let m): "calendar_workout:\(m)"
        case .calendarWorkoutWeekly(let n): "calendar_workout_weekly:\(n)"
        }
    }

    /// Weekly rules settle on the ISO week, not on the day.
    public var isWeekly: Bool {
        if case .calendarWorkoutWeekly = self { return true }
        return false
    }
}

public struct AutoVerifyError: Error, Equatable, CustomStringConvertible {
    public var rule: String
    public var reason: String

    public var description: String { "auto_verify '\(rule)': \(reason)" }
}
