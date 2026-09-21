import Foundation
import SwiftData

/// Writes the rating and comment logs back out as CSV.
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
        [File(name: "ratings-\(now.dayKey(in: timeZone)).csv", contents: try ratings(context)),
         File(name: "comments-\(now.dayKey(in: timeZone)).csv", contents: try comments(context))]
    }

    /// `LifeRPG-feedback-2026-09-20`, the folder the two files land in.
    public static func folderName(now: Date = Date(), in timeZone: TimeZone = .current) -> String {
        "LifeRPG-feedback-\(now.dayKey(in: timeZone))"
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
