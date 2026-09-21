import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// Doing a flexible routine earlier than its due day: Saturday's weight training done on Wednesday
/// is logged against the next occurrence still to come this week, which is created on the spot.
/// W38: Mon 2026-09-14 … Sun 20.
struct FlexibleAheadTests {
    private let tz = Fixtures.tokyo
    private let wed = "2026-09-16", thu = "2026-09-17", sat = "2026-09-19", sun = "2026-09-20"

    private func weights(_ ctx: ModelContext, flexible: Bool = true) -> RoutineTask {
        let r = RoutineTask()
        r.text = "Workout: weight training"; r.spec = "SAT,SUN"; r.weeklyTarget = 2
        r.basePoints = 30; r.flexibleWithinWeek = flexible
        ctx.insert(r)
        return r
    }

    private func occurrences(_ ctx: ModelContext) throws -> [RoutineOccurrence] {
        try ctx.fetch(FetchDescriptor<RoutineOccurrence>()).sorted { $0.dueDayKey < $1.dueDayKey }
    }

    private func candidates(_ ctx: ModelContext, on day: String) throws -> [Schedule.Ahead] {
        Schedule.aheadCandidates(try ctx.fetch(FetchDescriptor<RoutineTask>()),
                                 occurrences: try occurrences(ctx), on: day, in: tz)
    }

    @Test func offeredWithTheNextDueDay() throws {
        let ctx = try Fixtures.context()
        let r = weights(ctx)
        let c = try #require(try candidates(ctx, on: wed).first)
        #expect(c.routine.id == r.id)
        #expect(c.nextDueDayKey == sat)
        #expect(c.doneThisWeek == 0)
    }

    @Test func fixedRoutinesAreNeverOffered() throws {
        let ctx = try Fixtures.context()
        _ = weights(ctx, flexible: false)
        #expect(try candidates(ctx, on: wed).isEmpty)
    }

    @Test func completingAheadCreatesTheFutureOccurrenceDone() throws {
        let ctx = try Fixtures.context()
        let r = weights(ctx)
        let points = try Completion.completeAhead(r, on: wed, tier: .normal, in: ctx, timeZone: tz)
        #expect(points == 30)                                   // full, never "late"

        let o = try #require(try occurrences(ctx).first)
        #expect(o.dueDayKey == sat)
        #expect(o.weekKey == "2026-W38")
        #expect(o.completedDayKey == wed)
        #expect(o.awardedPoints == 30)
        #expect(r.lastCompletedDayKey == wed)
        #expect(try Economy.balance(ctx) == 30)

        // Next time it offers Sunday; after that the week is full.
        #expect(try candidates(ctx, on: thu).first?.nextDueDayKey == sun)
        #expect(try candidates(ctx, on: thu).first?.doneThisWeek == 1)
        try Completion.completeAhead(r, on: thu, tier: .veryLow, in: ctx, timeZone: tz)
        #expect(try candidates(ctx, on: thu).isEmpty)
        #expect(try Economy.balance(ctx) == 30 + 39)            // 30 × 1.3
        #expect(Schedule.doneAhead(try occurrences(ctx), on: thu).count == 1)
    }

    /// Saturday arrives: the occurrence already exists, so it is not created twice and it no
    /// longer counts toward Saturday's load.
    @Test func dueDayDoesNotDuplicateAndLoadDrops() throws {
        let ctx = try Fixtures.context()
        let r = weights(ctx)
        let other = RoutineTask(); other.text = "Clean"; other.spec = "SAT"
        ctx.insert(other)
        try Completion.completeAhead(r, on: wed, tier: .normal, in: ctx, timeZone: tz)

        var rng = SeededRNG(seed: 1)
        let day = try DayService.ensureToday(ctx, now: Fixtures.date(sat), in: tz, rng: &rng)
        #expect(day.routineLoad == 1)                           // only "Clean"
        let onSat = try DayService.occurrences(dueOn: sat, in: ctx)
        #expect(onSat.count == 2)
        #expect(onSat.filter { $0.routineID == r.id }.count == 1)
    }

