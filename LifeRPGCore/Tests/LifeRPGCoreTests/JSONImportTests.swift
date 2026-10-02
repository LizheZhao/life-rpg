import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// Stage 6's "done when": export, reinstall (a fresh store reseeded with new UUIDs), import — and
/// the balance matches exactly.
struct JSONImportTests {
    private let tz = Fixtures.tokyo
    private let saturday = "2026-09-19"
    private let routineText = "Workout: weight training"

    private func routine(_ ctx: ModelContext) -> RoutineTask {
        let r = RoutineTask()
        r.text = routineText; r.kind = .weekly; r.spec = "SAT"; r.basePoints = 50
        ctx.insert(r)
        return r
    }

    /// A store with a real day behind it: every quest done, the routine done, a rating, a reward
    /// bought, the opening grant.
    private func sourceStore() throws -> ModelContext {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        routine(ctx)
        try ctx.save()
        try Economy.grantStartingBalanceIfNeeded(ctx, dayKey: saturday, now: Fixtures.date(saturday))

        var rng = SeededRNG(seed: 7)
        let now = Fixtures.date(saturday, hour: 10)
        try DayService.ensureToday(ctx, now: now, in: tz, rng: &rng)
        for quest in try DayService.quests(on: saturday, in: ctx) {
            quest.trivialDone = quest.trivialDone.map { _ in true }
            try Completion.complete(quest, tier: .normal, in: ctx, rng: &rng)
        }
        for o in try DayService.occurrences(dueOn: saturday, in: ctx) {
            try Completion.completeRoutine(o, on: saturday, tier: .normal, in: ctx, now: now, timeZone: tz)
        }

        let rated = try #require(try DayService.quests(on: saturday, in: ctx).first { $0.templateID != nil && !$0.isTrivialGroup })
        Feedback.rate(ctx, target: .quest, id: rated.templateID, questID: rated.id,
                      text: rated.textSnapshot, rating: 2, dayKey: saturday, now: now)
        try Affinity.sync(ctx)

        let reward = Reward()
        reward.name = "Coffee beans"; reward.fixedCoins = 30
        ctx.insert(reward)
        try ctx.save()
        try Redemption.redeem(reward, on: saturday, in: ctx, now: now)
        return ctx
    }

    /// A reinstall: same seed texts, new UUIDs, the opening grant and a day of its own already on it.
    private func freshStore() throws -> ModelContext {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        routine(ctx)
        try ctx.save()
        try Economy.grantStartingBalanceIfNeeded(ctx, dayKey: "2026-09-27")
        var rng = SeededRNG(seed: 99)
        try DayService.ensureToday(ctx, now: Fixtures.date("2026-09-27"), in: tz, rng: &rng)
        return ctx
    }

    private func restore(_ source: ModelContext, into target: ModelContext) throws -> JSONImport.Plan {
        let plan = try JSONImport.plan(try JSONExport.data(source), against: target)
        try JSONImport.apply(plan, to: target)
        return plan
    }

    // MARK: the done-when

    @Test func balanceMatchesExactlyAfterAReinstall() throws {
        let source = try sourceStore()
        let target = try freshStore()
        _ = try restore(source, into: target)

        #expect(try Economy.balance(target) == (try Economy.balance(source)))
        #expect(try Economy.totalEarned(target) == (try Economy.totalEarned(source)))
        // One grant, the source's — the reinstall's own is replaced, not added to.
        let grant = Economy.Kind.grant.rawValue
        #expect(try target.fetchCount(FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.kind == grant })) == 1)
    }

