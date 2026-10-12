import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// A routine's difficulty is easy, medium or hard, and what it pays follows from it: the middle of
/// the tier's range (`AdHoc.basePoints`, `PLAN.md`: E 10, M 21, H 38). Like every other library
/// edit it only reaches forward, since an occurrence snapshots the points it was created with.
struct LibraryDifficultyTests {
    private let friday = "2026-09-18"

    private func routine(_ ctx: ModelContext, difficulty: Difficulty = .easy, base: Int = 25) -> RoutineTask {
        let r = RoutineTask()
        r.text = "Piano"; r.kind = .weekly; r.spec = "FRI"; r.difficulty = difficulty; r.basePoints = base
        ctx.insert(r)
        return r
    }

    @Test func theDifficultyDecidesThePayAtTheMiddleOfItsRange() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx)
        try ctx.save()
        for (d, pays) in [(Difficulty.hard, 38), (.medium, 21), (.easy, 10)] {
            try LibraryEdit.setDifficulty(d, forRoutine: r.id, in: ctx)
            #expect(r.difficulty == d && r.basePoints == pays)
        }
    }

    @Test func onlyEasyMediumOrHardApplyToARoutine() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx, difficulty: .medium, base: 21)
        try ctx.save()
        for d in [Difficulty.trivial, .epic] {
            #expect(throws: LibraryEdit.Failure.notARoutineTier) {
                try LibraryEdit.setDifficulty(d, forRoutine: r.id, in: ctx)
            }
        }
        #expect(r.difficulty == .medium && r.basePoints == 21)
    }

    @Test func newPointsApplyToWhatIsScheduledFromNowOn() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx, difficulty: .easy, base: 10)
        let before = RoutineOccurrence(routine: r, dueDayKey: friday, weekKey: "2026-W38")
        ctx.insert(before)
        try ctx.save()
        try LibraryEdit.setDifficulty(.hard, forRoutine: r.id, in: ctx)
        #expect(before.basePoints == 10)                                    // already asked at 10
        #expect(RoutineOccurrence(routine: r, dueDayKey: "2026-09-25", weekKey: "2026-W39").basePoints == 38)
    }

    @Test func aRowThatIsGoneIsAnError() throws {
        let ctx = try Fixtures.context()
        #expect(throws: LibraryEdit.Failure.notFound) {
            try LibraryEdit.setDifficulty(.hard, forRoutine: UUID(), in: ctx)
        }
    }

    // MARK: a quest's tier

    private func quest(_ ctx: ModelContext, difficulty: Difficulty = .easy) -> QuestTemplate {
        let q = QuestTemplate()
        q.text = "Stretch"; q.difficulty = difficulty
        ctx.insert(q)
        return q
    }

    @Test func aQuestCanMoveToAnyOfTheFiveTiers() throws {
        let ctx = try Fixtures.context()
        let q = quest(ctx)
        try ctx.save()
        for d in [Difficulty.trivial, .medium, .hard, .epic, .easy] {
            try LibraryEdit.setDifficulty(d, forQuest: q.id, in: ctx)
            #expect(q.difficulty == d)
        }
    }

    @Test func movingAQuestToEpicClearsHiddenAndWeekendOnly() throws {
        let ctx = try Fixtures.context()
        let q = quest(ctx, difficulty: .medium)
        q.hiddenEligible = true; q.weekendOnly = true
        try ctx.save()
        try LibraryEdit.setDifficulty(.epic, forQuest: q.id, in: ctx)
        #expect(q.difficulty == .epic)
        #expect(!q.hiddenEligible && !q.weekendOnly)
    }

    @Test func movingAQuestBetweenOrdinaryTiersKeepsHiddenAndWeekendOnly() throws {
        let ctx = try Fixtures.context()
        let q = quest(ctx, difficulty: .medium)
        q.hiddenEligible = true; q.weekendOnly = true
        try ctx.save()
        try LibraryEdit.setDifficulty(.hard, forQuest: q.id, in: ctx)
        #expect(q.hiddenEligible && q.weekendOnly)
    }

    /// What is already on a page keeps its own tier: a `DailyQuest` snapshots it.
    @Test func aQuestAlreadyDrawnKeepsItsTier() throws {
        let ctx = try Fixtures.context()
        let q = quest(ctx, difficulty: .easy)
        let drawn = DailyQuest()
        drawn.templateID = q.id; drawn.slot = .easy; drawn.textSnapshot = q.text
        ctx.insert(drawn)
        try ctx.save()
        try LibraryEdit.setDifficulty(.hard, forQuest: q.id, in: ctx)
        #expect(q.difficulty == .hard)
        #expect(drawn.slot == .easy)
    }

    @Test func aQuestThatIsGoneIsAnError() throws {
        let ctx = try Fixtures.context()
        #expect(throws: LibraryEdit.Failure.notFound) {
            try LibraryEdit.setDifficulty(.hard, forQuest: UUID(), in: ctx)
        }
    }

    // MARK: the backup

    private let sideCSV = """
    text,difficulty,hidden_eligible,weekend_only,cooldown_days,auto_verify,launch_url,variants,is_active
    Seed quest,E,FALSE,FALSE,,,,,TRUE
    """
    private let routineCSV = """
    text,frequency_kind,frequency_spec,weekly_target,base_points,difficulty,flexible_within_week,counts_for_clear,is_active,downgrade_of,auto_verify,launch_url,notes
    Seed routine,weekly,SAT,1,25,E,FALSE,TRUE,TRUE,,,,
    """

    private func seeded() throws -> ModelContext {
        let ctx = try Fixtures.context()
        try SeedImporter.seedIfEmpty(ctx, sideQuestsCSV: sideCSV, routinesCSV: routineCSV)
        return ctx
    }

    @Test func aChangedDifficultyIsRestored() throws {
        let source = try seeded()
        let r = try #require(try source.fetch(FetchDescriptor<RoutineTask>()).first)
        try LibraryEdit.setDifficulty(.hard, forRoutine: r.id, in: source)

        let target = try seeded()
        let plan = try JSONImport.plan(try JSONExport.data(source), against: target)
        try JSONImport.apply(plan, to: target)
        let back = try #require(try target.fetch(FetchDescriptor<RoutineTask>()).first)
        #expect(back.difficulty == .hard && back.basePoints == 38 && back.id == r.id)
    }

    /// Same points as the CSV but another tier: the file keeps the tier, because the tier is what
    /// the Library shows and what the next change starts from.
    @Test func aTierChangeSurvivesEvenWhenThePointsMatchTheCSV() throws {
        let source = try seeded()
        let r = try #require(try source.fetch(FetchDescriptor<RoutineTask>()).first)
        r.difficulty = .medium                                              // 25 points, as the CSV says
        try source.save()
        let target = try seeded()
        try JSONImport.apply(try JSONImport.plan(try JSONExport.data(source), against: target), to: target)
        let back = try #require(try target.fetch(FetchDescriptor<RoutineTask>()).first)
        #expect(back.difficulty == .medium && back.basePoints == 25)
    }

    /// A tier that is not one is refused by the audit and the store is left as it was.
    @Test func aTierThatIsNotOneIsRefused() throws {
        let ctx = try seeded()
        var s = try JSONExport.snapshot(ctx)
        s.fullLibrary?.routines[0].difficulty = "bogus"
        let plan = try JSONImport.plan(try JSONExport.encode(s), against: ctx)
        #expect(throws: JSONImport.Failure.self) { try JSONImport.apply(plan, to: ctx) }
        let r = try #require(try ctx.fetch(FetchDescriptor<RoutineTask>()).first)
        #expect(r.difficulty == .easy)
        #expect(try StoreAudit.issues(ctx).isEmpty)
    }
}
