import Foundation
import SwiftData

/// A one-way dump of the history tables.
///
/// Pulled forward from Stage 6 on purpose: until CloudKit is on, the only copy of real usage data
/// is this app's sandbox on one phone, and accumulating months of history with no way to get it
/// off the device is how it gets lost. Import comes in Stage 6 — this only writes.
///
/// Templates and routines are not included: they are rebuilt from the seed CSVs, which live in
/// `doc/` under version control. What cannot be rebuilt is what happened, so that is what ships —
/// and that includes the ratings and comments you write in the app, which exist nowhere else.
public enum JSONExport {
    /// Bumped only when the model changes shape, independently of the GitHub tag. Import reads
    /// this and nothing else, so it has to move in step with `SchemaV1` → `SchemaV2`.
    public static let schemaVersion = 2

    public struct Snapshot: Codable, Equatable, Sendable {
        public var schemaVersion: Int
        public var exportedAt: Date
        public var ledger: [Ledger]
        public var dailyQuests: [Quest]
        public var routineOccurrences: [Occurrence]
        public var dailyContexts: [Context]
        public var ratings: [Rating]
        public var comments: [Comment]
    }

    public struct Ledger: Codable, Equatable, Sendable {
        public var id: UUID
        public var timestamp: Date
        public var dayKey: String
        public var kind: String
        public var points: Int
        public var refID: UUID?
        public var note: String
    }

    public struct Quest: Codable, Equatable, Sendable {
        public var id: UUID
        public var dayKey: String
        public var weekKey: String
        public var slot: String
        public var isHiddenSlot: Bool
        public var templateID: UUID?
        public var text: String
        public var trivialGroup: [String]
        public var trivialDone: [Bool]
        public var trivialTemplateIDs: [UUID]
        public var trivialVariants: [String]
        public var variant: String?
        public var points: Int?
        public var completedAt: Date?
        public var sourceType: String
        public var rerollCount: Int
        public var replaced: Bool
        public var extensionCount: Int
    }

    public struct Occurrence: Codable, Equatable, Sendable {
        public var id: UUID
        public var routineID: UUID?
        public var dueDayKey: String
        public var weekKey: String
        public var completedDayKey: String?
        public var text: String
        public var usedDegraded: Bool
        public var basePoints: Int
        public var countsForClear: Bool
        public var awardedPoints: Int?
        public var penaltyApplied: Int
        public var skipped: Bool
        public var completedAt: Date?
    }

    public struct Context: Codable, Equatable, Sendable {
        public var dayKey: String
        public var hrv: Double?
        public var sleepHours: Double?
        public var restingHR: Double?
        public var energy: Double
        public var readiness: Int
        public var tier: String
        public var onCycle: Bool
        public var routineLoad: Int
        public var randomSlots: Int
    }

    public struct Rating: Codable, Equatable, Sendable {
        public var id: UUID
        public var targetID: UUID?
        public var targetKind: String
        public var text: String
        public var rating: Int
        public var dayKey: String
        public var timestamp: Date
    }

    public struct Comment: Codable, Equatable, Sendable {
        public var id: UUID
        public var targetID: UUID?
        public var targetKind: String
        public var text: String
        public var comment: String
        public var dayKey: String
        public var timestamp: Date
    }

    public static func snapshot(_ context: ModelContext, now: Date = Date()) throws -> Snapshot {
        Snapshot(
            schemaVersion: schemaVersion,
            exportedAt: now,
            ledger: try context.fetch(FetchDescriptor<LedgerEntry>()).sorted { $0.timestamp < $1.timestamp }.map {
                Ledger(id: $0.id, timestamp: $0.timestamp, dayKey: $0.dayKey, kind: $0.kind,
                       points: $0.points, refID: $0.refID, note: $0.note)
            },
            dailyQuests: try context.fetch(FetchDescriptor<DailyQuest>()).sorted { $0.dayKey < $1.dayKey }.map {
                Quest(id: $0.id, dayKey: $0.dayKey, weekKey: $0.weekKey, slot: $0.slotRaw,
                      isHiddenSlot: $0.isHiddenSlot, templateID: $0.templateID, text: $0.textSnapshot,
                      trivialGroup: $0.trivialGroup, trivialDone: $0.trivialDone,
                      trivialTemplateIDs: $0.trivialTemplateIDs,
                      trivialVariants: $0.trivialVariants, variant: $0.variantSnapshot,
                      points: $0.points,
                      completedAt: $0.completedAt, sourceType: $0.sourceTypeRaw,
                      rerollCount: $0.rerollCount, replaced: $0.replaced, extensionCount: $0.extensionCount)
            },
            routineOccurrences: try context.fetch(FetchDescriptor<RoutineOccurrence>()).sorted { $0.dueDayKey < $1.dueDayKey }.map {
                Occurrence(id: $0.id, routineID: $0.routineID, dueDayKey: $0.dueDayKey, weekKey: $0.weekKey,
                           completedDayKey: $0.completedDayKey, text: $0.textSnapshot,
                           usedDegraded: $0.usedDegraded, basePoints: $0.basePoints,
                           countsForClear: $0.countsForClear,
                           awardedPoints: $0.awardedPoints, penaltyApplied: $0.penaltyApplied,
                           skipped: $0.skipped, completedAt: $0.completedAt)
            },
            dailyContexts: try context.fetch(FetchDescriptor<DailyContext>()).sorted { $0.dayKey < $1.dayKey }.map {
                Context(dayKey: $0.dayKey, hrv: $0.hrv, sleepHours: $0.sleepHours, restingHR: $0.restingHR,
                        energy: $0.energy, readiness: $0.readiness, tier: $0.tierRaw, onCycle: $0.onCycle,
                        routineLoad: $0.routineLoad, randomSlots: $0.randomSlots)
            },
            ratings: try context.fetch(FetchDescriptor<QuestRating>()).sorted { $0.timestamp < $1.timestamp }.map {
                Rating(id: $0.id, targetID: $0.targetID, targetKind: $0.targetKindRaw,
                       text: $0.textSnapshot, rating: $0.rating, dayKey: $0.dayKey,
                       timestamp: $0.timestamp)
            },
            comments: try context.fetch(FetchDescriptor<QuestComment>()).sorted { $0.timestamp < $1.timestamp }.map {
                Comment(id: $0.id, targetID: $0.targetID, targetKind: $0.targetKindRaw,
                        text: $0.textSnapshot, comment: $0.comment, dayKey: $0.dayKey,
                        timestamp: $0.timestamp)
            })
    }

    public static func data(_ context: ModelContext, now: Date = Date()) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot(context, now: now))
    }

    /// `LifeRPG-2026-09-18.json`.
    public static func filename(now: Date = Date(), in timeZone: TimeZone = .current) -> String {
        "LifeRPG-\(now.dayKey(in: timeZone)).json"
    }
}
