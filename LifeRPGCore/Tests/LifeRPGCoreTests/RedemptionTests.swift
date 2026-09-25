import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// Cancelling a quest or routine, the streak freeze, and real rewards (`PLAN.md` §6).
struct RedemptionTests {
    private let tz = Fixtures.tokyo
    private let friday = "2026-09-18"
    private let saturday = "2026-09-19"

    private func day(_ ctx: ModelContext, _ dayKey: String, fund: Int = 1000) throws {
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 1)
        try DayService.ensureToday(ctx, now: Fixtures.date(dayKey), in: tz, rng: &rng)
        Economy.record(ctx, kind: .adjust, points: fund, dayKey: dayKey)
        try ctx.save()
    }

    private func slot(_ ctx: ModelContext, _ d: Difficulty, on dayKey: String) throws -> DailyQuest {
        try #require(try DayService.quests(on: dayKey, in: ctx)
            .first { $0.slot == d && !$0.replaced && !$0.isHiddenSlot })
    }

    private func redeems(_ ctx: ModelContext) throws -> [LedgerEntry] {
        try ctx.fetch(FetchDescriptor<LedgerEntry>()).filter { $0.kind == "redeem" }
    }

    // MARK: cancelling a quest

    /// The PLAN table, literally: E 120, M 250, H 450; T, hidden and epic aren't for sale.
    @Test func cancelPrices() {
        #expect(Redemption.cancelCost(for: .easy) == 120)
        #expect(Redemption.cancelCost(for: .medium) == 250)
        #expect(Redemption.cancelCost(for: .hard) == 450)
        #expect(Redemption.cancelCost(for: .trivial) == nil)
        #expect(Redemption.cancelCost(for: .epic) == nil)
        #expect(Redemption.cancelRoutineCost == 200)
        #expect(Redemption.streakFreezeCost == 300)
    }

    @Test func aCancelledQuestIsKeptAndChargedAndCanNoLongerBeDone() throws {
        let ctx = try Fixtures.context()
        try day(ctx, friday)
        let h = try slot(ctx, .hard, on: friday)
        try Redemption.cancel(h, on: friday, in: ctx)

        #expect(h.replaced)
        #expect(h.replacedReason == .cancelled)
        #expect(try Economy.balance(ctx) == 550)
        let entry = try #require(try redeems(ctx).first)
        #expect(entry.points == -450)
        #expect(entry.refID == h.id)
        #expect(entry.dayKey == friday)
        var rng = SeededRNG(seed: 2)
        #expect(throws: Completion.Failure.replaced) {
            try Completion.complete(h, tier: .normal, in: ctx, rng: &rng)
        }
    }

    /// It stops gating the clear, but it earns no streak day on its own.
    @Test func aCancelledQuestUnblocksTheClearButNotTheStreak() throws {
        let ctx = try Fixtures.context()
        try day(ctx, friday, fund: 2000)
        for d in [Difficulty.easy, .medium, .hard] {
            try Redemption.cancel(try slot(ctx, d, on: friday), on: friday, in: ctx)
        }
        #expect(try DayService.hiddenUnlocked(on: friday, in: ctx))
        #expect(try Streak.completedDayKeys(ctx).isEmpty)
        let marks = CalendarMarks.marks(quests: try ctx.fetch(FetchDescriptor<DailyQuest>()), occurrences: [])
        #expect(marks[friday] == nil)
    }

    @Test func onlyTodaysOpenRegularSlotsCanBeCancelled() throws {
        let ctx = try Fixtures.context()
        try day(ctx, friday)
        let e = try slot(ctx, .easy, on: friday)
        #expect(Redemption.blocked(cancelling: e, on: saturday, balance: 1000) == .notAvailable)

        let hidden = DailyQuest()
        hidden.dayKey = friday
        hidden.slot = .medium
        hidden.isHiddenSlot = true
        #expect(Redemption.blocked(cancelling: hidden, on: friday, balance: 1000) == .notAvailable)

        let epic = DailyQuest()
        epic.dayKey = friday
        epic.slot = .epic
        #expect(Redemption.blocked(cancelling: epic, on: friday, balance: 1000) == .notAvailable)

        e.completedAt = Date()
        #expect(Redemption.blocked(cancelling: e, on: friday, balance: 1000) == .alreadyCompleted)
    }

    @Test func cancellingObeysTheBalanceRule() throws {
        let ctx = try Fixtures.context()
        try day(ctx, friday, fund: 119)
        let e = try slot(ctx, .easy, on: friday)
        #expect(throws: Purchase.Blocked.tooExpensive(cost: 120, balance: 119)) {
            try Redemption.cancel(e, on: friday, in: ctx)
        }
        Economy.record(ctx, kind: .adjust, points: 1, dayKey: friday)
        try Redemption.cancel(e, on: friday, in: ctx)
        #expect(try Economy.balance(ctx) == 0)
        #expect(Redemption.blocked(cancelling: try slot(ctx, .medium, on: friday), on: friday, balance: -5)
                == .inDebt(balance: -5))
    }

    // MARK: cancelling a routine

    /// Overdue on Saturday: cancelling stops Saturday's deduction; Friday's, already charged, stays.
    @Test func aCancelledRoutineStopsTheLadder() throws {
        let ctx = try Fixtures.context()
        let o = Fixtures.occurrence(ctx, "Trash", due: friday)
        o.basePoints = 20
        Economy.record(ctx, kind: .adjust, points: 1000, dayKey: friday)
        try Overdue.settle(friday, in: ctx, timeZone: tz)          // round day 1: −10
        #expect(o.penaltyApplied == 10)

        try Redemption.cancel(o, flexible: false, on: saturday, in: ctx)
        #expect(o.skipped)
        try Overdue.settle(saturday, in: ctx, timeZone: tz)        // would have been −15
        #expect(o.penaltyApplied == 10)
        #expect(try Economy.balance(ctx) == 1000 - 10 - 200)
        let entry = try #require(try redeems(ctx).first)
        #expect(entry.refID == o.id)
        #expect(entry.dayKey == saturday)
    }

    @Test func aCancelledRoutineNoLongerGatesTheClear() throws {
        let ctx = try Fixtures.context()
        try day(ctx, friday)
        let o = Fixtures.occurrence(ctx, "Trash", due: friday)
        var rng = SeededRNG(seed: 3)
        for q in try DayService.quests(on: friday, in: ctx) {
            try Completion.complete(q, tier: .normal, in: ctx, now: Fixtures.date(friday), rng: &rng)
        }
        #expect(try !DayService.hiddenUnlocked(on: friday, in: ctx))
        try Redemption.cancel(o, flexible: false, on: friday, in: ctx)
        #expect(try DayService.hiddenUnlocked(on: friday, in: ctx))
    }

    @Test func flexibleUngatedAndFutureRoutinesCantBeCancelled() throws {
        let ctx = try Fixtures.context()
        let o = Fixtures.occurrence(ctx, "Run", due: friday)
        #expect(Redemption.blocked(cancelling: o, flexible: true, on: friday, balance: 1000) == .notAvailable)
        #expect(Redemption.blocked(cancelling: o, flexible: false, on: "2026-09-17", balance: 1000) == .notAvailable)
        o.countsForClear = false
        #expect(Redemption.blocked(cancelling: o, flexible: false, on: friday, balance: 1000) == .notAvailable)
    }

    // MARK: streak freeze

    /// Wed and Fri done, Thursday missed; on Saturday the run is 1 and Thursday can be covered.
    /// Covered, the run bridges back to Wednesday — 2 days, not 3: the freeze isn't a done day.
    @Test func aFreezeBridgesOneMissedDay() {
        let days: Set<String> = ["2026-09-16", "2026-09-18"]
        #expect(Streak.current(days: days, today: saturday, in: tz) == 1)
        #expect(Streak.repairableDay(days: days, today: saturday, in: tz) == "2026-09-17")
        #expect(Streak.current(days: days, frozen: ["2026-09-17"], today: saturday, in: tz) == 2)
        #expect(Streak.repairableDay(days: days, frozen: ["2026-09-17"], today: saturday, in: tz) == nil)
    }

    /// Nothing done yesterday and nothing yet today: yesterday is the gap, and it's repairable.
    @Test func yesterdayMissedIsRepairable() {
        let days: Set<String> = ["2026-09-16", "2026-09-17"]
        #expect(Streak.current(days: days, today: saturday, in: tz) == 0)
        #expect(Streak.repairableDay(days: days, today: saturday, in: tz) == friday)
        #expect(Streak.current(days: days, frozen: [friday], today: saturday, in: tz) == 2)
    }

    /// One freeze covers one day: a two-day gap stays broken, and so does no history at all.
    @Test func twoMissedDaysCantBeRepaired() {
        #expect(Streak.repairableDay(days: ["2026-09-16"], today: saturday, in: tz) == nil)
        #expect(Streak.repairableDay(days: [], today: saturday, in: tz) == nil)
    }

    @Test func buyingAFreezeBooksItToTheDayItCovers() throws {
        let ctx = try Fixtures.context()
        for d in ["2026-09-16", "2026-09-18"] {
            let q = DailyQuest()
            q.dayKey = d
            q.slot = .easy
            q.completedAt = Fixtures.date(d)
            ctx.insert(q)
        }
        Economy.record(ctx, kind: .adjust, points: 300, dayKey: friday)
        try ctx.save()

        let covered = try Redemption.freeze(on: saturday, in: ctx, timeZone: tz, now: Fixtures.date(saturday))
        #expect(covered == "2026-09-17")
        let entry = try #require(try ctx.fetch(FetchDescriptor<LedgerEntry>()).first { $0.kind == "freeze" })
        #expect(entry.points == -300)
        #expect(entry.dayKey == "2026-09-17")
        #expect(try Economy.balance(ctx) == 0)
        #expect(try Streak.current(ctx, today: saturday, in: tz) == 2)
        #expect(throws: Purchase.Blocked.nothingToRepair) {
            try Redemption.freeze(on: saturday, in: ctx, timeZone: tz)
        }
    }

    @Test func aFreezeWithNothingToRepairIsRefused() {
        #expect(Redemption.blockedFreeze(days: [friday], frozen: [], today: saturday, balance: 1000, in: tz)
                == .nothingToRepair)
        #expect(Redemption.blockedFreeze(days: ["2026-09-16", friday], frozen: [], today: saturday,
                                         balance: 299, in: tz) == .tooExpensive(cost: 300, balance: 299))
    }

    // MARK: rewards

    @Test func redeemingARewardChargesTodaysPriceOnce() throws {
        let ctx = try Fixtures.context()
        let meal = Reward()
        meal.name = "A nice meal"
        meal.estimatedCost = 100
        ctx.insert(meal)
        Economy.record(ctx, kind: .adjust, points: 1500, dayKey: friday)
        try ctx.save()

        try Redemption.redeem(meal, on: friday, in: ctx)
        let entry = try #require(try redeems(ctx).first)
        #expect(entry.points == -1000)
        #expect(entry.note == "A nice meal")
        #expect(entry.refID == meal.id)

        // Repricing later leaves the redemption at what it cost.
        meal.estimatedCost = 200
        #expect(try redeems(ctx).first?.points == -1000)
        #expect(Redemption.blocked(redeeming: meal, balance: 500) == .tooExpensive(cost: 2000, balance: 500))
        meal.isActive = false
        #expect(Redemption.blocked(redeeming: meal, balance: 5000) == .notAvailable)
    }
}