    @Test func historyReplacesWhatTheTargetHad() throws {
        let source = try sourceStore()
        let target = try freshStore()
        _ = try restore(source, into: target)

        let ids = { (ctx: ModelContext) in Set(try ctx.fetch(FetchDescriptor<DailyQuest>()).map(\.id)) }
        #expect(try ids(target) == (try ids(source)))
        #expect(try target.fetch(FetchDescriptor<DailyContext>()).map(\.dayKey) == [saturday])
        #expect(try target.fetchCount(FetchDescriptor<RoutineOccurrence>())
                == (try source.fetchCount(FetchDescriptor<RoutineOccurrence>())))
        #expect(try target.fetch(FetchDescriptor<Reward>()).map(\.name) == ["Coffee beans"])
    }

    // MARK: ids — the reinstall gave every library row a new UUID

    @Test func templateAndRoutineIDsAreRemappedByText() throws {
        let source = try sourceStore()
        let target = try freshStore()
        _ = try restore(source, into: target)

        let templates = Dictionary(uniqueKeysWithValues:
            try target.fetch(FetchDescriptor<QuestTemplate>()).map { ($0.id, $0.text) })
        for q in try target.fetch(FetchDescriptor<DailyQuest>()) {
            if let id = q.templateID { #expect(templates[id] == q.textSnapshot) }
            for (id, text) in zip(q.trivialTemplateIDs, q.trivialGroup) { #expect(templates[id] == text) }
        }

        let targetRoutine = try #require(try target.fetch(FetchDescriptor<RoutineTask>()).first)
        let occurrences = try target.fetch(FetchDescriptor<RoutineOccurrence>())
        #expect(!occurrences.isEmpty)
        #expect(occurrences.allSatisfy { $0.routineID == targetRoutine.id })

        let rating = try #require(try target.fetch(FetchDescriptor<QuestRating>()).first)
        #expect(templates[try #require(rating.targetID)] == rating.textSnapshot)
    }

    @Test func cooldownsScheduleAndAffinityComeBack() throws {
        let source = try sourceStore()
        let target = try freshStore()
        _ = try restore(source, into: target)

        let byText = { (ctx: ModelContext) in
            Dictionary(uniqueKeysWithValues: try ctx.fetch(FetchDescriptor<QuestTemplate>()).map { ($0.text, $0) })
        }
        let before = try byText(source), after = try byText(target)
        for (text, t) in before {
            let restored = try #require(after[text])
            #expect(restored.lastServedDayKey == t.lastServedDayKey, "\(text)")
            #expect(restored.lastCompletedDayKey == t.lastCompletedDayKey, "\(text)")
            #expect(restored.affinity == t.affinity, "\(text)")
        }
        #expect(after.values.contains { $0.affinity == 2 })
        #expect(try target.fetch(FetchDescriptor<RoutineTask>()).first?.lastCompletedDayKey == saturday)
    }

    /// Stamps the target set itself, on a day the backup never saw, belong to history that is gone.
    @Test func stampsNotInTheBackupAreCleared() throws {
        let source = try sourceStore()
        let target = try freshStore()
        let extra = Fixtures.quest(target, "Only in the new CSV", served: "2026-09-27")
        try target.save()
        _ = try restore(source, into: target)
        #expect(extra.lastServedDayKey == nil)
    }

    // MARK: preview

    @Test func planSummarisesWithoutWriting() throws {
        let source = try sourceStore()
        Fixtures.quest(source, "Removed from the CSV since")
        try source.save()
        let target = try freshStore()
        let balanceBefore = try Economy.balance(target)

        let plan = try JSONImport.plan(try JSONExport.data(source), against: target)
        #expect(plan.summary.balance == (try Economy.balance(source)))
        #expect(plan.summary.dailyQuests == (try source.fetchCount(FetchDescriptor<DailyQuest>())))
        #expect(plan.summary.ledgerEntries == (try source.fetchCount(FetchDescriptor<LedgerEntry>())))
        #expect(plan.summary.ratings == 1)
        #expect(plan.summary.rewards == 1)
        #expect(plan.summary.unmatchedLibrary == ["Removed from the CSV since"])
        #expect(plan.summary.lastDayKey == saturday)
        #expect(try Economy.balance(target) == balanceBefore)
    }

    // MARK: the doodle a custom routine wears (SchemaV4, export v4)

    private func sourceWithACustomRoutine() throws -> ModelContext {
        let source = try sourceStore()
        let custom = RoutineOccurrence()
        custom.textSnapshot = "Fix the bike"; custom.dueDayKey = saturday; custom.weekKey = "2026-W38"
        custom.basePoints = 38; custom.iconKey = "dumbbell"
        source.insert(custom)
        try source.save()
        return source
    }

    @Test func aChosenDoodleSurvivesARestore() throws {
        let source = try sourceWithACustomRoutine()
        let target = try freshStore()
        _ = try restore(source, into: target)

        let restored = try #require(try target.fetch(FetchDescriptor<RoutineOccurrence>())
            .first { $0.textSnapshot == "Fix the bike" })
        #expect(restored.iconKey == "dumbbell")
        #expect(restored.doodle == .dumbbell)
        #expect(try target.fetch(FetchDescriptor<RoutineOccurrence>())
            .filter { $0.textSnapshot != "Fix the bike" }.allSatisfy { $0.iconKey == nil })
    }

    /// A backup made before the column existed: version 3, no `iconKey` anywhere. It restores, and
    /// every row keeps the doodle its text gives it.
    @Test func aVersion3ExportStillImports() throws {
        let source = try sourceWithACustomRoutine()
        var json = try #require(try JSONSerialization.jsonObject(with: try JSONExport.data(source)) as? [String: Any])
        json["schemaVersion"] = 3
        var rows = try #require(json["routineOccurrences"] as? [[String: Any]])
        for i in rows.indices { rows[i].removeValue(forKey: "iconKey") }
        json["routineOccurrences"] = rows
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(!String(decoding: data, as: UTF8.self).contains("iconKey"))

        let target = try freshStore()
        let plan = try JSONImport.plan(data, against: target)
        try JSONImport.apply(plan, to: target)
        #expect(try Economy.balance(target) == (try Economy.balance(source)))
        let restored = try target.fetch(FetchDescriptor<RoutineOccurrence>())
        #expect(restored.count == (try source.fetchCount(FetchDescriptor<RoutineOccurrence>())))
        #expect(restored.allSatisfy { $0.iconKey == nil })
    }

    @Test func anUnknownDoodleKeyRestoresAndFallsBackToTheText() throws {
        let source = try sourceWithACustomRoutine()
        var snapshot = try JSONExport.snapshot(source)
        let i = try #require(snapshot.routineOccurrences.firstIndex { $0.text == "Fix the bike" })
        snapshot.routineOccurrences[i].iconKey = "telescope"
        let target = try freshStore()
        let plan = try JSONImport.plan(try JSONExport.encode(snapshot), against: target)
        try JSONImport.apply(plan, to: target)

        let restored = try #require(try target.fetch(FetchDescriptor<RoutineOccurrence>())
            .first { $0.textSnapshot == "Fix the bike" })
        #expect(restored.iconKey == "telescope")
        #expect(restored.doodle == DoodleKey.forText("Fix the bike"))
    }

    // MARK: refusing

    @Test func anAuditFailureRollsEverythingBack() throws {
        let source = try sourceStore()
        var snapshot = try JSONExport.snapshot(source)
        snapshot.dailyQuests[0].slot = "legendary"
        let target = try freshStore()
        let balanceBefore = try Economy.balance(target)
        let questsBefore = Set(try target.fetch(FetchDescriptor<DailyQuest>()).map(\.id))

        let plan = try JSONImport.plan(try JSONExport.encode(snapshot), against: target)
        #expect(throws: JSONImport.Failure.audit([
            StoreAudit.Issue(model: "DailyQuest", field: "slotRaw", value: "legendary", count: 1)
        ])) { try JSONImport.apply(plan, to: target) }

        #expect(try Economy.balance(target) == balanceBefore)
        #expect(Set(try target.fetch(FetchDescriptor<DailyQuest>()).map(\.id)) == questsBefore)
    }

    @Test func aNewerExportIsRefused() throws {
        var snapshot = try JSONExport.snapshot(try sourceStore())
        snapshot.schemaVersion = JSONExport.schemaVersion + 1
        #expect(throws: JSONImport.Failure.newerExport(JSONExport.schemaVersion + 1)) {
            try JSONImport.plan(try JSONExport.encode(snapshot), against: try Fixtures.context())
        }
    }

    @Test func anExportWithoutTheLibraryIsTooOld() throws {
        var snapshot = try JSONExport.snapshot(try sourceStore())
        snapshot.library = nil
        #expect(throws: JSONImport.Failure.exportTooOld) {
            try JSONImport.plan(try JSONExport.encode(snapshot), against: try Fixtures.context())
        }
    }

    @Test func anOlderSchemaVersionIsTooOld() throws {
        // Only the version is read before refusing, so the rest of the file may be anything.
        let data = Data(#"{"schemaVersion": 2, "ledger": "whatever"}"#.utf8)
        #expect(throws: JSONImport.Failure.exportTooOld) {
            try JSONImport.plan(data, against: try Fixtures.context())
        }
    }

    @Test func notJSONIsUnreadable() throws {
        #expect(throws: JSONImport.Failure.unreadable) {
            try JSONImport.plan(Data("LifeRPG".utf8), against: try Fixtures.context())
        }
    }
}
