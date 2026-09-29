import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// The fixed level track and every rule it prices (`PLAN.md` §6 "Level"). Numbers are the PLAN's
/// literals, not recomputed from the formula under test.
struct PerksTests {
    private let tz = Fixtures.tokyo
    private let friday = "2026-09-18"
    private let saturday = "2026-09-19"

    // MARK: the track

    @Test func levelThresholdsMatchThePlanTable() {
        #expect(Economy.earnedNeeded(forLevel: 1) == 0)
        #expect(Economy.earnedNeeded(forLevel: 3) == 240)
        #expect(Economy.earnedNeeded(forLevel: 5) == 960)
        #expect(Economy.earnedNeeded(forLevel: 8) == 2940)
        #expect(Economy.earnedNeeded(forLevel: 10) == 4860)
        #expect(Economy.earnedNeeded(forLevel: 12) == 7260)
        #expect(Economy.earnedNeeded(forLevel: 15) == 11760)
        #expect(Economy.earnedNeeded(forLevel: 20) == 21660)
        #expect(Economy.level(totalEarned: 239) == 2)
        #expect(Economy.level(totalEarned: 240) == 3)
    }

    @Test func trackIsInPlanOrder() {
        #expect(Perks.track.map(\.level) == [3, 5, 8, 10, 12, 15, 20])
        #expect(Perks.track == [.freeReroll, .thirdExtension, .betterMakeUp, .monthlyFreeze,
                                .cheaperEpicReroll, .secondFreeReroll, .cheaperFreeze])
    }

    @Test func newlyUnlockedIsTheHalfOpenRange() {
        #expect(Perks.newlyUnlocked(from: 2, to: 5) == [.freeReroll, .thirdExtension])
        #expect(Perks.newlyUnlocked(from: 3, to: 4) == [])
        #expect(Perks.newlyUnlocked(from: 0, to: 1) == [])
        #expect(Perks.unlocked(at: 9) == [.freeReroll, .thirdExtension, .betterMakeUp])
    }

    @Test func numbersPerLevel() {
        #expect(Perks.freeRerollsPerDay(level: 2) == 0)
        #expect(Perks.freeRerollsPerDay(level: 3) == 1)
        #expect(Perks.freeRerollsPerDay(level: 14) == 1)
        #expect(Perks.freeRerollsPerDay(level: 15) == 2)
        #expect(Perks.epicMaxExtensions(level: 4) == 2)
        #expect(Perks.epicMaxExtensions(level: 5) == 3)
        #expect(Perks.lateMakeUpRate(level: 7) == 0.5)
        #expect(Perks.lateMakeUpRate(level: 8) == 0.6)
        #expect(Perks.monthlyFreeFreezes(level: 9) == 0)
        #expect(Perks.monthlyFreeFreezes(level: 10) == 1)
        #expect(Perks.epicRerollCost(level: 11) == 80)
        #expect(Perks.epicRerollCost(level: 12) == 40)
        #expect(Perks.freezeCost(level: 19) == 300)
        #expect(Perks.freezeCost(level: 20) == 150)
    }

    // MARK: late make-up

    /// PLAN §4's example, base 50: 25 at 50%, 30 at 60%.
    @Test func lateMakeUpPaysSixtyPercentFromLevelEight() {
        #expect(Scoring.routinePoints(basePoints: 50, tier: .normal, late: true, level: 7) == 25)
        #expect(Scoring.routinePoints(basePoints: 50, tier: .normal, late: true, level: 8) == 30)
        #expect(Scoring.routinePoints(basePoints: 25, tier: .low, late: true, level: 8) == 20)   // 19.5
        #expect(Scoring.routinePoints(basePoints: 50, tier: .normal, late: false, level: 8) == 50)
    }

    @Test func completingLateReadsTheLevelFromTheLedger() throws {
        let ctx = try Fixtures.context()
        let o = Fixtures.occurrence(ctx, "Strength", due: "2026-09-17")
        o.basePoints = 50
        Economy.record(ctx, kind: .adjust, points: 2940, dayKey: "2026-09-01")      // Lv 8
        try ctx.save()
        let paid = try Completion.completeRoutine(o, on: friday, tier: .normal, in: ctx,
                                                  now: Fixtures.date(friday), timeZone: tz)
        #expect(paid == 30)
    }

    // MARK: rerolls

    private func quest(_ slot: Difficulty, rerollCount: Int = 0) -> DailyQuest {
        let q = DailyQuest()
        q.slot = slot
        q.dayKey = friday
        q.rerollCount = rerollCount
        return q
    }

    @Test func rerollPricesFollowTheLevel() {
        #expect(Reroll.cost(for: quest(.easy), level: 2) == 10)
        #expect(Reroll.cost(for: quest(.easy), level: 3, freeUsedToday: 0) == 0)
        #expect(Reroll.cost(for: quest(.easy, rerollCount: 1), level: 3, freeUsedToday: 1) == 15)
        #expect(Reroll.cost(for: quest(.hard), level: 15, freeUsedToday: 1) == 0)
        #expect(Reroll.cost(for: quest(.hard), level: 15, freeUsedToday: 2) == 30)
        #expect(Reroll.cost(for: quest(.epic), level: 3, freeUsedToday: 0) == 80)    // never free
        #expect(Reroll.cost(for: quest(.epic), level: 12) == 40)
    }

    @Test func aFreeRerollIsStillRefusedInDebt() {
        #expect(Reroll.blocked(for: quest(.easy), on: friday, balance: -5, level: 3, in: tz)
                == .inDebt(balance: -5))
        #expect(Reroll.blocked(for: quest(.easy), on: friday, balance: 0, level: 3, in: tz) == nil)
    }

    /// The free one writes a 0-point entry and still advances the slot's count; the next one pays.
    @Test func performingAFreeReroll() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 1)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz, rng: &rng)
        Economy.record(ctx, kind: .adjust, points: 300, dayKey: friday)              // Lv 3
        try ctx.save()
        let old = try #require(try DayService.quests(on: friday, in: ctx)
            .first { $0.slot == .easy && !$0.replaced && !$0.isHiddenSlot })

        let fresh = try Reroll.perform(old, on: friday, in: ctx, timeZone: tz, now: Fixtures.date(friday), rng: &rng)
        #expect(fresh.rerollCount == 1)
        #expect(try Reroll.freeRerollsUsed(ctx, on: friday) == 1)
        #expect(try Economy.balance(ctx) == 300)

        _ = try Reroll.perform(fresh, on: friday, in: ctx, timeZone: tz, now: Fixtures.date(friday), rng: &rng)
        let spends = try ctx.fetch(FetchDescriptor<LedgerEntry>()).filter { $0.kind == "reroll" }.map(\.points)
        #expect(spends.sorted() == [-15, 0])
        #expect(try Economy.balance(ctx) == 285)
    }

    // MARK: epic extension

    @Test func aThirdExtensionFromLevelFive() {
        let epic = DailyQuest()
        epic.slot = .epic
        epic.dayKey = "2026-09-14"
        epic.extensionCount = 2
        #expect(Epic.blocked(epic, on: friday, balance: 1000, level: 4, in: tz) == .maxExtensions)
        #expect(Epic.blocked(epic, on: friday, balance: 1000, level: 5, in: tz) == nil)
        epic.extensionCount = 3
        #expect(Epic.blocked(epic, on: friday, balance: 1000, level: 20, in: tz) == .maxExtensions)
    }

    // MARK: freeze

    private func freezeEntry(_ dayKey: String, points: Int) -> LedgerEntry {
        let e = LedgerEntry()
        e.kind = Economy.Kind.freeze.rawValue
        e.dayKey = dayKey
        e.points = points
        return e
    }

    @Test func freezePricesFollowTheLevelAndTheMonth() {
        #expect(Redemption.freezeCost(covering: "2026-09-17", level: 9, ledger: []) == 300)
        #expect(Redemption.freezeCost(covering: "2026-09-17", level: 10, ledger: []) == 0)
        // This month's free one is used; a paid one doesn't use it up.
        #expect(Redemption.freezeCost(covering: "2026-09-17", level: 10,
                                      ledger: [freezeEntry("2026-09-03", points: 0)]) == 300)
        #expect(Redemption.freezeCost(covering: "2026-09-17", level: 10,
                                      ledger: [freezeEntry("2026-09-03", points: -300)]) == 0)
        // Last month's doesn't count against this one.
        #expect(Redemption.freezeCost(covering: "2026-09-17", level: 10,
                                      ledger: [freezeEntry("2026-08-30", points: 0)]) == 0)
        #expect(Redemption.freezeCost(covering: "2026-09-17", level: 20,
                                      ledger: [freezeEntry("2026-09-03", points: 0)]) == 150)
    }

    @Test func aFreeFreezeBooksZeroAndStillCovers() throws {
        let ctx = try Fixtures.context()
        for d in ["2026-09-16", friday] {
            let q = DailyQuest()
            q.dayKey = d
            q.slot = .easy
            q.completedAt = Fixtures.date(d)
            ctx.insert(q)
        }
        Economy.record(ctx, kind: .adjust, points: 4860, dayKey: "2026-09-01")      // Lv 10
        try ctx.save()

        let covered = try Redemption.freeze(on: saturday, in: ctx, timeZone: tz, now: Fixtures.date(saturday))
        #expect(covered == "2026-09-17")
        let entry = try #require(try ctx.fetch(FetchDescriptor<LedgerEntry>()).first { $0.kind == "freeze" })
        #expect(entry.points == 0)
        #expect(try Economy.balance(ctx) == 4860)
        #expect(try Streak.current(ctx, today: saturday, in: tz) == 2)
    }
}
