import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// Completing a quest: the roll, the ledger entry, the cooldown write-back, and the fact that
/// none of it can be taken back.
struct CompletionTests {
    private let tz = Fixtures.tokyo
    private let friday = "2026-09-18"

    private func day(_ ctx: ModelContext, tier: Tier = .normal, seed: UInt64 = 1) throws -> [DailyQuest] {
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: seed)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz,
                                   inputs: DayInputs(tier: tier), rng: &rng)
        return try DayService.quests(on: friday, in: ctx).sorted { $0.textSnapshot < $1.textSnapshot }
    }

    @Test func completingWritesPointsLedgerAndCooldown() throws {
        let ctx = try Fixtures.context()
        let quest = try day(ctx).first { !$0.isTrivialGroup }!
        var rng = SeededRNG(seed: 2)
        let now = Fixtures.date(friday, hour: 21)
        let points = try Completion.complete(quest, tier: .normal, in: ctx, now: now, rng: &rng)

        #expect(quest.points == points)
        #expect(quest.completedAt == now)
        #expect(quest.slot.range.contains(points))

        let ledger = try ctx.fetch(FetchDescriptor<LedgerEntry>())
        #expect(ledger.count == 1)
        #expect(ledger[0].kind == "quest")
        #expect(ledger[0].points == points)
        #expect(ledger[0].dayKey == friday)
        #expect(ledger[0].refID == quest.id)
        #expect(try Economy.balance(ctx) == points)

        // Cooldown now counts from the completion day, not the draw day.
        let template = try Completion.templates(of: quest, in: ctx).first!
        #expect(template.lastCompletedDayKey == friday)
    }

    @Test func completingTwiceIsRefused() throws {
        let ctx = try Fixtures.context()
        let quest = try day(ctx).first { !$0.isTrivialGroup }!
        var rng = SeededRNG(seed: 2)
        try Completion.complete(quest, tier: .normal, in: ctx, rng: &rng)
        #expect(throws: Completion.Failure.alreadyCompleted) {
            try Completion.complete(quest, tier: .normal, in: ctx, rng: &rng)
        }
        #expect(try ctx.fetch(FetchDescriptor<LedgerEntry>()).count == 1)
    }

    /// The T group scores once, as a whole, and only when all three are ticked.
    @Test func trivialGroupScoresOnceAllThreeAreTicked() throws {
        let ctx = try Fixtures.context()
        let group = try day(ctx, tier: .veryLow, seed: 3).first(where: \.isTrivialGroup)!
        var rng = SeededRNG(seed: 4)

        #expect(throws: Completion.Failure.trivialGroupIncomplete(remaining: 3)) {
            try Completion.complete(group, tier: .normal, in: ctx, rng: &rng)
        }
        #expect(try Completion.tickTrivialItem(group, at: 0, tier: .normal, in: ctx, rng: &rng) == nil)
        #expect(try Completion.tickTrivialItem(group, at: 1, tier: .normal, in: ctx, rng: &rng) == nil)
        #expect(try ctx.fetch(FetchDescriptor<LedgerEntry>()).isEmpty)

        let points = try Completion.tickTrivialItem(group, at: 2, tier: .normal, in: ctx, rng: &rng)
        #expect(points == 12)
        #expect(group.completedAt != nil)
        #expect(try ctx.fetch(FetchDescriptor<LedgerEntry>()).count == 1)

        // All three templates start their own cooldown, not just one of them.
        let templates = try Completion.templates(of: group, in: ctx)
        #expect(templates.count == 3)
        #expect(templates.allSatisfy { $0.lastCompletedDayKey == friday })
    }

    @Test func tickingOutOfRangeIsRefused() throws {
        let ctx = try Fixtures.context()
        let group = try day(ctx, tier: .veryLow, seed: 3).first(where: \.isTrivialGroup)!
        var rng = SeededRNG(seed: 4)
        #expect(throws: Completion.Failure.indexOutOfRange) {
            try Completion.tickTrivialItem(group, at: 5, tier: .normal, in: ctx, rng: &rng)
        }
    }

    @Test func lowTierPaysTheEffortMultiplier() throws {
        let ctx = try Fixtures.context()
        let quest = try day(ctx, tier: .low, seed: 5).first { !$0.isTrivialGroup }!
        var rng = SeededRNG(seed: 6)
        var mirror = rng
        let points = try Completion.complete(quest, tier: .low, in: ctx, rng: &rng)
        let expected = Scoring.questPoints(slot: quest.slot, isTrivialGroup: false, isHidden: false,
                                           tier: .low, rng: &mirror)
        #expect(points == expected)
        #expect(points > quest.slot.range.lowerBound)
    }

    /// A completed day feeds the streak and the level straight out of the ledger.
    @Test func completionFeedsStreakAndLevel() throws {
        let ctx = try Fixtures.context()
        var rng = SeededRNG(seed: 7)
        for quest in try day(ctx, seed: 7) {
            quest.trivialDone = quest.trivialDone.map { _ in true }
            try Completion.complete(quest, tier: .normal, in: ctx, rng: &rng)
        }
        #expect(try Streak.current(ctx, today: friday, in: tz) == 1)
        let total = try Economy.totalEarned(ctx)
        #expect(total == (try Economy.balance(ctx)))
        #expect(Economy.level(totalEarned: total) >= 1)
    }
}
