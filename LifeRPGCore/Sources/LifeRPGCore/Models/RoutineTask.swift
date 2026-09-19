import Foundation
import SwiftData

@Model public final class RoutineTask {
    public var id: UUID = UUID()
    public var text: String = ""
    public var basePoints: Int = 15
    public var difficultyRaw: String = Difficulty.easy.rawValue
    public var intensityRaw: String = Intensity.low.rawValue
    public var kindRaw: String = RecurrenceKind.weekly.rawValue
    public var spec: String = ""                  // "MON,THU" / "3" / "1:SAT" / "2:SAT"
    public var anchorWeekKey: String?             // everyNWeeksOnWeekday only, e.g. "2026-W38"
    public var weeklyTarget: Int = 1
    public var flexibleWithinWeek: Bool = false
    public var countsForClear: Bool = true
    public var degradedText: String?
    public var launchURLString: String?
    public var autoVerifyRule: String?
    public var lastCompletedDayKey: String?
    public var isActive: Bool = true

    public init() {}

    public var difficulty: Difficulty {
        get { Difficulty(rawValue: difficultyRaw) ?? .easy }
        set { difficultyRaw = newValue.rawValue }
    }

    public var intensity: Intensity {
        get { Intensity(rawValue: intensityRaw) ?? .low }
        set { intensityRaw = newValue.rawValue }
    }

    public var kind: RecurrenceKind {
        get { RecurrenceKind(rawValue: kindRaw) ?? .weekly }
        set { kindRaw = newValue.rawValue }
    }
}
