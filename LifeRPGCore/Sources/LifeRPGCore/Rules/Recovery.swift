import Foundation

/// A stretch of days set aside to recover — after surgery, an illness (`PLAN.md` §5, "Recovery").
///
/// Turned on by hand in Settings, from the day it was turned on through a last day the user picks.
/// Inside it the day's random slots are the bottom of the ladder (`veryLow`: T, E, E), a routine
/// heavier than easy is swapped for a light version that is easy or lighter or not scheduled at
/// all, no epic is drawn, and an ended day is judged without any penalty. Rounds still end: an
/// occurrence left open is still closed on its day 4, it just costs nothing.
public struct RecoveryPeriod: Equatable, Sendable {
    public var firstDayKey: String
    public var lastDayKey: String

    public init(firstDayKey: String, lastDayKey: String) {
        self.firstDayKey = firstDayKey
        self.lastDayKey = lastDayKey
    }

    public func contains(_ dayKey: String) -> Bool {
        firstDayKey <= dayKey && dayKey <= lastDayKey
    }
}

public enum Recovery {
    /// Every recovery day is planned as the lowest tier, whatever the body data says.
    public static let tier: Tier = .veryLow

    /// What a routine due on a recovery day becomes.
    public enum Plan: Equatable {
        case asIs
        case light(RoutineTask)
        /// Not asked of you today: no occurrence, so nothing to be overdue.
        case rest
    }

    public static func fits(_ routine: RoutineTask) -> Bool {
        routine.difficulty == .trivial || routine.difficulty == .easy
    }

    /// The light versions a heavy routine may be swapped for on a recovery day.
    public static func lightVersions(of routine: RoutineTask, in routines: [RoutineTask]) -> [RoutineTask] {
        Degrade.versions(of: routine, in: routines).filter(fits)
    }

    public static func plan(for routine: RoutineTask, in routines: [RoutineTask],
                            rng: inout some RandomNumberGenerator) -> Plan {
        if fits(routine) { return .asIs }
        return lightVersions(of: routine, in: routines).randomElement(using: &rng).map(Plan.light) ?? .rest
    }

    /// `inputs` as they stand with `period` set: inside it the tier is `tier`, whatever the body
    /// said. The one place the app turns its setting into a day's inputs.
    public static func applied(_ period: RecoveryPeriod?, to inputs: DayInputs, on dayKey: String) -> DayInputs {
        var result = inputs
        result.recovery = period
        if result.isRecovery(dayKey) { result.tier = tier }
        return result
    }
}
