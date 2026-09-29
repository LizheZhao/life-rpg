import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// The pinned savings goal (`PLAN.md` §6 "Savings goal").
struct SavingsGoalTests {
    private let tz = Fixtures.tokyo
    private let today = "2026-09-30"

    private func reward(_ ctx: ModelContext, _ name: String, cost: Double) -> Reward {
        let r = Reward()
        r.name = name
        r.estimatedCost = cost
        ctx.insert(r)
        return r
    }

    private func entry(_ kind: Economy.Kind, _ points: Int, _ offset: Int) -> LedgerEntry {
        let e = LedgerEntry()
        e.kind = kind.rawValue
        e.points = points
        e.dayKey = DayKey.adding(offset, to: today, in: tz)!
        return e
    }

    @Test func pinningOneUnpinsTheOther() throws {
        let ctx = try Fixtures.context()
        let meal = reward(ctx, "A nice meal", cost: 100)
        let phones = reward(ctx, "Headphones", cost: 600)
        try SavingsGoal.pin(meal, in: ctx)
        try SavingsGoal.pin(phones, in: ctx)
        #expect(!meal.isGoal)
        #expect(phones.isGoal)
        #expect(SavingsGoal.goal([meal, phones]) === phones)
        try SavingsGoal.unpin(phones, in: ctx)
        #expect(SavingsGoal.goal([meal, phones]) == nil)
    }

    @Test func redeemingOrArchivingTheGoalUnpinsIt() throws {
        let ctx = try Fixtures.context()
        let meal = reward(ctx, "A nice meal", cost: 100)
        let phones = reward(ctx, "Headphones", cost: 600)
        Economy.record(ctx, kind: .adjust, points: 1000, dayKey: today)
        try SavingsGoal.pin(meal, in: ctx)
        try Redemption.redeem(meal, on: today, in: ctx)
        #expect(!meal.isGoal)

        try SavingsGoal.pin(phones, in: ctx)
        try Redemption.archive(phones, in: ctx)
        #expect(!phones.isActive)
        #expect(!phones.isGoal)
        #expect(SavingsGoal.goal([meal, phones]) == nil)
    }

    /// Net over the last 28 days, today and day −27 included, the grant left out: 700 − 100 − 40.
    @Test func paceIsNetOverFourWeeks() {
        let ledger = [
            entry(.grant, 100, -2),
            entry(.quest, 700, -3),
            entry(.reroll, -100, -1),
            entry(.penalty, -40, -27),
            entry(.quest, 500, -28),          // just outside
        ]
        #expect(SavingsGoal.pace(ledger, today: today, in: tz) == 140)
    }

    @Test func weeksLeft() {
        #expect(SavingsGoal.weeksLeft(price: 1000, balance: 400, pace: 150) == 4)
        #expect(SavingsGoal.weeksLeft(price: 1000, balance: 400, pace: 600) == 1)
        #expect(SavingsGoal.weeksLeft(price: 1000, balance: 1000, pace: 0) == 0)
        #expect(SavingsGoal.weeksLeft(price: 1000, balance: 400, pace: 0) == nil)
        #expect(SavingsGoal.weeksLeft(price: 1000, balance: 400, pace: -20) == nil)
    }

    @Test func progressReadsNegativeAsZero() throws {
        let ctx = try Fixtures.context()
        let meal = reward(ctx, "A nice meal", cost: 100)                // 1000 coins
        meal.isGoal = true
        let debt = SavingsGoal.progress(rewards: [meal], ledger: [entry(.penalty, -30, 0)], today: today, in: tz)
        #expect(debt?.fraction == 0)
        #expect(debt?.weeksLeft == nil)

        let saving = try #require(SavingsGoal.progress(rewards: [meal], ledger: [entry(.quest, 400, -1)],
                                                        today: today, in: tz))
        #expect(saving.price == 1000)
        #expect(saving.fraction == 0.4)
        #expect(saving.weeksLeft == 6)                                    // 600 left at 100/week
        #expect(!saving.ready)
    }

    /// An export written before `isGoal` existed still reads, as not a goal.
    @Test func oldRewardRowsDecodeWithoutTheField() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Meal","estimatedCost":100,"isActive":true}"#
        let row = try JSONDecoder().decode(JSONExport.RewardRow.self, from: Data(json.utf8))
        #expect(row.isGoal == nil)
    }

    @Test func theExportCarriesThePin() throws {
        let ctx = try Fixtures.context()
        let meal = reward(ctx, "A nice meal", cost: 100)
        try SavingsGoal.pin(meal, in: ctx)
        let snapshot = try JSONExport.snapshot(ctx)
        #expect(snapshot.rewards?.first?.isGoal == true)
    }
}
