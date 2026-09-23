import Foundation
import SwiftData

/// Today's instance of a random slot. Text is snapshotted; never reference the template for history.
@Model public final class DailyQuest {
    public var id: UUID = UUID()
    public var dayKey: String = ""                // "2026-09-17", local timezone
    public var weekKey: String = ""               // "2026-W38", used for epic and flexible settlement
    public var slotRaw: String = ""
    public var isHiddenSlot: Bool = false
    public var templateID: UUID?
    public var textSnapshot: String = ""
    public var launchURLSnapshot: String?
    public var variantSnapshot: String?           // the value drawn from a parameterized template
    public var trivialGroup: [String] = []        // the three texts in the T group; non-empty = isTrivialGroup
    public var trivialDone: [Bool] = []
    public var trivialTemplateIDs: [UUID] = []    // parallel to trivialGroup, for the cooldown write-back only
    public var trivialVariants: [String] = []     // parallel to trivialGroup; "" = that item has none
    public var points: Int?                       // nil = not completed
    public var completedAt: Date?
    public var sourceTypeRaw: String = "manual"
    public var rerollCount: Int = 0
    public var replaced: Bool = false             // no longer this day's ask; see `replacedReason`
    /// Why, as a `ReplacedReason` raw value. Added after `replaced` shipped meaning one thing, so
    /// nil reads as `adHoc` — every row written before this was one.
    public var replacedReasonRaw: String?
    public var extensionCount: Int = 0            // epic only, max 2

    public init() {}

    public var slot: Difficulty {
        get { Difficulty(rawValue: slotRaw) ?? .easy }
        set { slotRaw = newValue.rawValue }
    }

    public var isTrivialGroup: Bool { !trivialGroup.isEmpty }

    public var replacedReason: ReplacedReason {
        get { replacedReasonRaw.flatMap(ReplacedReason.init(rawValue:)) ?? .adHoc }
        set { replacedReasonRaw = newValue.rawValue }
    }
}
