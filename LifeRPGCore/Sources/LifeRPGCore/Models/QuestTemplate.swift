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
    /// Deleted by the user, as far as the Library is concerned: the row stays, so what the history,
    /// the ratings and the notes point at still resolves, but it is not listed. Not the same as
    /// `isActive` (turned off, still listed, can be turned back on). An archived row is always
    /// inactive too, so every place that draws, schedules or offers rows needs no second test.
    public var isArchived: Bool = false
    /// `LibraryOrigin` raw value. Every row that existed before the field is a seed row.
    /// The key the starter library gave the row it was installed from (nil for the user's own rows and
    /// for rows from before keys existed, which `StarterUpdate.claim` matches by text once). It is what
    /// tells a starter row apart from the user's edits of it, so a renamed or deleted row is never
    /// offered again.
    public var starterKey: String?
    public var originRaw: String = LibraryOrigin.seed.rawValue

    public init() {}

    public var origin: LibraryOrigin {
        get { LibraryOrigin(rawValue: originRaw) ?? .seed }
        set { originRaw = newValue.rawValue }
    }

    public var difficulty: Difficulty {
        get { Difficulty(rawValue: difficultyRaw) ?? .easy }
        set { difficultyRaw = newValue.rawValue }
    }
}
