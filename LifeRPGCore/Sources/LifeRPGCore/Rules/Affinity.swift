import Foundation
import SwiftData

/// Feeding the rating log back into `QuestTemplate.affinity`, the number sampling weights on
/// (`Sampling.weight`, `PLAN.md` §12 "How `affinity` is derived from the rating log").
///
/// **Decided with the user: the mean of the last three ratings, rounded.** Not the newest alone,
/// so one off day counts for at most a third; not a time window, so a quest that comes round
/// rarely isn't judged on a single old rating or on none. Rounding is to nearest with .5 away from
/// zero — only reachable with exactly two ratings (+1, 0 → +1).
///
/// `affinity` is therefore derived, never typed in: it is recomputed from the log, which stays the
/// source of truth, so a rating can never be lost to an overwritten field.
public enum Affinity {
    public static let window = 3

    /// The affinity `ratings` imply: newest `window` of them, averaged, rounded, clamped to −2…2.
    /// No ratings → 0, the neutral weight.
    public static func derive(_ ratings: [QuestRating]) -> Int {
        let recent = ratings.sorted { $0.timestamp > $1.timestamp }.prefix(window)
        guard !recent.isEmpty else { return 0 }
        let mean = Double(recent.reduce(0) { $0 + $1.rating }) / Double(recent.count)
        return max(-2, min(2, Int(mean.rounded(.toNearestOrAwayFromZero))))
    }

    /// Recomputes every quest template's affinity from the log. Routine ratings are kept but not
    /// read — routines are scheduled, not drawn, so they have no weight to set. Does not save.
    /// Returns how many templates changed.
    @discardableResult
    public static func sync(_ context: ModelContext) throws -> Int {
        let quest = FeedbackTarget.quest.rawValue
        let byTemplate = Dictionary(grouping: try context.fetch(FetchDescriptor<QuestRating>(
            predicate: #Predicate { $0.targetKindRaw == quest })).filter { $0.targetID != nil },
                                    by: { $0.targetID! })
        var changed = 0
        for t in try context.fetch(FetchDescriptor<QuestTemplate>()) {
            let value = derive(byTemplate[t.id] ?? [])
            if t.affinity != value {
                t.affinity = value
                changed += 1
            }
        }
        return changed
    }
}
