import Foundation
import SwiftData

/// Reading a `JSONExport` back: a full restore of the history tables, confirmed before it
/// overwrites anything (`PLAN.md` §10).
///
/// Two steps on purpose. `plan` decodes, checks the version and works out the id mapping without
/// touching the store, so the confirmation can show what is about to replace what. `apply` then
/// replaces every history table wholesale — the backup is the whole truth, not something merged
/// into what is there — and runs `StoreAudit` before saving, rolling everything back if the file
/// carried anything the app can't read.
///
/// **Ids.** A reinstall reseeds the library from the CSVs with new UUIDs, so every reference the
/// history holds into it (`templateID`, `routineID`, a rating's `targetID`, …) would point at
/// nothing. The export's `library` carries each old id with its text, and text is already the
/// seed's identity (`SeedImporter.mergeSeeds`), so old ids are re-pointed at the row with the same
/// text. An id whose text the library no longer has is left as it was, dangling — never cleared,
/// because a nil `routineID` would turn a scheduled occurrence into an ad-hoc one — and listed in
/// the summary. The history rows' own ids are kept, since the ledger and the ratings refer to them.
public enum JSONImport {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        /// Not JSON, or not an export's shape.
        case unreadable
        /// Written by a newer build than this one.
        case newerExport(Int)
        /// Written before import existed: no `library`, so history can't be re-pointed.
        case exportTooOld
        /// The file decoded, but carries values nothing can read back. Nothing was written.
        case audit([StoreAudit.Issue])

