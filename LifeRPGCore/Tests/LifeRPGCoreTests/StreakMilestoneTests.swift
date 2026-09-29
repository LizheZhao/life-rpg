import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// Streak milestone bonuses (`PLAN.md` §6 "Streak milestones").
struct StreakMilestoneTests {
    private let tz = Fixtures.tokyo
    private let today = "2026-09-30"

    /// `count` consecutive days ending `last`.
    private func run(_ count: Int, endingOn last: String) -> Set<String> {
        Set((0..<count).map { DayKey.adding(-$0, to: last, in: tz)! })
    }

    private func day(_ offset: Int) -> String { DayKey.adding(offset, to: today, in: tz)! }

    private func paid(_ threshold: Int, on dayKey: String) -> LedgerEntry {
        let e = LedgerEntry()
        e.kind = Economy.Kind.streak.rawValue
        e.dayKey = dayKey
        e.points = StreakMilestone.coins(at: threshold)!
        e.note = "Streak \(threshold)"
        return e
    }

    // MARK: the table

    @Test func thresholdsPayThePlanLiterals() {
        #expect(StreakMilestone.coins(at: 7) == 50)
        #expect(StreakMilestone.coins(at: 14) == 100)
        #expect(StreakMilestone.coins(at: 30) == 250)
        #expect(StreakMilestone.coins(at: 60) == 400)
        #expect(StreakMilestone.coins(at: 100) == 600)
        #expect(StreakMilestone.coins(at: 130) == 300)
        #expect(StreakMilestone.coins(at: 160) == 300)
        #expect(StreakMilestone.coins(at: 8) == nil)
        #expect(StreakMilestone.coins(at: 115) == nil)
        #expect(StreakMilestone.coins(at: 120) == nil)
    }

    @Test func thresholdsThroughACount() {
        #expect(StreakMilestone.thresholds(through: 6) == [])
        #expect(StreakMilestone.thresholds(through: 14) == [7, 14])
        #expect(StreakMilestone.thresholds(through: 165) == [7, 14, 30, 60, 100, 130, 160])
    }

    // MARK: what is due

    @Test func aFreshThirtyDayRunOwesThreeBonuses() {
        let due = StreakMilestone.due(days: run(30, endingOn: today), frozen: [], ledger: [], today: today, in: tz)
        #expect(due.map(\.days) == [7, 14, 30])
        #expect(due.map(\.coins) == [50, 100, 250])
    }

    @Test func whatThisRunPaidIsNotDueAgain() {
        let ledger = [paid(7, on: day(-23)), paid(14, on: day(-16))]
        let due = StreakMilestone.due(days: run(30, endingOn: today), frozen: [], ledger: ledger, today: today, in: tz)
        #expect(due.map(\.days) == [30])
    }

    /// A real break starts a new run, which earns 7 again — that took seven real days.
    @Test func anEarlierRunsBonusDoesntCount() {
        let ledger = [paid(7, on: "2026-08-10")]
        let due = StreakMilestone.due(days: run(8, endingOn: today), frozen: [], ledger: ledger, today: today, in: tz)
        #expect(due.map(\.days) == [7])
    }

    @Test func noRunNothingDue() {
        #expect(StreakMilestone.due(days: [], frozen: [], ledger: [], today: today, in: tz) == [])
    }

    /// Run A of 25 paid 7 and 14; a gap; run B of 6 up to today. The freeze joins them into 31:
    /// 30 is due at once, and 7 / 14 stay paid.
    @Test func aFreezeJoiningTwoRunsPaysTheThresholdNeitherReached() {
        let gap = day(-6)
        let days = run(6, endingOn: today).union(run(25, endingOn: day(-7)))
        let ledger = [paid(7, on: day(-25)), paid(14, on: day(-18))]
        #expect(StreakMilestone.due(days: days, frozen: [], ledger: ledger, today: today, in: tz) == [])
        let due = StreakMilestone.due(days: days, frozen: [gap], ledger: ledger, today: today, in: tz)
        #expect(due.map(\.days) == [30])
        #expect(Streak.runStart(days: days, frozen: [gap], today: today, in: tz) == day(-31))
    }

    // MARK: settling

    private func completedQuests(_ ctx: ModelContext, on days: Set<String>) {
        for d in days {
            let q = DailyQuest()
            q.dayKey = d
            q.slot = .easy
            q.completedAt = Fixtures.date(d)
            q.points = 10
            ctx.insert(q)
        }
    }

    @Test func settleBooksOnceAndIsIdempotent() throws {
        let ctx = try Fixtures.context()
        completedQuests(ctx, on: run(7, endingOn: today))
        try ctx.save()

        let awards = try StreakMilestone.settle(ctx, today: today, in: tz, now: Fixtures.date(today))
        #expect(awards == [.init(days: 7, coins: 50)])
        let entry = try #require(try ctx.fetch(FetchDescriptor<LedgerEntry>()).first { $0.kind == "streak" })
        #expect(entry.points == 50)
        #expect(entry.dayKey == today)
        #expect(entry.note == "Streak 7")
        #expect(StreakMilestone.threshold(of: entry) == 7)
        #expect(try Economy.totalEarned(ctx) == 50)                   // it counts toward the level

        #expect(try StreakMilestone.settle(ctx, today: today, in: tz) == [])
        #expect(try ctx.fetch(FetchDescriptor<LedgerEntry>()).filter { $0.kind == "streak" }.count == 1)
    }

    /// The seventh day's completion pays the bonus itself — no separate step.
    @Test func completingTheSeventhDayPaysIt() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        completedQuests(ctx, on: run(6, endingOn: day(-1)))
        var rng = SeededRNG(seed: 3)
        try DayService.ensureToday(ctx, now: Fixtures.date(today), in: tz, rng: &rng)
        let q = try #require(try DayService.quests(on: today, in: ctx)
            .first { !$0.isTrivialGroup && !$0.isHiddenSlot && $0.slot != .epic })

        try Completion.complete(q, tier: .normal, in: ctx, now: Fixtures.date(today), timeZone: tz, rng: &rng)
        let bonus = try ctx.fetch(FetchDescriptor<LedgerEntry>()).filter { $0.kind == "streak" }
        #expect(bonus.map(\.points) == [50])
    }

    /// The epic isn't a streak day, so completing it settles nothing.
    @Test func theEpicDoesntSettle() throws {
        let ctx = try Fixtures.context()
        completedQuests(ctx, on: run(6, endingOn: day(-1)))
        let epic = DailyQuest()
        epic.slot = .epic
        epic.dayKey = day(-2)
        ctx.insert(epic)
        try ctx.save()
        var rng = SeededRNG(seed: 3)
        try Completion.complete(epic, tier: .normal, in: ctx, now: Fixtures.date(today), timeZone: tz, rng: &rng)
        #expect(try ctx.fetch(FetchDescriptor<LedgerEntry>()).filter { $0.kind == "streak" }.isEmpty)
    }
}
