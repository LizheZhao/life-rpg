import Foundation
import SwiftData

/// Writes the history table and the rating and comment logs back out as CSV.
///
/// The history table (`history`) is the one place the records and the library are put together:
/// the app keeps them apart (a record points at its library row by id), and this joins them on
/// that id so a row reads in full without the app.
///
/// These two tables are the only user-entered data that the seed CSVs in `doc/` cannot rebuild, so
/// they need a way off the device that is readable without the app. CSV rather than JSON because
/// the destination is a spreadsheet or a diff against `doc/*.csv`, not an importer.
///
/// Every row is exported, not just the newest per target: the logs are append-only on purpose, and
/// "which quests have I been rating highest lately" is only answerable while the dates are intact.
public enum CSVExport {
    public struct File: Equatable, Sendable {
        public var name: String
        public var contents: String
    }

    public static func files(_ context: ModelContext, now: Date = Date(),
                             in timeZone: TimeZone = .current) throws -> [File] {
        [File(name: "history-\(now.dayKey(in: timeZone)).csv", contents: try history(context)),
         File(name: "ratings-\(now.dayKey(in: timeZone)).csv", contents: try ratings(context)),
         File(name: "comments-\(now.dayKey(in: timeZone)).csv", contents: try comments(context))]
    }

    /// `LifeRPG-tables-2026-09-20`, the folder the files land in.
    public static func folderName(now: Date = Date(), in timeZone: TimeZone = .current) -> String {
        "LifeRPG-tables-\(now.dayKey(in: timeZone))"
    }

