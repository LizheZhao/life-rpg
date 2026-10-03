import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// The library has two layers: the seed CSVs' rows, which a reinstall brings back on its own, and
/// the rows the user saved, which exist nowhere else. The second layer travels in the backup.
struct UserLibraryTests {
    private let tz = Fixtures.tokyo
    private let day = "2026-09-19", week = "2026-W38"

    private func mineQuest(_ ctx: ModelContext, _ text: String = "Call grandma") -> QuestTemplate {
        let t = Fixtures.quest(ctx, text, .hard, hidden: true, weekendOnly: true, variants: ["a", "b"])
        t.origin = .user
        t.cooldownDaysOverride = 5
        t.launchURLString = "https://example.com"
        return t
    }

    private func mineRoutine(_ ctx: ModelContext, _ text: String = "Piano practice") -> RoutineTask {
        let r = RoutineTask()
        r.text = text; r.origin = .user; r.difficulty = .medium; r.basePoints = 21
        r.kind = .weekly; r.spec = "MON,THU"; r.weeklyTarget = 2; r.flexibleWithinWeek = true
        ctx.insert(r)
        return r
    }

    // MARK: the model

    @Test func everyExistingRowIsASeedRow() {
        #expect(QuestTemplate().origin == .seed)
        #expect(RoutineTask().origin == .seed)
    }

    // MARK: export

    @Test func onlyTheUsersOwnRowsAreExportedInFull() throws {
        let ctx = try Fixtures.context()
        Fixtures.quest(ctx, "From the CSV")
        let q = mineQuest(ctx)
        let r = mineRoutine(ctx)
        let seedRoutine = RoutineTask()
        seedRoutine.text = "Also from the CSV"
        ctx.insert(seedRoutine)
        try ctx.save()

        let mine = try #require(try JSONExport.snapshot(ctx).userLibrary)
        #expect(mine.quests.map(\.text) == ["Call grandma"])
        let quest = try #require(mine.quests.first)
        #expect(quest.id == q.id && quest.difficulty == "hard" && quest.hiddenEligible && quest.weekendOnly)
        #expect(quest.cooldownDaysOverride == 5 && quest.variants == ["a", "b"] && quest.isActive)
        #expect(quest.launchURL == "https://example.com")

        #expect(mine.routines.map(\.text) == ["Piano practice"])
        let routine = try #require(mine.routines.first)
        #expect(routine.id == r.id && routine.difficulty == "medium" && routine.basePoints == 21)
        #expect(routine.kind == "weekly" && routine.spec == "MON,THU" && routine.weeklyTarget == 2)
        #expect(routine.flexibleWithinWeek && routine.countsForClear)
    }

    @Test func aBackupWithNothingOfTheUsersCarriesNoSuchBlock() throws {
        let ctx = try Fixtures.context()
        Fixtures.quest(ctx, "From the CSV")
        try ctx.save()
        #expect(try JSONExport.snapshot(ctx).userLibrary == nil)
    }

    // MARK: import

    /// A source store with the user's quest and routine, each used by history and rated, and a
    /// fresh store a reinstall would leave: the CSV rows only.
    private func restoredStores() throws -> (source: ModelContext, target: ModelContext, plan: JSONImport.Plan) {
        let source = try Fixtures.context()
        let q = mineQuest(source)
        let r = mineRoutine(source)
        let drawn = DailyQuest()
        drawn.dayKey = day; drawn.weekKey = week; drawn.slot = .hard
        drawn.templateID = q.id; drawn.textSnapshot = q.text
        let occurrence = RoutineOccurrence()
        occurrence.dueDayKey = day; occurrence.weekKey = week
        occurrence.routineID = r.id; occurrence.textSnapshot = r.text
        source.insert(drawn); source.insert(occurrence)
        Feedback.rate(source, target: .quest, id: q.id, questID: drawn.id, text: q.text, rating: 2, dayKey: day)
        Feedback.rate(source, target: .routine, id: r.id, text: r.text, rating: 1, dayKey: day)
        try source.save()

        let target = try Fixtures.context()
        Fixtures.quest(target, "From the CSV")
        try target.save()
        let plan = try JSONImport.plan(try JSONExport.data(source), against: target)
        try JSONImport.apply(plan, to: target)
        return (source, target, plan)
    }