    /// Done twice ahead: Sunday's settlement finds the target met.
    @Test func aheadCompletionsCountAtSettlement() throws {
        let ctx = try Fixtures.context()
        let r = weights(ctx)
        try Completion.completeAhead(r, on: wed, tier: .normal, in: ctx, timeZone: tz)
        try Completion.completeAhead(r, on: thu, tier: .normal, in: ctx, timeZone: tz)
        try Overdue.settle(sun, in: ctx, timeZone: tz)
        #expect(try ctx.fetch(FetchDescriptor<LedgerEntry>()).allSatisfy { $0.kind == "routine" })
    }

    /// Once one is open on the page (due today or earlier this week) that is what you tap; the
    /// ahead list doesn't offer a second way to do the same thing.
    @Test func notOfferedWhileOneIsOpen() throws {
        let ctx = try Fixtures.context()
        let r = weights(ctx)
        ctx.insert(RoutineOccurrence(routine: r, dueDayKey: sat, weekKey: "2026-W38"))
        #expect(try candidates(ctx, on: sat).isEmpty)
        #expect(try candidates(ctx, on: sun).isEmpty)
    }

    /// Nothing left to come due this week: nothing to log ahead against.
    @Test func notOfferedAfterTheLastDueDay() throws {
        let ctx = try Fixtures.context()
        let r = RoutineTask(); r.text = "Workout: running"; r.spec = "TUE"
        r.flexibleWithinWeek = true; r.basePoints = 25
        ctx.insert(r)
        #expect(try candidates(ctx, on: wed).isEmpty)
        #expect(throws: Completion.Failure.nothingAhead) {
            try Completion.completeAhead(r, on: wed, tier: .normal, in: ctx, timeZone: tz)
        }
        #expect(try ctx.fetch(FetchDescriptor<LedgerEntry>()).isEmpty)
    }

    /// The biweekly cadence starts from the first completion, however it was done — ahead included.
    @Test func aheadFirstCompletionSetsTheBiweeklyAnchor() throws {
        let ctx = try Fixtures.context()
        let r = RoutineTask(); r.text = "Deep clean"; r.kind = .everyNWeeksOnWeekday; r.spec = "2:SAT"
        r.flexibleWithinWeek = true; r.basePoints = 20
        ctx.insert(r)
        try Completion.completeAhead(r, on: wed, tier: .normal, in: ctx, timeZone: tz)
        #expect(r.anchorWeekKey == "2026-W38")
        // Next Saturday (W39) is the off week; the one after (W40) is due.
        #expect(Schedule.dueRoutines([r], occurrences: try occurrences(ctx), on: "2026-09-26", in: tz).isEmpty)
        #expect(Schedule.dueRoutines([r], occurrences: try occurrences(ctx), on: "2026-10-03", in: tz).count == 1)
    }

    /// Target met for the week: the remaining scheduled days don't come due — no load, no gate.
    @Test func targetMetStopsTheRestOfTheWeek() throws {
        let ctx = try Fixtures.context()
        let r = RoutineTask(); r.text = "Study"; r.spec = "MON,WED,FRI"; r.weeklyTarget = 2
        r.flexibleWithinWeek = true; r.basePoints = 20
        ctx.insert(r)
        let mon = "2026-09-14", fri = "2026-09-18"
        for day in [mon, wed] {
            let o = RoutineOccurrence(routine: r, dueDayKey: day, weekKey: "2026-W38")
            o.completedDayKey = day
            ctx.insert(o)
        }
        #expect(Schedule.dueRoutines([r], occurrences: try occurrences(ctx), on: fri, in: tz).isEmpty)
        // A new week starts the count over.
        #expect(Schedule.dueRoutines([r], occurrences: try occurrences(ctx), on: "2026-09-21", in: tz).count == 1)
    }

    /// Fixed routines have no weekly target to meet: every scheduled day is due.
    @Test func fixedRoutinesIgnoreTheTarget() throws {
        let ctx = try Fixtures.context()
        let r = RoutineTask(); r.text = "Take out the trash"; r.spec = "WED,SAT"; r.weeklyTarget = 1
        ctx.insert(r)
        let o = RoutineOccurrence(routine: r, dueDayKey: wed, weekKey: "2026-W38")
        o.completedDayKey = wed
        ctx.insert(o)
        #expect(Schedule.dueRoutines([r], occurrences: try occurrences(ctx), on: sat, in: tz).count == 1)
    }

    @Test func inactiveRoutinesAreNotOffered() throws {
        let ctx = try Fixtures.context()
        weights(ctx).isActive = false
        #expect(try candidates(ctx, on: wed).isEmpty)
    }
}