        public var description: String {
            switch self {
            case .unreadable: "This file isn't a Life RPG export."
            case .newerExport(let v): "Exported by a newer build (schema \(v)). Update the app first."
            case .exportTooOld: "This export predates import. Export again with this build."
            case .audit(let issues):
                "Import cancelled, nothing changed: " + issues.map(\.description).joined(separator: ", ")
            }
        }
    }

    public struct Summary: Equatable, Sendable {
        public var exportedAt: Date
        public var firstDayKey: String?
        public var lastDayKey: String?
        public var dailyQuests: Int
        public var routineOccurrences: Int
        public var ledgerEntries: Int
        public var ratings: Int
        public var comments: Int
        public var rewards: Int
        /// What the balance will be once the backup is in.
        public var balance: Int
        /// Library texts in the backup that this store doesn't have; their history stays but
        /// points at nothing.
        public var unmatchedLibrary: [String]
    }

    public struct Plan: Sendable {
        public var snapshot: JSONExport.Snapshot
        public var summary: Summary
        var questIDs: [UUID: UUID]
        var routineIDs: [UUID: UUID]
    }

    private struct VersionProbe: Decodable { var schemaVersion: Int }

    /// Decodes and maps; writes nothing.
    public static func plan(_ data: Data, against context: ModelContext) throws -> Plan {
        guard let probe = try? JSONDecoder().decode(VersionProbe.self, from: data) else { throw Failure.unreadable }
        if probe.schemaVersion > JSONExport.schemaVersion { throw Failure.newerExport(probe.schemaVersion) }
        if probe.schemaVersion < JSONExport.oldestReadableVersion { throw Failure.exportTooOld }
        guard let snapshot = try? JSONExport.decode(data) else { throw Failure.unreadable }
        guard let library = snapshot.library else { throw Failure.exportTooOld }

        let quests = Dictionary(try context.fetch(FetchDescriptor<QuestTemplate>()).map { ($0.text, $0.id) },
                                uniquingKeysWith: { a, _ in a })
        let routines = Dictionary(try context.fetch(FetchDescriptor<RoutineTask>()).map { ($0.text, $0.id) },
                                  uniquingKeysWith: { a, _ in a })
        var questIDs: [UUID: UUID] = [:], routineIDs: [UUID: UUID] = [:], unmatched: [String] = []
        for q in library.quests {
            if let id = quests[q.text] { questIDs[q.id] = id } else { unmatched.append(q.text) }
        }
        for r in library.routines {
            if let id = routines[r.text] { routineIDs[r.id] = id } else { unmatched.append(r.text) }
        }

        let days = snapshot.dailyContexts.map(\.dayKey)
        let summary = Summary(
            exportedAt: snapshot.exportedAt,
            firstDayKey: days.min(), lastDayKey: days.max(),
            dailyQuests: snapshot.dailyQuests.count,
            routineOccurrences: snapshot.routineOccurrences.count,
            ledgerEntries: snapshot.ledger.count,
            ratings: snapshot.ratings.count,
            comments: snapshot.comments.count,
            rewards: snapshot.rewards?.count ?? 0,
            balance: Economy.balance(snapshot.ledger),
            unmatchedLibrary: unmatched.sorted())
        return Plan(snapshot: snapshot, summary: summary, questIDs: questIDs, routineIDs: routineIDs)
    }

    /// Replaces the history tables with the backup's and saves — or, if `StoreAudit` finds
    /// anything, rolls back and throws `.audit`, leaving the store exactly as it was.
    public static func apply(_ plan: Plan, to context: ModelContext) throws {
        do {
            try replace(with: plan, in: context)
            let issues = try StoreAudit.issues(context)
            guard issues.isEmpty else { throw Failure.audit(issues) }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func replace(with plan: Plan, in context: ModelContext) throws {
        try deleteAll(DailyQuest.self, in: context)
        try deleteAll(RoutineOccurrence.self, in: context)
        try deleteAll(LedgerEntry.self, in: context)
        try deleteAll(DailyContext.self, in: context)
        try deleteAll(QuestRating.self, in: context)
        try deleteAll(QuestComment.self, in: context)
        try deleteAll(Reward.self, in: context)

        let s = plan.snapshot
        let quest = { (id: UUID) in plan.questIDs[id] ?? id }
        let routine = { (id: UUID) in plan.routineIDs[id] ?? id }
        let target = { (kind: String, id: UUID) in
            kind == FeedbackTarget.routine.rawValue ? routine(id) : quest(id)
        }

        for e in s.ledger {
            let row = LedgerEntry()
            row.id = e.id; row.timestamp = e.timestamp; row.dayKey = e.dayKey; row.kind = e.kind
            row.points = e.points; row.refID = e.refID; row.note = e.note
            context.insert(row)
        }

        for q in s.dailyQuests {
            let row = DailyQuest()
            row.id = q.id; row.dayKey = q.dayKey; row.weekKey = q.weekKey; row.slotRaw = q.slot
            row.isHiddenSlot = q.isHiddenSlot; row.templateID = q.templateID.map(quest)
            row.textSnapshot = q.text; row.launchURLSnapshot = q.launchURL; row.variantSnapshot = q.variant
            row.trivialGroup = q.trivialGroup; row.trivialDone = q.trivialDone
            row.trivialTemplateIDs = q.trivialTemplateIDs.map(quest); row.trivialVariants = q.trivialVariants
            row.points = q.points; row.completedAt = q.completedAt; row.sourceTypeRaw = q.sourceType
            row.rerollCount = q.rerollCount; row.replaced = q.replaced
            row.replacedReasonRaw = q.replacedReason; row.extensionCount = q.extensionCount
            context.insert(row)
        }

        for o in s.routineOccurrences {
            let row = RoutineOccurrence()
            row.id = o.id; row.routineID = o.routineID.map(routine); row.dueDayKey = o.dueDayKey
            row.weekKey = o.weekKey; row.completedDayKey = o.completedDayKey; row.textSnapshot = o.text
            row.usedDegraded = o.usedDegraded; row.degradedTextSnapshot = o.degradedText
            row.degradedRoutineID = o.degradedRoutineID.map(routine)
            row.degradedBasePoints = o.degradedBasePoints; row.basePoints = o.basePoints
            row.countsForClear = o.countsForClear; row.awardedPoints = o.awardedPoints
            row.penaltyApplied = o.penaltyApplied; row.skipped = o.skipped; row.completedAt = o.completedAt
            row.sourceTypeRaw = o.sourceType; row.replacesQuestID = o.replacesQuestID
            row.adHocSourceRoutineID = o.adHocSourceRoutineID.map(routine); row.replacedByID = o.replacedByID
            row.iconKey = o.iconKey
            context.insert(row)
        }

        for c in s.dailyContexts {
            let row = DailyContext()
            row.dayKey = c.dayKey; row.hrv = c.hrv; row.sleepHours = c.sleepHours; row.restingHR = c.restingHR
            row.energy = c.energy; row.readiness = c.readiness; row.tierRaw = c.tier; row.onCycle = c.onCycle
            row.cycleDay = c.cycleDay; row.routineLoad = c.routineLoad; row.randomSlots = c.randomSlots
            context.insert(row)
        }

        for r in s.ratings {
            let row = QuestRating()
            row.id = r.id; row.targetID = r.targetID.map { target(r.targetKind, $0) }; row.questID = r.questID
            row.targetKindRaw = r.targetKind; row.textSnapshot = r.text; row.rating = r.rating
            row.dayKey = r.dayKey; row.timestamp = r.timestamp
            context.insert(row)
        }

        for c in s.comments {
            let row = QuestComment()
            row.id = c.id; row.targetID = c.targetID.map { target(c.targetKind, $0) }; row.questID = c.questID
            row.targetKindRaw = c.targetKind; row.textSnapshot = c.text; row.comment = c.comment
            row.dayKey = c.dayKey; row.timestamp = c.timestamp
            context.insert(row)
        }

        for r in s.rewards ?? [] {
            let row = Reward()
            row.id = r.id; row.name = r.name; row.estimatedCost = r.estimatedCost
            row.virtualKind = r.virtualKind; row.fixedCoins = r.fixedCoins; row.isActive = r.isActive
            row.isGoal = r.isGoal ?? false
            context.insert(row)
        }

        // The stamps come from the backup too. A row the backup doesn't know was never served or
        // done in the history now on the store, so whatever it says belongs to history just deleted.
        let library = s.library ?? JSONExport.Library(quests: [], routines: [])
        let questStamps = Dictionary(library.quests.compactMap { q in plan.questIDs[q.id].map { ($0, q) } },
                                     uniquingKeysWith: { a, _ in a })
        for t in try context.fetch(FetchDescriptor<QuestTemplate>()) {
            t.lastServedDayKey = questStamps[t.id]?.lastServedDayKey
            t.lastCompletedDayKey = questStamps[t.id]?.lastCompletedDayKey
        }
        let routineStamps = Dictionary(library.routines.compactMap { r in plan.routineIDs[r.id].map { ($0, r) } },
                                       uniquingKeysWith: { a, _ in a })
        for r in try context.fetch(FetchDescriptor<RoutineTask>()) {
            r.lastCompletedDayKey = routineStamps[r.id]?.lastCompletedDayKey
        }

        try Affinity.sync(context)
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
        for row in try context.fetch(FetchDescriptor<T>()) { context.delete(row) }
    }
}
