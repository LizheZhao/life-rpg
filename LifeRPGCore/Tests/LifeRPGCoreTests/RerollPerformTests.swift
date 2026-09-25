import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// Performing a reroll: the old row is kept as `replaced(.rerolled)`, the new one carries the count.
struct RerollPerformTests {
    private let tz = Fixtures.tokyo
    private let friday = "2026-09-18"
    private let saturday = "2026-09-19"
    private let monday = "2026-09-21"
    private let wednesday = "2026-09-23"

    private func day(_ ctx: ModelContext, _ dayKey: String, fund: Int = 1000, epics: Int = 0) throws {
        Fixtures.stockLibrary(ctx)
        for i in 0..<epics { Fixtures.quest(ctx, "epic #\(i)", .epic) }
        var rng = SeededRNG(seed: 1)
        try DayService.ensureToday(ctx, now: Fixtures.date(dayKey), in: tz, rng: &rng)
        Economy.record(ctx, kind: .adjust, points: fund, dayKey: dayKey)
        try ctx.save()
    }

    private func slot(_ ctx: ModelContext, _ d: Difficulty, on dayKey: String) throws -> DailyQuest {
        try #require(try DayService.quests(on: dayKey, in: ctx)
            .first { $0.slot == d && !$0.replaced && !$0.isHiddenSlot })
    }

    private func reroll(_ q: DailyQuest, _ dayKey: String, _ ctx: ModelContext, seed: UInt64 = 7) throws -> DailyQuest {
        var rng = SeededRNG(seed: seed)
        return try Reroll.perform(q, on: dayKey, in: ctx, timeZone: tz,
                                  now: Fixtures.date(dayKey), rng: &rng)
    }

    @Test func theOldRowIsKeptAndTheNewOneCarriesTheCount() throws {
        let ctx = try Fixtures.context()
        try day(ctx, friday)
        let old = try slot(ctx, .easy, on: friday)

        let fresh = try reroll(old, friday, ctx)
        #expect(old.replaced)
        #expect(old.replacedReason == .rerolled)
        #expect(old.completedAt == nil)
        #expect(fresh.slot == .easy)
        #expect(fresh.dayKey == friday)
        #expect(fresh.rerollCount == 1)
        #expect(fresh.templateID != old.templateID)
        #expect(try DayService.quests(on: friday, in: ctx).count == 4)   // 3 slots + the swapped-away row

        let spend = try #require(try ctx.fetch(FetchDescriptor<LedgerEntry>()).first { $0.kind == "reroll" })
        #expect(spend.points == -10)
        #expect(spend.dayKey == friday)
        #expect(spend.refID == old.id)
    }

    /// `PLAN.md` §6: E goes 10 / 15 / 23 / 34 — accumulated on the slot through the new rows.
    @Test func escalationAccumulatesOnTheSlot() throws {
        let ctx = try Fixtures.context()
        try day(ctx, friday)
        var q = try slot(ctx, .easy, on: friday)
        var paid: [Int] = []
        for i in 0..<4 {
            let before = try Economy.balance(ctx)
            q = try reroll(q, friday, ctx, seed: UInt64(i))
            paid.append(before - (try Economy.balance(ctx)))
        }
        #expect(paid == [10, 15, 23, 34])
        #expect(q.rerollCount == 4)
    }

    /// And it resets daily: tomorrow's E is a new row starting at zero.
    @Test func escalationResetsTheNextDay() throws {
        let ctx = try Fixtures.context()
        try day(ctx, friday)
        _ = try reroll(try slot(ctx, .easy, on: friday), friday, ctx)
        var rng = SeededRNG(seed: 2)
        try DayService.ensureToday(ctx, now: Fixtures.date(saturday), in: tz, rng: &rng)
        #expect(Reroll.cost(for: try slot(ctx, .easy, on: saturday)) == 10)
    }

    /// Nothing the day already served comes back, so it runs dry rather than bouncing — and a
    /// reroll with nothing to draw charges nothing and changes nothing.
    @Test func neverDrawsBackWhatWasSwappedAwayAndRunsDryForFree() throws {
        let ctx = try Fixtures.context()
        try day(ctx, friday, fund: 100_000)
        var q = try slot(ctx, .hard, on: friday)
        var seen: Set<UUID> = [q.templateID!]
        // Six H in the stock library, one already on the page: five rerolls, then dry.
        for i in 0..<5 {
            q = try reroll(q, friday, ctx, seed: UInt64(i))
            #expect(!seen.contains(q.templateID!))
            seen.insert(q.templateID!)
        }
        let balance = try Economy.balance(ctx)
        #expect(throws: Purchase.Blocked.noCandidates) { try reroll(q, friday, ctx) }
        #expect(try Economy.balance(ctx) == balance)
        #expect(!q.replaced)
    }

    @Test func aRerolledAwayRowCannotBeCompletedOrRerolledAgain() throws {
        let ctx = try Fixtures.context()
        try day(ctx, friday)
        let old = try slot(ctx, .medium, on: friday)
        _ = try reroll(old, friday, ctx)
        var rng = SeededRNG(seed: 3)
        #expect(throws: Completion.Failure.replaced) {
            try Completion.complete(old, tier: .normal, in: ctx, rng: &rng)
        }
        #expect(Reroll.blocked(for: old, on: friday, balance: 1000) == .notAvailable)
    }

    /// Full clear, streak and the calendar skip the swapped-away row like any replaced one.
    @Test func theFullClearCountsOnlyTheReplacement() throws {
        let ctx = try Fixtures.context()
        try day(ctx, friday)
        _ = try reroll(try slot(ctx, .easy, on: friday), friday, ctx)
        var rng = SeededRNG(seed: 4)
        for q in try DayService.quests(on: friday, in: ctx) where !q.replaced {
            try Completion.complete(q, tier: .normal, in: ctx, now: Fixtures.date(friday), rng: &rng)
        }
        #expect(try DayService.hiddenUnlocked(on: friday, in: ctx))
        let quests = try ctx.fetch(FetchDescriptor<DailyQuest>())
        #expect(CalendarMarks.marks(quests: quests, occurrences: [])[friday]?.randomsDone == 3)
        #expect(Streak.completedDayKeys(quests) == [friday])
    }

    /// The day detail reads the swapped-away row off the same day.
    @Test func theDayRecordStillHasTheSwappedAwayRow() throws {
        let ctx = try Fixtures.context()
        try day(ctx, friday)
        let old = try slot(ctx, .easy, on: friday)
        _ = try reroll(old, friday, ctx)
        let record = try DayRecord.load(friday, in: ctx)
        #expect(record.quests.contains { $0.quest.id == old.id && $0.quest.replacedReason == .rerolled })
    }

    @Test func hiddenAndOtherDaysCannotBeRerolled() throws {
        let ctx = try Fixtures.context()
        try day(ctx, friday)
        let hidden = DailyQuest()
        hidden.dayKey = friday
        hidden.isHiddenSlot = true
        #expect(Reroll.blocked(for: hidden, on: friday, balance: 1000) == .notAvailable)
        #expect(Reroll.blocked(for: try slot(ctx, .easy, on: friday), on: saturday, balance: 1000) == .notAvailable)
    }

    @Test func theBalanceRuleHolds() throws {
        let ctx = try Fixtures.context()
        try day(ctx, friday, fund: 9)
        let q = try slot(ctx, .easy, on: friday)
        // 9 on top of the default nothing: can't afford 10.
        #expect(throws: Purchase.Blocked.tooExpensive(cost: 10, balance: 9)) { try reroll(q, friday, ctx) }
        Economy.record(ctx, kind: .adjust, points: 1, dayKey: friday)
        _ = try reroll(q, friday, ctx)
        #expect(try Economy.balance(ctx) == 0)
    }

    // MARK: epic

    /// Flat 80 every time, as often as you like until it is extended; each new epic keeps the
    /// old one's deadline and never repeats one already swapped away.
    @Test func theEpicRerollsForAFlatEightyAndKeepsItsDeadline() throws {
        let ctx = try Fixtures.context()
        try day(ctx, monday, epics: 3)
        var epic = try #require(try Epic.current(on: monday, in: ctx, timeZone: tz))
        var seen: Set<UUID> = [epic.templateID!]

        for i in 0..<2 {
            let before = try Economy.balance(ctx)
            epic = try reroll(epic, wednesday, ctx, seed: UInt64(i))
            #expect(before - (try Economy.balance(ctx)) == 80)
            #expect(!seen.contains(epic.templateID!))
            seen.insert(epic.templateID!)
            #expect(epic.dayKey == monday)
            #expect(Epic.lastDayKey(of: epic, in: tz) == "2026-09-27")
        }
        #expect(epic.rerollCount == 2)
        #expect(try Epic.current(on: wednesday, in: ctx, timeZone: tz)?.id == epic.id)
        let spends = try ctx.fetch(FetchDescriptor<LedgerEntry>()).filter { $0.kind == "reroll" }
        #expect(spends.allSatisfy { $0.dayKey == wednesday })
        // All three epics have been on the page this week: nothing left to swap to, nothing charged.
        #expect(throws: Purchase.Blocked.noCandidates) { try reroll(epic, wednesday, ctx) }
    }

    /// Decided with the user: once extended, the epic is kept — no more rerolls.
    @Test func anExtendedEpicCannotBeRerolled() throws {
        let ctx = try Fixtures.context()
        try day(ctx, monday, epics: 3)
        let epic = try #require(try Epic.current(on: monday, in: ctx, timeZone: tz))
        #expect(Reroll.blocked(for: epic, on: monday, balance: 1000) == nil)
        try Epic.extend(epic, on: monday, in: ctx, timeZone: tz)
        #expect(Reroll.blocked(for: epic, on: monday, balance: 1000) == .epicExtended)
    }

    /// With a single epic in the library there is nothing to swap to, so nothing is charged.
    @Test func aLoneEpicCannotBeRerolled() throws {
        let ctx = try Fixtures.context()
        try day(ctx, monday, epics: 1)
        let epic = try #require(try Epic.current(on: monday, in: ctx, timeZone: tz))
        #expect(throws: Purchase.Blocked.noCandidates) { try reroll(epic, monday, ctx) }
        #expect(!epic.replaced)
    }
}
