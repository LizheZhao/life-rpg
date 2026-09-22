import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// An ad-hoc routine replacing a random slot (`PLAN.md` §3): the slot is marked `replaced` and
/// drops out of full-clear; the routine is due today, gates the hidden quest, and loses points on
/// the fixed ladder if not done. Free to do, and independent of the routine library's scheduling.
/// Friday 2026-09-18.
struct AdHocTests {
    private let tz = Fixtures.tokyo
    private let fri = "2026-09-18", sat = "2026-09-19", sun = "2026-09-20", mon = "2026-09-21"

    private func generated() throws -> (ModelContext, [DailyQuest]) {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 21)
        try DayService.ensureToday(ctx, now: Fixtures.date(fri), in: tz, rng: &rng)
        return (ctx, try DayService.quests(on: fri, in: ctx).sorted { $0.textSnapshot < $1.textSnapshot })
    }

    private func routine(_ ctx: ModelContext, _ text: String, spec: String = "SAT",
                         flexible: Bool = false, countsForClear: Bool = true) -> RoutineTask {
        let r = RoutineTask()
        r.text = text; r.spec = spec; r.basePoints = 30
        r.flexibleWithinWeek = flexible; r.countsForClear = countsForClear
        ctx.insert(r)
        return r
    }

    // MARK: points

    /// Midpoint of the difficulty's random range, rounded: 5–15, 12–30, 25–50.
    @Test func customBasePointsAreTheRangeMidpoint() {
        #expect(AdHoc.basePoints(for: .easy) == 10)
        #expect(AdHoc.basePoints(for: .medium) == 21)
        #expect(AdHoc.basePoints(for: .hard) == 38)
        #expect(AdHoc.basePoints(for: .trivial) == nil)
        #expect(AdHoc.basePoints(for: .epic) == nil)
    }

    // MARK: replacing

    @Test func customReplacesASlotForFree() throws {
        let (ctx, quests) = try generated()
        let slot = try #require(quests.first)
        let o = try AdHoc.replace(slot, with: .custom(text: "  Call the landlord ", difficulty: .medium),
                                  in: ctx, timeZone: tz)
        #expect(slot.replaced)
        #expect(o.textSnapshot == "Call the landlord")
        #expect(o.basePoints == 21)
        #expect(o.dueDayKey == fri)
        #expect(o.weekKey == "2026-W38")
        #expect(o.routineID == nil)                              // independent of any schedule
        #expect(o.replacesQuestID == slot.id)
        #expect(o.adHocSourceRoutineID == nil)
        #expect(o.countsForClear)
        #expect(try ctx.fetch(FetchDescriptor<LedgerEntry>()).isEmpty)   // the swap itself is free
    }

    /// From the library: text and points come from the routine, but the occurrence is not the
    /// routine's — no `routineID`, so it is never flexible, never counts toward the weekly target
    /// and never moves `lastCompletedDayKey`. It always gates the clear, whatever the routine says:
    /// otherwise swapping a hard slot for a non-scoring check-in would be a free pass.
    @Test func fromTheLibraryIsIndependentOfTheRoutine() throws {
        let (ctx, quests) = try generated()
        let r = routine(ctx, "Workout: weight training", flexible: true, countsForClear: false)
        let o = try AdHoc.replace(quests[0], with: .routine(r), in: ctx, timeZone: tz)
        #expect(o.textSnapshot == "Workout: weight training")
        #expect(o.basePoints == 30)
        #expect(o.routineID == nil)
        #expect(o.adHocSourceRoutineID == r.id)
        #expect(o.countsForClear)

        try Completion.completeRoutine(o, on: fri, tier: .normal, in: ctx, timeZone: tz)
        #expect(o.awardedPoints == 30)
        #expect(r.lastCompletedDayKey == nil)
        // Saturday still asks for the routine's own session: the ad-hoc one didn't count.
        let all = try ctx.fetch(FetchDescriptor<RoutineOccurrence>())
        #expect(Schedule.dueRoutines([r], occurrences: all, on: sat, in: tz).count == 1)
    }

    @Test func onlyAnOpenRandomSlotOfThatDayCanBeReplaced() throws {
        let (ctx, quests) = try generated()
        var rng = SeededRNG(seed: 3)
        let done = quests[0]
        done.trivialDone = done.trivialDone.map { _ in true }
        try Completion.complete(done, tier: .normal, in: ctx, rng: &rng)
        let custom = AdHoc.Source.custom(text: "x", difficulty: .easy)

        #expect(throws: AdHoc.Failure.notReplaceable) {
            try AdHoc.replace(done, with: custom, in: ctx, timeZone: tz)
        }
        try AdHoc.replace(quests[1], with: custom, in: ctx, timeZone: tz)
        #expect(throws: AdHoc.Failure.notReplaceable) {           // already replaced
            try AdHoc.replace(quests[1], with: custom, in: ctx, timeZone: tz)
        }
        let hidden = DailyQuest(); hidden.dayKey = fri; hidden.isHiddenSlot = true
        ctx.insert(hidden)
        #expect(throws: AdHoc.Failure.notReplaceable) {
            try AdHoc.replace(hidden, with: custom, in: ctx, timeZone: tz)
        }
        #expect(Set(AdHoc.replaceableSlots(try DayService.quests(on: fri, in: ctx), on: fri).map(\.id))
                == Set(quests.dropFirst(2).map(\.id)))
    }

    @Test func customNeedsTextAndAScoringDifficulty() throws {
        let (ctx, quests) = try generated()
        #expect(throws: AdHoc.Failure.emptyText) {
            try AdHoc.replace(quests[0], with: .custom(text: "   ", difficulty: .easy), in: ctx, timeZone: tz)
        }
        #expect(throws: AdHoc.Failure.noBasePoints) {
            try AdHoc.replace(quests[0], with: .custom(text: "x", difficulty: .trivial), in: ctx, timeZone: tz)
        }
        #expect(!quests[0].replaced)
        #expect(try ctx.fetch(FetchDescriptor<RoutineOccurrence>()).isEmpty)
    }

    /// A replaced slot is gone: it can't be completed afterwards for its points on top.
    @Test func aReplacedSlotCannotBeCompleted() throws {
        let (ctx, quests) = try generated()
        var rng = SeededRNG(seed: 3)
        let slot = quests[0]
        try AdHoc.replace(slot, with: .custom(text: "x", difficulty: .easy), in: ctx, timeZone: tz)
        slot.trivialDone = slot.trivialDone.map { _ in false }
        #expect(throws: Completion.Failure.replaced) {
            try Completion.complete(slot, tier: .normal, in: ctx, rng: &rng)
        }
        if slot.isTrivialGroup {
            #expect(throws: Completion.Failure.replaced) {
                try Completion.tickTrivialItem(slot, at: 0, tier: .normal, in: ctx, rng: &rng)
            }
        }
        #expect(try ctx.fetch(FetchDescriptor<LedgerEntry>()).isEmpty)
    }

    // MARK: the day

    @Test func theAdHocRoutineGatesHiddenInsteadOfTheSlot() throws {
        let (ctx, quests) = try generated()
        var rng = SeededRNG(seed: 3)
        let o = try AdHoc.replace(quests[0], with: .custom(text: "x", difficulty: .easy), in: ctx, timeZone: tz)
        for quest in quests.dropFirst() {
            quest.trivialDone = quest.trivialDone.map { _ in true }
            try Completion.complete(quest, tier: .normal, in: ctx, rng: &rng)
        }
        #expect(try !DayService.hiddenUnlocked(on: fri, in: ctx))
        try Completion.completeRoutine(o, on: fri, tier: .normal, in: ctx, timeZone: tz)
        #expect(try DayService.hiddenUnlocked(on: fri, in: ctx))
    }

    /// Not done: the fixed ladder on its base, 21 → −11 / −16 / −21, then skipped on day 4.
    @Test func undoneItLosesPointsOnTheFixedLadder() throws {
        let (ctx, quests) = try generated()
        let o = try AdHoc.replace(quests[0], with: .custom(text: "x", difficulty: .medium), in: ctx, timeZone: tz)
        try Overdue.settle(fri, in: ctx, timeZone: tz)
        #expect(try Economy.balance(ctx) == -11)
        try Overdue.settle(sat, in: ctx, timeZone: tz)
        try Overdue.settle(sun, in: ctx, timeZone: tz)
        #expect(try Economy.balance(ctx) == -11 - 16 - 21)
        #expect(o.skipped)
        #expect(try ctx.fetch(FetchDescriptor<LedgerEntry>()).contains { $0.kind == "skip" && $0.dayKey == mon })
    }

    // MARK: the library tab

    /// Active routines not already on today's page — neither scheduled today nor already added.
    @Test func libraryCandidates() throws {
        let (ctx, quests) = try generated()
        let free = routine(ctx, "B free")
        let inactive = routine(ctx, "C inactive"); inactive.isActive = false
        let scheduled = routine(ctx, "D scheduled")
        ctx.insert(RoutineOccurrence(routine: scheduled, dueDayKey: fri, weekKey: "2026-W38"))
        let added = routine(ctx, "A added")
        try AdHoc.replace(quests[0], with: .routine(added), in: ctx, timeZone: tz)
        // Still open from Wednesday: pinned on the page as overdue, so it is on the page too.
        let overdue = routine(ctx, "E overdue")
        ctx.insert(RoutineOccurrence(routine: overdue, dueDayKey: "2026-09-16", weekKey: "2026-W38"))
        // Finished or given up earlier: nothing of theirs is on today's page.
        let doneEarlier = routine(ctx, "F done earlier")
        let d = RoutineOccurrence(routine: doneEarlier, dueDayKey: "2026-09-16", weekKey: "2026-W38")
        d.completedDayKey = "2026-09-16"
        ctx.insert(d)
        let skippedEarlier = routine(ctx, "G skipped earlier")
        let s = RoutineOccurrence(routine: skippedEarlier, dueDayKey: "2026-09-11", weekKey: "2026-W37")
        s.skipped = true
        ctx.insert(s)

        let all = try ctx.fetch(FetchDescriptor<RoutineOccurrence>())
        let routines = try ctx.fetch(FetchDescriptor<RoutineTask>())
        #expect(AdHoc.libraryCandidates(routines, occurrences: all, on: fri).map(\.id)
                == [free.id, doneEarlier.id, skippedEarlier.id])
        #expect(throws: AdHoc.Failure.alreadyOnToday) {
            try AdHoc.replace(quests[1], with: .routine(overdue), in: ctx, timeZone: tz)
        }
        #expect(throws: AdHoc.Failure.alreadyOnToday) {
            try AdHoc.replace(quests[1], with: .routine(added), in: ctx, timeZone: tz)
        }
    }

    @Test func exportCarriesTheLink() throws {
        let (ctx, quests) = try generated()
        let r = routine(ctx, "Clean")
        try AdHoc.replace(quests[0], with: .routine(r), in: ctx, timeZone: tz)
        let o = try #require(try JSONExport.snapshot(ctx).routineOccurrences.first)
        #expect(o.replacesQuestID == quests[0].id)
        #expect(o.adHocSourceRoutineID == r.id)
    }
}
