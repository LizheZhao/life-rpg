import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// The debug-only undo. Its one real requirement is that it is a *whole* undo — a reopen that left
/// the ledger entries behind would hand out points for work the app now shows as not done.
struct DayResetTests {
    private let tz = Fixtures.tokyo
    private let friday = "2026-09-18"

    @Test func reopeningPutsTheBalanceBack() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 4)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz, rng: &rng)
        for quest in try DayService.quests(on: friday, in: ctx) {
            quest.trivialDone = quest.trivialDone.map { _ in true }
            try Completion.complete(quest, tier: .normal, in: ctx, rng: &rng)
        }
        #expect(try Economy.balance(ctx) > 0)

        try DayReset.reopen(ctx, dayKey: friday)
        #expect(try Economy.balance(ctx) == 0)
        #expect(try DayService.quests(on: friday, in: ctx).allSatisfy { $0.completedAt == nil })
        #expect(try DayService.quests(on: friday, in: ctx).allSatisfy { $0.points == nil })
    }

    /// The same quests come back, not new ones — that is the point of reopening rather than
    /// regenerating, when what you are testing is the payout for a particular difficulty.
    @Test func theSameQuestsComeBack() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 7)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz, rng: &rng)
        let before = try DayService.quests(on: friday, in: ctx).map(\.textSnapshot).sorted()
        for quest in try DayService.quests(on: friday, in: ctx) {
            quest.trivialDone = quest.trivialDone.map { _ in true }
            try Completion.complete(quest, tier: .normal, in: ctx, rng: &rng)
        }

        try DayReset.reopen(ctx, dayKey: friday)
        #expect(try DayService.quests(on: friday, in: ctx).map(\.textSnapshot).sorted() == before)
        #expect(try DayService.dailyContext(for: friday, in: ctx) != nil)
    }

    @Test func aTGroupsTicksAreClearedTogether() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 3)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz,
                                   inputs: DayInputs(tier: .veryLow), rng: &rng)
        let group = try #require(try DayService.quests(on: friday, in: ctx).first(where: \.isTrivialGroup))
        for i in group.trivialDone.indices {
            try Completion.tickTrivialItem(group, at: i, tier: .normal, in: ctx, rng: &rng)
        }
        #expect(group.completedAt != nil)

        try DayReset.reopen(ctx, dayKey: friday)
        #expect(group.trivialDone == [false, false, false])
        #expect(group.completedAt == nil)
    }

    /// Hidden is drawn once a day and the guard is the row existing, so reopening has to delete it
    /// — clearing its fields would leave the day permanently unable to reveal one again.
    @Test func theHiddenQuestIsRemovedSoItCanBeRevealedAgain() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 21)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz, rng: &rng)
        for quest in try DayService.quests(on: friday, in: ctx) {
            quest.trivialDone = quest.trivialDone.map { _ in true }
            try Completion.complete(quest, tier: .normal, in: ctx, rng: &rng)
        }
        #expect(try DayService.drawHidden(ctx, on: friday, in: tz, rng: &rng) != nil)

        let result = try DayReset.reopen(ctx, dayKey: friday)
        #expect(result.hiddenRemoved == 1)
        #expect(try DayService.quests(on: friday, in: ctx).allSatisfy { !$0.isHiddenSlot })
        #expect(try !DayService.hiddenUnlocked(on: friday, in: ctx))   // the day is open again
    }

    /// Another day's history must not be touched.
    @Test func yesterdayIsLeftAlone() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 5)
        try DayService.ensureToday(ctx, now: Fixtures.date("2026-09-17"), in: tz, rng: &rng)
        for quest in try DayService.quests(on: "2026-09-17", in: ctx) {
            quest.trivialDone = quest.trivialDone.map { _ in true }
            try Completion.complete(quest, tier: .normal, in: ctx, rng: &rng)
        }
        let earned = try Economy.balance(ctx)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz, rng: &rng)

        try DayReset.reopen(ctx, dayKey: friday)
        #expect(try Economy.balance(ctx) == earned)
        #expect(try DayService.quests(on: "2026-09-17", in: ctx).allSatisfy { $0.completedAt != nil })
    }
}
