import Foundation
import SwiftData

@Model public final class QuestTemplate {
    public var id: UUID = UUID()
    public var text: String = ""
    public var difficultyRaw: String = Difficulty.easy.rawValue
    public var hiddenEligible: Bool = false
    public var weekendOnly: Bool = false          // excluded from the pool Mon–Fri
    public var cooldownDaysOverride: Int?
    public var variants: [String] = []            // parameterized placeholders
    public var launchURLString: String?
    public var autoVerifyRule: String?            // "mindful:15" / "calendar_workout:30"
    public var affinity: Int = 0                  // -2...2, sampling weight
    public var lastServedDayKey: String?          // drawn but not completed → 1-day cooldown
    public var lastCompletedDayKey: String?       // completed → full cooldown
    public var isActive: Bool = true

    public init() {}

    public var difficulty: Difficulty {
        get { Difficulty(rawValue: difficultyRaw) ?? .easy }
        set { difficultyRaw = newValue.rawValue }
    }
}
