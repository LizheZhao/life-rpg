import Foundation
import SwiftData

/// Reading and writing the rating / comment log.
///
/// Both tables are append-only, so every question about them is "which rows, over what window".
/// Nothing here overwrites or deletes a row — a changed opinion is a new row on a later day, and
/// the old one stays as the record of what you thought then.
public enum Feedback {
    @discardableResult
    public static func rate(_ context: ModelContext,
                            target: FeedbackTarget,
                            id: UUID?,
                            questID: UUID? = nil,
                            text: String,
                            rating: Int,
                            dayKey: String,
                            now: Date = Date()) -> QuestRating {
        let row = QuestRating()
        row.target = target
        row.targetID = id
        row.questID = questID
        row.textSnapshot = text
        row.rating = max(-2, min(2, rating))      // the sampling weight only reads -2…2
        row.dayKey = dayKey
        row.timestamp = now
        context.insert(row)
        return row
    }

    @discardableResult
    public static func comment(_ context: ModelContext,
                               target: FeedbackTarget,
                               id: UUID?,
                               questID: UUID? = nil,
                               text: String,
                               comment: String,
                               dayKey: String,
                               now: Date = Date()) -> QuestComment {
        let row = QuestComment()
        row.target = target
        row.targetID = id
        row.questID = questID
        row.textSnapshot = text
        row.comment = comment
        row.dayKey = dayKey
        row.timestamp = now
        context.insert(row)
        return row
    }

    /// The newest rating per target — what "how do I feel about this one now" means.
    public static func latestRatings(_ context: ModelContext) throws -> [UUID: QuestRating] {
        var newest: [UUID: QuestRating] = [:]
        for row in try context.fetch(FetchDescriptor<QuestRating>()) {
            guard let id = row.targetID else { continue }
            if let existing = newest[id], existing.timestamp >= row.timestamp { continue }
            newest[id] = row
        }
        return newest
    }

    /// Average rating per target over a window, best first. `since` is inclusive; pass nil for all
    /// of history. Averaged rather than "newest wins" because the question this answers is what has
    /// been landing well *lately*, which one good day shouldn't decide on its own.
    public static func topRated(_ context: ModelContext,
                                target: FeedbackTarget? = nil,
                                since dayKey: String? = nil,
                                limit: Int = 10) throws -> [(text: String, average: Double, count: Int)] {
        var sums: [String: (total: Int, count: Int)] = [:]
        for row in try context.fetch(FetchDescriptor<QuestRating>()) {
            if let target, row.target != target { continue }
            if let dayKey, row.dayKey < dayKey { continue }
            let current = sums[row.textSnapshot] ?? (0, 0)
            sums[row.textSnapshot] = (current.total + row.rating, current.count + 1)
        }
        return sums
            .map { (text: $0.key, average: Double($0.value.total) / Double($0.value.count), count: $0.value.count) }
            .sorted { ($0.average, $0.count, $1.text) > ($1.average, $1.count, $0.text) }
            .prefix(max(0, limit))
            .map { $0 }
    }

    public static func comments(_ context: ModelContext, for id: UUID) throws -> [QuestComment] {
        try context.fetch(FetchDescriptor<QuestComment>())
            .filter { $0.targetID == id }
            .sorted { $0.timestamp > $1.timestamp }
    }
}
