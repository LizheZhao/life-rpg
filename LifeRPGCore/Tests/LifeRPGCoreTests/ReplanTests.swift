import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// Re-reading the body data for a day already on screen: what is done stays done, what is open
/// is redrawn (`PLAN.md` §5).
struct ReplanTests {
    private let tz = Fixtures.tokyo
    private let fri = "2026-09-18"

    private func world(_ tier: Tier = .normal) throws -> ModelContext {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx, each: 8)
        var rng = SeededRNG(seed: 3)
        try DayService.ensureToday(ctx, now: Fixtures.date(fri), in: tz,
                                   inputs: DayInputs(tier: tier), rng: &rng)
        return ctx
    }

    private func replan(_ ctx: ModelContext, to inputs: DayInputs) throws -> Replan.Change? {
        var rng = SeededRNG(seed: 11)
        return try Replan.apply(ctx, on: fri, inputs: inputs, in: tz, rng: &rng)
    }

    @Test func thesameTierChangesNothing() throws {
        let ctx = try world()
        #expect(try Replan.preview(ctx, on: fri, inputs: DayInputs(tier: .normal), in: tz) == nil)
        #expect(try replan(ctx, to: DayInputs(tier: .normal)) == nil)
    }

    @Test func aDayThatWasNeverGeneratedHasNothingToReplan() throws {
        let ctx = try Fixtures.context()
        #expect(try Replan.preview(ctx, on: fri, inputs: DayInputs(tier: .low), in: tz) == nil)
    }

    /// The composition follows the new tier: `normal` is E/M/H, `veryLow` is three E slots.
    @Test func openSlotsAreRedrawnForTheNewTier() throws {
        let ctx = try world()
        let before = try DayService.quests(on: fri, in: ctx).map(\.slot).map(\.code).sorted()
        #expect(before == ["E", "H", "M"])

        let change = try #require(try replan(ctx, to: DayInputs(tier: .veryLow)))
        #expect(change.fromTier == .normal)
        #expect(change.toTier == .veryLow)
        #expect(change.redrawnQuests == 3)
        #expect(change.keptQuests == 0)

        let after = try DayService.quests(on: fri, in: ctx).filter { !$0.replaced }
        #expect(after.count == 3)
        #expect(after.allSatisfy { $0.slot == .easy })
        // The old rows are kept as the record that they were once asked for, not deleted.
        #expect(try DayService.quests(on: fri, in: ctx).filter(\.replaced).count == 3)
        #expect(try DayService.dailyContext(for: fri, in: ctx)?.tier == .veryLow)
    }

    /// What is done is never touched: same text, same points, same ledger entry, and the slot it
    /// filled is not drawn again.
    @Test func completedQuestsSurviveUntouched() throws {
        let ctx = try world()
        let done = try #require(try DayService.quests(on: fri, in: ctx).first { $0.slot == .medium })
        var completionRNG = SeededRNG(seed: 2)
        let awarded = try Completion.complete(done, tier: .normal, in: ctx, now: Fixtures.date(fri),
                                              rng: &completionRNG)
        let text = done.textSnapshot

        let change = try #require(try replan(ctx, to: DayInputs(tier: .veryLow)))
        #expect(change.keptQuests == 1)
        #expect(change.redrawnQuests == 2)
        #expect(done.points == awarded)
        #expect(done.textSnapshot == text)
        #expect(!done.replaced)

        // A finished M can't fill one of a very-low day's three E slots, so all three are drawn —
        // and the finished one stays on the page beside them.
        let open = try DayService.quests(on: fri, in: ctx).filter { !$0.replaced }
        #expect(open.filter { $0.completedAt == nil }.count == 3)
        #expect(open.filter { $0.completedAt != nil }.count == 1)
        #expect(Economy.balance(try ctx.fetch(FetchDescriptor<LedgerEntry>())) == awarded)
    }

    /// A day that turns out to be harder than it looked gains its hard slot; the finished easy
    /// one still counts toward it.
    @Test func replanningUpwardsKeepsWhatWasDone() throws {
        let ctx = try world(.veryLow)
        let first = try #require(try DayService.quests(on: fri, in: ctx).first { !$0.isTrivialGroup })
        var completionRNG = SeededRNG(seed: 2)
        try Completion.complete(first, tier: .veryLow, in: ctx, now: Fixtures.date(fri),
                                rng: &completionRNG)

        try replan(ctx, to: DayInputs(tier: .normal))
        let open = try DayService.quests(on: fri, in: ctx).filter { !$0.replaced }
        #expect(open.contains { $0.slot == .hard })
        #expect(open.contains { $0.completedAt != nil })
    }

    /// The same template never shows up twice in one day, including across a re-plan.
    @Test func aRedrawDoesNotRepeatWhatTheDayAlreadyServed() throws {
        let ctx = try world()
        let servedBefore = Set(try DayService.quests(on: fri, in: ctx).compactMap(\.templateID))
        try replan(ctx, to: DayInputs(tier: .veryLow))
        let fresh = try DayService.quests(on: fri, in: ctx)
            .filter { !$0.replaced }
            .compactMap(\.templateID)
        #expect(Set(fresh).isDisjoint(with: servedBefore))
    }

    /// An open routine has its light-version decision made again — the first cycle day arriving
    /// mid-morning is exactly this case. A completed one is left alone.
    @Test func openRoutinesGetTheirDowngradeDecisionRedone() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        let strength = RoutineTask()
        strength.text = "Workout: weight training"; strength.spec = "FRI"; strength.basePoints = 30
        ctx.insert(strength)
        let walk = RoutineTask()
        walk.text = "Walk, 30 minutes"; walk.basePoints = 10
        ctx.insert(walk)
        strength.downgradeIDs = [walk.id]
        var rng = SeededRNG(seed: 5)
        try DayService.ensureToday(ctx, now: Fixtures.date(fri), in: tz,
                                   inputs: DayInputs(tier: .normal), rng: &rng)
        let o = try #require(try DayService.occurrences(dueOn: fri, in: ctx).first)
        #expect(!o.usedDegraded)

        // Day 1 of a period, read at noon: the tier drops to low and the session becomes a walk.
        let change = try #require(try replan(ctx, to: DayInputs(tier: .low, cycleDay: 1)))
        #expect(change.adjustedRoutines == 1)
        #expect(o.usedDegraded)
        #expect(o.displayText == "Walk, 30 minutes")
        #expect(o.effectiveBasePoints == 10)
        #expect(try DayService.dailyContext(for: fri, in: ctx)?.cycleDay == 1)

        // And back up again while it is still open.
        try replan(ctx, to: DayInputs(tier: .normal))
        #expect(!o.usedDegraded)
        #expect(o.displayText == "Workout: weight training")
    }

    @Test func aCompletedRoutineIsNotReopened() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        let strength = RoutineTask()
        strength.text = "Workout: weight training"; strength.spec = "FRI"; strength.basePoints = 30
        ctx.insert(strength)
        let walk = RoutineTask()
        walk.text = "Walk, 30 minutes"; walk.basePoints = 10
        ctx.insert(walk)
        strength.downgradeIDs = [walk.id]
        var rng = SeededRNG(seed: 5)
        try DayService.ensureToday(ctx, now: Fixtures.date(fri), in: tz,
                                   inputs: DayInputs(tier: .normal), rng: &rng)
        let o = try #require(try DayService.occurrences(dueOn: fri, in: ctx).first)
        let paid = try Completion.completeRoutine(o, on: fri, tier: .normal, in: ctx, timeZone: tz)
        #expect(paid == 30)

        let change = try #require(try replan(ctx, to: DayInputs(tier: .low, cycleDay: 1)))
        #expect(change.adjustedRoutines == 0)
        #expect(!o.usedDegraded)
        #expect(o.awardedPoints == 30)
    }
}