    /// One row per quest and per routine that was on a day, oldest first, with the library row it
    /// came from joined on its id (difficulty, whether the user saved it, whether it is on) and the
    /// latest rating given right after it. Then one row for every library row no record points at,
    /// so a quest saved but never drawn is in the table too. A custom task has no library row, so
    /// its library columns are empty.
    public static func history(_ context: ModelContext) throws -> String {
        let templates = Dictionary(uniqueKeysWithValues:
            try context.fetch(FetchDescriptor<QuestTemplate>()).map { ($0.id, $0) })
        let routines = Dictionary(uniqueKeysWithValues:
            try context.fetch(FetchDescriptor<RoutineTask>()).map { ($0.id, $0) })
        let quests = try context.fetch(FetchDescriptor<DailyQuest>())
        let occurrences = try context.fetch(FetchDescriptor<RoutineOccurrence>())
        let settled = Schedule.settledIDs(try context.fetch(FetchDescriptor<LedgerEntry>()))
        let rated = Dictionary(grouping: try context.fetch(FetchDescriptor<QuestRating>()).filter { $0.questID != nil },
                               by: { $0.questID! })
            .mapValues { $0.max { $0.timestamp < $1.timestamp }! }

        func flag(_ b: Bool) -> String { b ? "TRUE" : "FALSE" }
        struct Line {
            var day: String, text: String, cells: [String]
        }
        func cells(kind: String, status: String, points: Int?, base: Int?, penalty: Int?, completedAt: Date?,
                   ratingFor id: UUID?, difficulty: Difficulty?, origin: LibraryOrigin?, active: Bool?) -> [String] {
            [kind, status, points.map(String.init) ?? "", base.map(String.init) ?? "",
             penalty.map(String.init) ?? "", completedAt.map(iso) ?? "",
             id.flatMap { rated[$0] }.map { String($0.rating) } ?? "",
             difficulty?.code ?? "", origin?.rawValue ?? "", active.map(flag) ?? ""]
        }

        var lines: [Line] = []
        var used = Set<UUID>()

        for q in quests {
            let template = q.isTrivialGroup ? nil : q.templateID.flatMap { templates[$0] }
            if let id = template?.id { used.insert(id) }
            if q.isTrivialGroup { used.formUnion(q.trivialTemplateIDs) }
            let kind = q.isTrivialGroup ? "micro-actions" : q.isHiddenSlot ? "hidden" : q.slot == .epic ? "epic" : "quest"
            let status = q.replaced ? "replaced" : q.completedAt != nil || q.points != nil ? "done" : "open"
            lines.append(Line(
                day: q.dayKey,
                text: q.isTrivialGroup ? q.trivialGroup.joined(separator: " | ") : q.textSnapshot,
                cells: cells(kind: kind, status: status, points: q.points, base: nil, penalty: nil,
                             completedAt: q.completedAt, ratingFor: q.id, difficulty: template?.difficulty,
                             origin: template?.origin, active: template?.isActive)))
        }
        for o in occurrences {
            let routine = (o.routineID ?? o.adHocSourceRoutineID).flatMap { routines[$0] }
            if let id = routine?.id { used.insert(id) }
            let kind: String
            if AdHoc.isExtra(o, among: occurrences) { kind = "extra" }
            else if o.replacesQuestID != nil || occurrences.contains(where: { $0.replacedByID == o.id }) { kind = "swap" }
            else { kind = "routine" }
            let status: String
            switch DayRecord.status(of: o, settled: settled) {
            case .done: status = "done"
            case .doneAhead: status = "done ahead"
            case .late: status = "done late"
            case .skipped: status = "cancelled"
            case .missed: status = "missed"
            case .replaced: status = "replaced"
            case .notDone: status = "open"
            }
            lines.append(Line(
                day: o.dueDayKey, text: o.displayText,
                cells: cells(kind: kind, status: status, points: o.awardedPoints, base: o.basePoints,
                             penalty: o.penaltyApplied, completedAt: o.completedAt, ratingFor: o.id,
                             difficulty: routine?.difficulty, origin: routine?.origin, active: routine?.isActive)))
        }
        lines.sort { ($0.day, $0.text) < ($1.day, $1.text) }

        // The library rows no record points at, last.
        let unused: [Line] =
            templates.values.filter { !used.contains($0.id) }.map {
                Line(day: "", text: $0.text,
                     cells: cells(kind: "library", status: "", points: nil, base: nil, penalty: nil, completedAt: nil,
                                  ratingFor: nil, difficulty: $0.difficulty, origin: $0.origin, active: $0.isActive))
            } + routines.values.filter { !used.contains($0.id) }.map {
                Line(day: "", text: $0.text,
                     cells: cells(kind: "library", status: "", points: nil, base: $0.basePoints, penalty: nil,
                                  completedAt: nil, ratingFor: nil, difficulty: $0.difficulty, origin: $0.origin,
                                  active: $0.isActive))
            }
        lines += unused.sorted { $0.text < $1.text }

        return table(header: ["day_key", "kind", "text", "status", "points", "base_points", "penalty", "completed_at",
                              "rating", "library_difficulty", "library_origin", "library_active"],
                     rows: lines.map { [$0.day, $0.cells[0], $0.text] + Array($0.cells.dropFirst()) })
    }

    public static func ratings(_ context: ModelContext) throws -> String {
        let rows = try context.fetch(FetchDescriptor<QuestRating>())
            .sorted { ($0.dayKey, $0.timestamp) < ($1.dayKey, $1.timestamp) }
        return table(header: ["day_key", "target_kind", "text", "rating", "timestamp", "target_id"],
                     rows: rows.map {
                         [$0.dayKey, $0.targetKindRaw, $0.textSnapshot, "\($0.rating)",
                          iso($0.timestamp), $0.targetID?.uuidString ?? ""]
                     })
    }

    public static func comments(_ context: ModelContext) throws -> String {
        let rows = try context.fetch(FetchDescriptor<QuestComment>())
            .sorted { ($0.dayKey, $0.timestamp) < ($1.dayKey, $1.timestamp) }
        return table(header: ["day_key", "target_kind", "text", "comment", "timestamp", "target_id"],
                     rows: rows.map {
                         [$0.dayKey, $0.targetKindRaw, $0.textSnapshot, $0.comment,
                          iso($0.timestamp), $0.targetID?.uuidString ?? ""]
                     })
    }

    // MARK: writing

    static func table(header: [String], rows: [[String]]) -> String {
        ([header] + rows).map { $0.map(field).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    /// RFC 4180: quote whenever the value holds a comma, a quote or a newline, and double the
    /// quotes inside. `CSV.parse` reads this back unchanged.
    static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
        else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
