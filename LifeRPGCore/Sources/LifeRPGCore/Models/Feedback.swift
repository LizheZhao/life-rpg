import Foundation
import SwiftData

/// A rating you gave a quest or routine on one particular day.
///
/// Append-only and keyed on the day, not on the template: the same quest can be rated differently
/// in March and in September, and both readings are kept. That is what makes "what have I been
/// rating highest lately" answerable at all — a single overwritten field on the template could only
/// ever answer "what do I think right now".
///
/// The text is snapshotted like every other history row, so an export stays readable after the
/// template it points at is edited or deactivated. `questID` links a rating back to the one
/// completion that prompted it — `DailyQuest` stays the record of what happened, this stays the
/// record of how it felt, and the summary page joins them rather than either table carrying both.
@Model public final class QuestRating {
    public var id: UUID = UUID()
    public var targetID: UUID?                    // QuestTemplate.id or RoutineTask.id
    public var questID: UUID?                     // the DailyQuest this was rated right after, if any
    public var targetKindRaw: String = FeedbackTarget.quest.rawValue
    public var textSnapshot: String = ""
    public var rating: Int = 0                    // -2…2, same scale as QuestTemplate.affinity
    public var dayKey: String = ""
    public var timestamp: Date = Date()

    public init() {}

    public var target: FeedbackTarget {
        get { FeedbackTarget(rawValue: targetKindRaw) ?? .quest }
        set { targetKindRaw = newValue.rawValue }
    }
}

/// A free-text note on a quest or routine, also dated and also append-only, so notes read as a log
/// rather than as one field that keeps getting overwritten.
@Model public final class QuestComment {
    public var id: UUID = UUID()
    public var targetID: UUID?
    public var questID: UUID?
    public var targetKindRaw: String = FeedbackTarget.quest.rawValue
    public var textSnapshot: String = ""
    public var comment: String = ""
    public var dayKey: String = ""
    public var timestamp: Date = Date()

    public init() {}

    public var target: FeedbackTarget {
        get { FeedbackTarget(rawValue: targetKindRaw) ?? .quest }
        set { targetKindRaw = newValue.rawValue }
    }
}
