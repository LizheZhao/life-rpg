import Foundation
import SwiftData

/// Reading and writing the rating / comment log.
///
/// Both tables are append-only, so every question about them is "which rows, over what window".
/// Nothing here overwrites or deletes a row — a changed opinion is a new row on a later day, and
/// the old one stays as the record of what you thought then.
public enum Feedback {
    /// What a card can be rated and noted as: the library row it came from, and the one completion
    /// the feedback links back to. Nil when there is no such row — a custom task, a micro-action
    /// group (three templates in one card) — so the card offers nothing to file.
    public struct Subject: Equatable, Sendable {
        public let target: FeedbackTarget
        /// The `QuestTemplate` or `RoutineTask` the feedback is filed under.
        public let id: UUID
        public let text: String
        /// The `DailyQuest` or `RoutineOccurrence` itself.
        public let instanceID: UUID
    }

    public static func subject(of quest: DailyQuest) -> Subject? {
        guard !quest.isTrivialGroup, let id = quest.templateID else { return nil }
        return Subject(target: .quest, id: id, text: quest.textSnapshot, instanceID: quest.id)
    }

    /// A routine picked from the library through "+" is still that routine
    /// (`adHocSourceRoutineID`, as `Schedule.doneThisWeek` counts it).
    public static func subject(of occurrence: RoutineOccurrence) -> Subject? {
        guard let id = occurrence.routineID ?? occurrence.adHocSourceRoutineID else { return nil }
        return Subject(target: .routine, id: id, text: occurrence.displayText, instanceID: occurrence.id)
    }

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
    ///
    /// The array overloads here exist so a page can hand in the rows its `@Query` already holds
    /// rather than re-filtering beside Core.
    public static func latestRatings(_ rows: [QuestRating]) -> [UUID: QuestRating] {
        var newest: [UUID: QuestRating] = [:]
        for row in rows {
            guard let id = row.targetID else { continue }
            if let existing = newest[id], existing.timestamp >= row.timestamp { continue }
            newest[id] = row
        }
        return newest
    }

    public static func latestRatings(_ context: ModelContext) throws -> [UUID: QuestRating] {
        latestRatings(try context.fetch(FetchDescriptor<QuestRating>()))
    }

    /// Every rating of one target, newest first — the history a changed opinion leaves behind.
    public static func ratings(_ rows: [QuestRating], for id: UUID) -> [QuestRating] {
        rows.filter { $0.targetID == id }.sorted { $0.timestamp > $1.timestamp }
    }

    /// How a library row has been rated overall: the mean of every rating it has, and how many.
    public struct Standing: Equatable, Sendable {
        public var average: Double
        public var count: Int

        public init(average: Double, count: Int) {
            self.average = average
            self.count = count
        }
    }

    /// Every row that has been rated, with its mean. Averaged rather than "newest wins": one good
    /// day shouldn't decide on its own, and the ratings are an append-only log so all of them are
    /// still there. A rating with no row behind it (a custom task) stands for nothing.
    public static func standings(_ rows: [QuestRating]) -> [UUID: Standing] {
        var sums: [UUID: (total: Int, count: Int)] = [:]
        for row in rows {
            guard let id = row.targetID else { continue }
            let current = sums[id] ?? (0, 0)
            sums[id] = (current.total + row.rating, current.count + 1)
        }
        return sums.mapValues { Standing(average: Double($0.total) / Double($0.count), count: $0.count) }
    }

    /// The Library's "Rated best" order: the best average first, then the one rated more often, then
    /// A to Z. Rows with no rating come after all of those, A to Z.
    public static func ranked<Row>(_ rows: [Row], id: (Row) -> UUID, text: (Row) -> String,
                                   standings: [UUID: Standing]) -> [Row] {
        func byName(_ a: Row, _ b: Row) -> Bool {
            text(a).localizedStandardCompare(text(b)) == .orderedAscending
        }
        let rated = rows.filter { standings[id($0)] != nil }.sorted { a, b in
            let (x, y) = (standings[id(a)]!, standings[id(b)]!)
            if x.average != y.average { return x.average > y.average }
            if x.count != y.count { return x.count > y.count }
            return byName(a, b)
        }
        return rated + rows.filter { standings[id($0)] == nil }.sorted(by: byName)
    }

    public static func comments(_ rows: [QuestComment], for id: UUID) -> [QuestComment] {
        rows.filter { $0.targetID == id }.sorted { $0.timestamp > $1.timestamp }
    }

    public static func comments(_ context: ModelContext, for id: UUID) throws -> [QuestComment] {
        comments(try context.fetch(FetchDescriptor<QuestComment>()), for: id)
    }
}