    @Test func theUsersRowsComeBackWithTheirOwnIds() throws {
        let (source, target, plan) = try restoredStores()
        let quests = try target.fetch(FetchDescriptor<QuestTemplate>())
        let mine = try #require(quests.first { $0.text == "Call grandma" })
        let original = try #require(try source.fetch(FetchDescriptor<QuestTemplate>()).first { $0.origin == .user })
        #expect(mine.origin == .user && mine.id == original.id)
        #expect(mine.difficulty == .hard && mine.hiddenEligible && mine.weekendOnly && mine.cooldownDaysOverride == 5)
        #expect(mine.variants == ["a", "b"] && mine.launchURLString == "https://example.com")

        let routine = try #require(try target.fetch(FetchDescriptor<RoutineTask>()).first { $0.text == "Piano practice" })
        #expect(routine.origin == .user && routine.spec == "MON,THU" && routine.weeklyTarget == 2)
        #expect(routine.flexibleWithinWeek && routine.basePoints == 21)
        #expect(plan.summary.unmatchedLibrary.isEmpty)
        #expect(plan.summary.userQuests == 1 && plan.summary.userRoutines == 1)
    }

    @Test func historyAndRatingsPointAtTheRestoredRows() throws {
        let (_, target, _) = try restoredStores()
        let quest = try #require(try target.fetch(FetchDescriptor<QuestTemplate>()).first { $0.text == "Call grandma" })
        let routine = try #require(try target.fetch(FetchDescriptor<RoutineTask>()).first { $0.text == "Piano practice" })
        #expect(try target.fetch(FetchDescriptor<DailyQuest>()).allSatisfy { $0.templateID == quest.id })
        #expect(try target.fetch(FetchDescriptor<RoutineOccurrence>()).allSatisfy { $0.routineID == routine.id })
        let ratings = try target.fetch(FetchDescriptor<QuestRating>())
        #expect(Set(ratings.compactMap(\.targetID)) == [quest.id, routine.id])
        #expect(StoreAuditCheck.isClean(target))
    }

    /// Restoring never deletes: a row of the user's that is already there, whatever its id, is the
    /// one the backup's id is re-pointed at, not a second copy.
    @Test func aRowThatIsAlreadyThereIsNotDuplicated() throws {
        let source = try Fixtures.context()
        let q = mineQuest(source)
        let drawn = DailyQuest()
        drawn.dayKey = day; drawn.weekKey = week; drawn.slot = .hard
        drawn.templateID = q.id; drawn.textSnapshot = q.text
        source.insert(drawn)
        try source.save()

        let target = try Fixtures.context()
        let existing = mineQuest(target)
        try target.save()
        #expect(existing.id != q.id)
        let plan = try JSONImport.plan(try JSONExport.data(source), against: target)
        try JSONImport.apply(plan, to: target)

        #expect(try target.fetch(FetchDescriptor<QuestTemplate>()).filter { $0.text == "Call grandma" }.count == 1)
        #expect(try target.fetch(FetchDescriptor<DailyQuest>()).allSatisfy { $0.templateID == existing.id })
    }

    @Test func aBackupFromBeforeTheUsersLayerStillRestores() throws {
        let source = try Fixtures.context()
        Fixtures.quest(source, "From the CSV")
        try source.save()
        var snapshot = try JSONExport.snapshot(source)
        snapshot.userLibrary = nil
        let target = try Fixtures.context()
        let plan = try JSONImport.plan(try JSONExport.encode(snapshot), against: target)
        #expect(plan.summary.userQuests == 0 && plan.summary.userRoutines == 0)
        try JSONImport.apply(plan, to: target)
    }
}

/// `StoreAudit` as a yes / no, for tests that only need to know nothing dangles.
private enum StoreAuditCheck {
    static func isClean(_ ctx: ModelContext) -> Bool { (try? StoreAudit.issues(ctx))?.isEmpty ?? false }
}
