import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// Turning a library row off and changing what a routine pays. Both only reach forward: what is
/// already on the page keeps its own state, which is also what stops "off, then on again" from
/// being a free cancel (a cancel costs coins, `Redemption.cancel`).
struct LibraryEditTests {
    private let tz = Fixtures.tokyo
    private let friday = "2026-09-18"

    private func routine(_ ctx: ModelContext, _ text: String = "Piano", base: Int = 20) -> RoutineTask {
        let r = RoutineTask()
        r.text = text; r.kind = .weekly; r.spec = "FRI"; r.basePoints = base
        ctx.insert(r)
        return r
    }

    // MARK: on and off

    @Test func turningARoutineOffStopsItBeingScheduledOrOffered() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx)
        try ctx.save()
        #expect(!Schedule.dueRoutines([r], occurrences: [], on: friday, in: tz).isEmpty)

        try LibraryEdit.setActive(false, .routine, id: r.id, in: ctx)
        #expect(!r.isActive)
        #expect(Schedule.dueRoutines([r], occurrences: [], on: friday, in: tz).isEmpty)
        #expect(AdHoc.libraryCandidates([r], occurrences: [], on: friday).isEmpty)

        try LibraryEdit.setActive(true, .routine, id: r.id, in: ctx)
        #expect(r.isActive)
    }

    @Test func turningAQuestOffTakesItOutOfThePool() throws {
        let ctx = try Fixtures.context()
        let q = Fixtures.quest(ctx, "Sing a song out loud at home")
        try ctx.save()
        try LibraryEdit.setActive(false, .quest, id: q.id, in: ctx)
        #expect(!q.isActive)
        #expect(try Sampling.activeTemplates(ctx).isEmpty)
    }

    /// What is already open on the page is not touched: it still runs its ladder or its week.
    @Test func whatIsAlreadyOnThePageIsLeftAlone() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx)
        let o = RoutineOccurrence(routine: r, dueDayKey: friday, weekKey: "2026-W38")
        o.penaltyApplied = 10
        ctx.insert(o)
        try ctx.save()

        try LibraryEdit.setActive(false, .routine, id: r.id, in: ctx)
        #expect(!o.skipped && o.completedDayKey == nil && o.penaltyApplied == 10)
        #expect(Schedule.isOpen(o))
    }

    @Test func aRowThatIsGoneIsAnError() throws {
        let ctx = try Fixtures.context()
        #expect(throws: LibraryEdit.Failure.notFound) {
            try LibraryEdit.setActive(false, .quest, id: UUID(), in: ctx)
        }
    }

    // MARK: what a routine pays

    @Test func newPointsApplyToWhatIsScheduledFromNowOn() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx, base: 20)
        let before = RoutineOccurrence(routine: r, dueDayKey: friday, weekKey: "2026-W38")
        ctx.insert(before)
        try ctx.save()

        try LibraryEdit.setBasePoints(30, forRoutine: r.id, in: ctx)
        #expect(r.basePoints == 30)
        #expect(before.basePoints == 20)                                    // already asked at 20
        let after = RoutineOccurrence(routine: r, dueDayKey: "2026-09-25", weekKey: "2026-W39")
        #expect(after.basePoints == 30)
    }

    @Test func aRoutineCannotPayLessThanFive() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx)
        try ctx.save()
        #expect(throws: LibraryEdit.Failure.belowMinimum(5)) {
            try LibraryEdit.setBasePoints(4, forRoutine: r.id, in: ctx)
        }
        #expect(r.basePoints == 20)
        try LibraryEdit.setBasePoints(5, forRoutine: r.id, in: ctx)          // five is allowed
        try LibraryEdit.setBasePoints(5000, forRoutine: r.id, in: ctx)       // and there is no ceiling
        #expect(r.basePoints == 5000)
    }

    // MARK: the backup remembers what changed on the seed rows

    private let sideCSV = """
    text,difficulty,hidden_eligible,weekend_only,cooldown_days,auto_verify,launch_url,variants,is_active
    Seed quest A,E,FALSE,FALSE,,,,,TRUE
    Seed quest B,M,FALSE,FALSE,,,,,FALSE
    """
    private let routineCSV = """
    text,frequency_kind,frequency_spec,weekly_target,base_points,difficulty,flexible_within_week,counts_for_clear,is_active,downgrade_of,auto_verify,launch_url,notes
    Seed routine,weekly,SAT,1,25,E,FALSE,TRUE,TRUE,,,,
    """

    private func seeded() throws -> (ModelContext, JSONExport.Seeds) {
        let ctx = try Fixtures.context()
        _ = try SeedImporter.mergeSeeds(ctx, sideQuestsCSV: sideCSV, routinesCSV: routineCSV)
        return (ctx, .init(sideQuestsCSV: sideCSV, routinesCSV: routineCSV))
    }

    @Test func untouchedSeedRowsAddNothingToTheBackup() throws {
        let (ctx, seeds) = try seeded()
        #expect(try JSONExport.snapshot(ctx, seeds: seeds).libraryChanges == nil)
    }

    @Test func onlyWhatDiffersFromTheCSVIsRemembered() throws {
        let (ctx, seeds) = try seeded()
        let quests = try ctx.fetch(FetchDescriptor<QuestTemplate>())
        let a = try #require(quests.first { $0.text == "Seed quest A" })
        let b = try #require(quests.first { $0.text == "Seed quest B" })   // inactive in the CSV already
        let r = try #require(try ctx.fetch(FetchDescriptor<RoutineTask>()).first)
        try LibraryEdit.setActive(false, .quest, id: a.id, in: ctx)
        try LibraryEdit.setActive(true, .quest, id: b.id, in: ctx)
        try LibraryEdit.setBasePoints(40, forRoutine: r.id, in: ctx)

        let changes = try #require(try JSONExport.snapshot(ctx, seeds: seeds).libraryChanges)
        #expect(Dictionary(uniqueKeysWithValues: changes.quests.map { ($0.text, $0.isActive) })
                == ["Seed quest A": false, "Seed quest B": true])
        #expect(changes.routines.map(\.text) == ["Seed routine"])
        #expect(changes.routines.first?.basePoints == 40 && changes.routines.first?.isActive == true)
    }

    @Test func aReinstallGetsTheChangesBack() throws {
        let (source, seeds) = try seeded()
        let a = try #require(try source.fetch(FetchDescriptor<QuestTemplate>()).first { $0.text == "Seed quest A" })
        let r = try #require(try source.fetch(FetchDescriptor<RoutineTask>()).first)
        try LibraryEdit.setActive(false, .quest, id: a.id, in: source)
        try LibraryEdit.setBasePoints(40, forRoutine: r.id, in: source)

        let (target, _) = try seeded()                                       // a fresh install: the CSV's values
        let plan = try JSONImport.plan(try JSONExport.data(source, seeds: seeds), against: target)
        #expect(plan.summary.libraryChanges == 2)
        try JSONImport.apply(plan, to: target)

        #expect(try target.fetch(FetchDescriptor<QuestTemplate>()).first { $0.text == "Seed quest A" }?.isActive == false)
        #expect(try target.fetch(FetchDescriptor<RoutineTask>()).first?.basePoints == 40)
        // What the backup did not mention keeps the CSV's value.
        #expect(try target.fetch(FetchDescriptor<QuestTemplate>()).first { $0.text == "Seed quest B" }?.isActive == false)
    }

    @Test func aBackupMadeWithoutTheCSVsRecordsNoChanges() throws {
        let (ctx, _) = try seeded()
        let a = try #require(try ctx.fetch(FetchDescriptor<QuestTemplate>()).first { $0.text == "Seed quest A" })
        try LibraryEdit.setActive(false, .quest, id: a.id, in: ctx)
        #expect(try JSONExport.snapshot(ctx).libraryChanges == nil)
    }
}
