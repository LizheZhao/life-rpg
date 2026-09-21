import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// Completing a routine: fixed points, the ledger, and the history the scheduler reads next.
struct RoutineCompletionTests {
    private let tz = Fixtures.tokyo
    private let saturday = "2026-09-19"

    private func setUp(kind: RecurrenceKind = .weekly, spec: String = "SAT",
                       base: Int = 50) throws -> (ModelContext, RoutineTask, RoutineOccurrence) {
        let ctx = try Fixtures.context()
        let r = RoutineTask()
        r.text = "Workout: weight training"; r.kind = kind; r.spec = spec; r.basePoints = base
        ctx.insert(r)
        let o = RoutineOccurrence(routine: r, dueDayKey: saturday, weekKey: "2026-W38")
        ctx.insert(o)
        try ctx.save()
        return (ctx, r, o)
    }

    // MARK: points — literals, not the formula

    @Test func routinePointsLiterals() {
        #expect(Scoring.routinePoints(basePoints: 50, tier: .normal, late: false) == 50)
        #expect(Scoring.routinePoints(basePoints: 20, tier: .veryLow, late: false) == 26)
        #expect(Scoring.routinePoints(basePoints: 25, tier: .low, late: false) == 33)     // 32.5
        #expect(Scoring.routinePoints(basePoints: 50, tier: .normal, late: true) == 25)
        #expect(Scoring.routinePoints(basePoints: 25, tier: .normal, late: true) == 13)   // 12.5
        #expect(Scoring.routinePoints(basePoints: 25, tier: .low, late: true) == 16)      // 16.25
        #expect(Scoring.routinePoints(basePoints: 50, tier: .high, late: false) == 50)
    }

    @Test func onTheDueDayPaysFullBase() throws {
        let (ctx, r, o) = try setUp()
        let now = Fixtures.date(saturday, hour: 20)
        let points = try Completion.completeRoutine(o, on: saturday, tier: .normal, in: ctx,
                                                    now: now, timeZone: tz)
        #expect(points == 50)
        #expect(o.completedDayKey == saturday)
        #expect(o.completedAt == now)
        #expect(o.awardedPoints == 50)
        #expect(r.lastCompletedDayKey == saturday)

        let ledger = try ctx.fetch(FetchDescriptor<LedgerEntry>())
        #expect(ledger.count == 1)
        #expect(ledger[0].kind == "routine")
        #expect(ledger[0].points == 50)
        #expect(ledger[0].refID == o.id)
        #expect(try Economy.balance(ctx) == 50)
    }

    @Test func lowTierPaysTheMultiplier() throws {
        let (ctx, _, o) = try setUp(base: 20)
        #expect(try Completion.completeRoutine(o, on: saturday, tier: .veryLow, in: ctx, timeZone: tz) == 26)
    }

    @Test func dayTwoAndThreeAreLateMakeUpsAtHalf() throws {
        let (ctx, r, o) = try setUp()
        #expect(try Completion.completeRoutine(o, on: "2026-09-21", tier: .normal, in: ctx, timeZone: tz) == 25)
        #expect(o.completedDayKey == "2026-09-21")
        #expect(r.lastCompletedDayKey == "2026-09-21")       // everyNDays counts from the real day
        #expect(try ctx.fetch(FetchDescriptor<LedgerEntry>())[0].dayKey == "2026-09-21")
    }

    @Test func dayFourAndEarlierThanDueAreRefused() throws {
        let (ctx, _, o) = try setUp()
        #expect(throws: Completion.Failure.outsideRound(dueDayKey: saturday, dayKey: "2026-09-22")) {
            try Completion.completeRoutine(o, on: "2026-09-22", tier: .normal, in: ctx, timeZone: tz)
        }
        #expect(throws: Completion.Failure.self) {
            try Completion.completeRoutine(o, on: "2026-09-18", tier: .normal, in: ctx, timeZone: tz)
        }
        #expect(try ctx.fetch(FetchDescriptor<LedgerEntry>()).isEmpty)
    }

    @Test func completingTwiceOrAfterSkipIsRefused() throws {
        let (ctx, _, o) = try setUp()
        try Completion.completeRoutine(o, on: saturday, tier: .normal, in: ctx, timeZone: tz)
        #expect(throws: Completion.Failure.alreadyCompleted) {
            try Completion.completeRoutine(o, on: saturday, tier: .normal, in: ctx, timeZone: tz)
        }

        let (ctx2, _, skipped) = try setUp()
        skipped.skipped = true
        #expect(throws: Completion.Failure.skipped) {
            try Completion.completeRoutine(skipped, on: saturday, tier: .normal, in: ctx2, timeZone: tz)
        }
    }

    // MARK: everyNWeeksOnWeekday anchor

    /// The cadence starts from the first completion: done in W38, so due W40, W42 … and not W39.
    @Test func firstCompletionSetsTheBiweeklyAnchor() throws {
        let (ctx, r, o) = try setUp(kind: .everyNWeeksOnWeekday, spec: "2:SAT")
        #expect(r.anchorWeekKey == nil)
        try Completion.completeRoutine(o, on: saturday, tier: .normal, in: ctx, timeZone: tz)
        #expect(r.anchorWeekKey == "2026-W38")

        let occurrences = try ctx.fetch(FetchDescriptor<RoutineOccurrence>())
        #expect(Schedule.dueRoutines([r], occurrences: occurrences, on: "2026-09-26", in: tz).isEmpty)
        #expect(Schedule.dueRoutines([r], occurrences: occurrences, on: "2026-10-03", in: tz).count == 1)
    }

    @Test func laterCompletionsKeepTheAnchor() throws {
        let (ctx, r, _) = try setUp(kind: .everyNWeeksOnWeekday, spec: "2:SAT")
        r.anchorWeekKey = "2026-W36"
        let later = RoutineOccurrence(routine: r, dueDayKey: "2026-10-03", weekKey: "2026-W40")
        ctx.insert(later)
        try Completion.completeRoutine(later, on: "2026-10-03", tier: .normal, in: ctx, timeZone: tz)
        #expect(r.anchorWeekKey == "2026-W36")
    }

    @Test func weeklyRoutinesNeverGetAnAnchor() throws {
        let (ctx, r, o) = try setUp()
        try Completion.completeRoutine(o, on: saturday, tier: .normal, in: ctx, timeZone: tz)
        #expect(r.anchorWeekKey == nil)
    }

    /// An `everyNDays` routine, end to end through `ensureToday`: due the first day, not again
    /// while it's open, next due N days after it was done.
    @Test func everyNDaysEndToEnd() throws {
        let ctx = try Fixtures.context()
        let r = RoutineTask(); r.text = "Water the plants"; r.kind = .everyNDays; r.spec = "3"
        ctx.insert(r)
        var rng = SeededRNG(seed: 1)
        func open(_ d: String) throws -> [RoutineOccurrence] {
            try DayService.ensureToday(ctx, now: Fixtures.date(d), in: tz, rng: &rng)
            return try DayService.occurrences(dueOn: d, in: ctx)
        }
        let first = try #require(try open("2026-09-14").first)
        #expect(try open("2026-09-15").isEmpty)
        try Completion.completeRoutine(first, on: "2026-09-15", tier: .normal, in: ctx, timeZone: tz)
        #expect(try open("2026-09-16").isEmpty)
        #expect(try open("2026-09-17").isEmpty)
        #expect(try open("2026-09-18").count == 1)       // 15 + 3
    }
}
