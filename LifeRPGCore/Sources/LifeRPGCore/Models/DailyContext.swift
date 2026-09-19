import Foundation
import SwiftData

@Model public final class DailyContext {
    public var dayKey: String = ""
    public var hrv: Double?
    public var sleepHours: Double?
    public var restingHR: Double?
    public var energy: Double = 1.0
    public var readiness: Int = 75
    public var tierRaw: String = Tier.normal.rawValue
    public var onCycle: Bool = false
    public var routineLoad: Int = 0
    public var randomSlots: Int = 3

    public init() {}

    public var tier: Tier {
        get { Tier(rawValue: tierRaw) ?? .normal }
        set { tierRaw = newValue.rawValue }
    }
}
