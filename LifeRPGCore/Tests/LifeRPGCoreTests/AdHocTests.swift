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
    /// routine's — no `routineID`, so it is never flexible and never moves `lastCompletedDayKey`.
    /// It always gates the clear, whatever the routine says: otherwise swapping a hard slot for a
    /// non-scoring check-in would be a free pass. Done, it **does** count toward the routine's
    /// weekly target (decided with the user): doing the routine is doing the routine.
    @Test func fromTheLibraryCountsTowardTheWeeklyTarget() throws {
        let (ctx, quests) = try generated()
        let r = routine(ctx, "Workout: weight training", flexible: true, countsForClear: false)
        let o = try AdHoc.replace(quests[0], with: .routine(r), in: ctx, timeZone: tz)
        #expect(o.textSnapshot == "Workout: weight training")
        #expect(o.basePoints == 30)
        #expect(o.routineID == nil)
        #expect(o.adHocSourceRoutineID == r.id)
        #expect(o.countsForClear)

        let all = try ctx.fetch(FetchDescriptor<RoutineOccurrence>())
        #expect(Schedule.dueRoutines([r], occurrences: all, on: sat, in: tz).count == 1)
        try Completion.completeRoutine(o, on: fri, tier: .normal, in: ctx, timeZone: tz)
        #expect(o.awardedPoints == 30)
        #expect(r.lastCompletedDayKey == nil)
        // The week's one session is done, so Saturday no longer asks for it.
        #expect(Schedule.dueRoutines([r], occurrences: all, on: sat, in: tz).isEmpty)
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

    // MARK: adding on top (decided with the user)

    /// Extra work: nothing replaced, nothing gated, nothing charged if left undone.
    @Test func addingReplacesNothingAndGatesNothing() throws {
        let (ctx, quests) = try generated()
        let o = try AdHoc.add(.custom(text: "Fix the bike", difficulty: .hard), on: fri, in: ctx, timeZone: tz)
        #expect(quests.allSatisfy { !$0.replaced })
        #expect(o.dueDayKey == fri)
        #expect(o.weekKey == "2026-W38")
        #expect(o.basePoints == 38)
        #expect(o.routineID == nil)
        #expect(o.replacesQuestID == nil)
        #expect(!o.countsForClear)

        var rng = SeededRNG(seed: 4)
        for quest in quests {
            quest.trivialDone = quest.trivialDone.map { _ in true }
            try Completion.complete(quest, tier: .normal, in: ctx, rng: &rng)
        }
        #expect(try DayService.hiddenUnlocked(on: fri, in: ctx))     // the added one is still open
    }

    @Test func anAddedRoutineUndoneCostsNothing() throws {
        let (ctx, _) = try generated()
        let o = try AdHoc.add(.custom(text: "x", difficulty: .medium), on: fri, in: ctx, timeZone: tz)
        for day in [fri, sat, sun] { try Overdue.settle(day, in: ctx, timeZone: tz) }
        #expect(try Economy.balance(ctx) == 0)
        #expect(o.skipped)                                           // its round still ends
    }

    @Test func anAddedRoutinePaysWhenDone() throws {
        let (ctx, _) = try generated()
        let r = routine(ctx, "Deep clean")
        let o = try AdHoc.add(.routine(r), on: fri, in: ctx, timeZone: tz)
        #expect(o.adHocSourceRoutineID == r.id)
        try Completion.completeRoutine(o, on: fri, tier: .normal, in: ctx, timeZone: tz)
        #expect(try Economy.balance(ctx) == 30)
        // Once on the page, it isn't offered again.
        #expect(!AdHoc.libraryCandidates([r], occurrences: try ctx.fetch(FetchDescriptor<RoutineOccurrence>()),
                                         on: fri).contains { $0.id == r.id })
        #expect(throws: AdHoc.Failure.alreadyOnToday) {
            try AdHoc.add(.routine(r), on: fri, in: ctx, timeZone: tz)
        }
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

    // MARK: replacing a routine

    private func scheduled(_ ctx: ModelContext, _ r: RoutineTask, due: String) -> RoutineOccurrence {
        let o = RoutineOccurrence(routine: r, dueDayKey: due, weekKey: DayKey.weekKey(of: due, in: tz)!)
        ctx.insert(o)
        return o
    }

    /// Free, but never for something lighter — that would be a cancel without the 200.
    @Test func aRoutineCanOnlyBeSwappedForSomethingAsHeavy() throws {
        let ctx = try Fixtures.context()
        let trash = routine(ctx, "Take out the trash")          // base 30 in this fixture
        let o = scheduled(ctx, trash, due: fri)
        #expect(AdHoc.customDifficulties(replacing: o) == [.hard])
        #expect(throws: AdHoc.Failure.tooLight(minimum: 30)) {
            try AdHoc.replaceRoutine(o, flexible: false, with: .custom(text: "x", difficulty: .medium),
                                     on: fri, in: ctx, timeZone: tz)
        }
        #expect(!o.skipped)

        let fresh = try AdHoc.replaceRoutine(o, flexible: false,
                                             with: .custom(text: "Deep-clean the oven", difficulty: .hard),
                                             on: fri, in: ctx, timeZone: tz)
        #expect(o.skipped && o.replacedByID == fresh.id)
        #expect(fresh.basePoints == 38 && fresh.dueDayKey == fri && fresh.countsForClear)
        #expect(fresh.routineID == nil)
        #expect(try ctx.fetch(FetchDescriptor<LedgerEntry>()).isEmpty)
        #expect(Schedule.backlog(try ctx.fetch(FetchDescriptor<RoutineOccurrence>())).isEmpty)
        #expect(DayRecord.status(of: o) == .replaced)
        #expect(throws: AdHoc.Failure.routineNotReplaceable) {
            try AdHoc.replaceRoutine(o, flexible: false, with: .custom(text: "y", difficulty: .hard),
                                     on: fri, in: ctx, timeZone: tz)
        }
    }

    /// An overdue fixed routine: the swap keeps the old due day, so the ladder carries on — the
    /// replacement pays the late half and is charged the next rung, not a fresh round. What was
    /// already charged stays, and the old one is never charged again.
    @Test func swappingAnOverdueRoutineKeepsItsLadder() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx, "Clean the apartment", spec: "FRI")
        let o = scheduled(ctx, r, due: fri)
        try Overdue.settle(fri, in: ctx, timeZone: tz)
        #expect(o.penaltyApplied == 15)

        let fresh = try AdHoc.replaceRoutine(o, flexible: false,
                                             with: .custom(text: "Deep-clean the bathroom", difficulty: .hard),
                                             on: sat, in: ctx, timeZone: tz)
        #expect(fresh.dueDayKey == fri)
        try Overdue.settle(sat, in: ctx, timeZone: tz)
        #expect(o.penaltyApplied == 15)                       // closed, never charged again
        #expect(fresh.penaltyApplied == 29)                   // round day 2: 75% of 38
        #expect(try Completion.completeRoutine(fresh, on: sun, tier: .normal, in: ctx, timeZone: tz) == 19)
    }

    /// A flexible session: the replacement is due today, and the swapped session drops out of the
    /// week's target rather than counting as a shortfall.
    @Test func swappingAFlexibleSessionDropsItFromTheWeek() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx, "Work on project", spec: "SAT,SUN", flexible: true)
        r.weeklyTarget = 2
        let a = scheduled(ctx, r, due: sat)
        let b = scheduled(ctx, r, due: sun)
        let fresh = try AdHoc.replaceRoutine(a, flexible: true,
                                             with: .custom(text: "Write the cover letter", difficulty: .hard),
                                             on: sun, in: ctx, timeZone: tz)
        #expect(fresh.dueDayKey == sun)
        try Completion.completeRoutine(b, on: sun, tier: .normal, in: ctx, timeZone: tz)
        try Completion.completeRoutine(fresh, on: sun, tier: .normal, in: ctx, timeZone: tz)
        try Overdue.settle(sun, in: ctx, timeZone: tz)
        #expect(try ctx.fetch(FetchDescriptor<LedgerEntry>()).filter { $0.kind == "penalty" }.isEmpty)
    }

    /// The replacement gates the hidden quest in the old one's place.
    @Test func theReplacementGatesTheClear() throws {
        let (ctx, _) = try generated()
        let r = routine(ctx, "Laundry", spec: "FRI")
        let o = scheduled(ctx, r, due: fri)
        let fresh = try AdHoc.replaceRoutine(o, flexible: false,
                                             with: .custom(text: "Iron everything", difficulty: .hard),
                                             on: fri, in: ctx, timeZone: tz)
        let marks = CalendarMarks.marks(quests: [], occurrences: [o, fresh])
        #expect(marks[fri]?.routinesCleared != true)
        fresh.completedDayKey = fri
        #expect(CalendarMarks.marks(quests: [], occurrences: [o, fresh])[fri]?.routinesCleared == true)
    }

    // MARK: finding what already exists

    /// Saturday's flexible session still open on Sunday is on the page, so the library leaves it
    /// out — `onPageOccurrence` is what lets the sheet show it (and mark it done) anyway.
    @Test func anOpenSessionFromEarlierInTheWeekIsFoundOnThePage() throws {
        let ctx = try Fixtures.context()
        let grocery = routine(ctx, "Grocery shopping and cleaning out the fridge", flexible: true)
        let other = routine(ctx, "Cat grooming", spec: "SUN")
        let sat = scheduled(ctx, grocery, due: self.sat)
        let all = try ctx.fetch(FetchDescriptor<RoutineOccurrence>())

        #expect(!AdHoc.libraryCandidates([grocery, other], occurrences: all, on: sun).contains { $0.id == grocery.id })
        #expect(AdHoc.onPageOccurrence(for: grocery, occurrences: all, on: sun)?.id == sat.id)
        #expect(AdHoc.onPageOccurrence(for: other, occurrences: all, on: sun) == nil)

        try Completion.completeRoutine(sat, on: sun, tier: .normal, in: ctx, timeZone: tz)
        // Done on an earlier due day: no longer on the page at all.
        #expect(AdHoc.onPageOccurrence(for: grocery, occurrences: all, on: sun) == nil)
    }

    @Test func similarRoutinesMatchWhatWasTyped() throws {
        let ctx = try Fixtures.context()
        let grocery = routine(ctx, "Grocery shopping and cleaning out the fridge")
        let project = routine(ctx, "Work on project")
        let study = routine(ctx, "学习 LeetCode")
        let all = [grocery, project, study]

        #expect(AdHoc.similarRoutines(to: "Grocery Shopping", in: all).map(\.id) == [grocery.id])
        #expect(AdHoc.similarRoutines(to: "went shop", in: all).map(\.id) == [grocery.id])   // "shop" ⊂ "shopping"
        #expect(AdHoc.similarRoutines(to: "project work", in: all).map(\.id) == [project.id])
        #expect(AdHoc.similarRoutines(to: "学习", in: all).map(\.id) == [study.id])
        #expect(AdHoc.similarRoutines(to: "Social time", in: all).isEmpty)
        #expect(AdHoc.similarRoutines(to: "the and", in: all).isEmpty)       // filler only
        project.isActive = false
        #expect(AdHoc.similarRoutines(to: "project", in: all).isEmpty)
    }
}
