import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// Settling a day that has ended: the escalating overdue penalty and day-4 auto-skip for fixed
/// routines, and Sunday's single shortfall deduction for flexible ones (`PLAN.md` §4).
/// Sat 2026-09-19 / Sun 20 close W38; Mon 21 opens W39.
struct OverdueTests {
    private let tz = Fixtures.tokyo
    private let sat = "2026-09-19", sun = "2026-09-20", mon = "2026-09-21", tue = "2026-09-22"

    private func routine(_ ctx: ModelContext, _ text: String = "Clean the apartment",
                         spec: String = "SAT", base: Int = 50, target: Int = 1,
                         flexible: Bool = false, countsForClear: Bool = true) -> RoutineTask {
        let r = RoutineTask()
        r.text = text; r.spec = spec; r.basePoints = base; r.weeklyTarget = target
        r.flexibleWithinWeek = flexible; r.countsForClear = countsForClear
        ctx.insert(r)
        return r
    }

    @discardableResult
    private func occurrence(_ ctx: ModelContext, _ r: RoutineTask, due: String) -> RoutineOccurrence {
        let o = RoutineOccurrence(routine: r, dueDayKey: due, weekKey: DayKey.weekKey(of: due, in: tz)!)
        ctx.insert(o)
        return o
    }

    private func settle(_ ctx: ModelContext, _ days: String...) throws {
        for d in days { try Overdue.settle(d, in: ctx, timeZone: tz) }
        try ctx.save()
    }

    private func entries(_ ctx: ModelContext, _ kind: String) throws -> [LedgerEntry] {
        try ctx.fetch(FetchDescriptor<LedgerEntry>()).filter { $0.kind == kind }.sorted { $0.dayKey < $1.dayKey }
    }

    // MARK: rates — PLAN.md's literals

    @Test func penaltyLiterals() {
        #expect(Scoring.overduePenalty(basePoints: 50, roundDay: 1) == 25)
        #expect(Scoring.overduePenalty(basePoints: 50, roundDay: 2) == 38)     // 37.5
        #expect(Scoring.overduePenalty(basePoints: 50, roundDay: 3) == 50)
        #expect(Scoring.overduePenalty(basePoints: 5, roundDay: 1) == 3)       // 2.5
        #expect(Scoring.overduePenalty(basePoints: 5, roundDay: 2) == 4)       // 3.75
        #expect(Scoring.overduePenalty(basePoints: 15, roundDay: 1) == 8)      // 7.5
        #expect(Scoring.flexibleShortfallPenalty(basePoints: 30) == 15)
        #expect(Scoring.flexibleShortfallPenalty(basePoints: 25) == 13)        // 12.5
    }

    // MARK: fixed routines

    /// The worked example: base 50 → −25 / −38 / −50, −113 in all, then skipped on day 4.
    @Test func escalatesOverThreeDaysThenSkips() throws {
        let ctx = try Fixtures.context()
        let o = occurrence(ctx, routine(ctx), due: sat)

        try settle(ctx, sat)
        #expect(try entries(ctx, "penalty").map(\.points) == [-25])
        #expect(!o.skipped)
        try settle(ctx, sun)
        try settle(ctx, mon)
        #expect(try entries(ctx, "penalty").map(\.points) == [-25, -38, -50])
        #expect(try entries(ctx, "penalty").map(\.dayKey) == [sat, sun, mon])
        #expect(o.penaltyApplied == 113)
        #expect(o.skipped)
        #expect(o.completedDayKey == nil)

        let skip = try #require(try entries(ctx, "skip").first)
        #expect(skip.points == 0)
        #expect(skip.dayKey == tue)          // day 4
        #expect(skip.refID == o.id)
        #expect(try Economy.balance(ctx) == -113)

        try settle(ctx, tue)                  // nothing left to judge
        #expect(try entries(ctx, "penalty").count == 3)
        #expect(try entries(ctx, "skip").count == 1)
    }

    @Test func settlingTheSameDayTwiceDeductsOnce() throws {
        let ctx = try Fixtures.context()
        occurrence(ctx, routine(ctx), due: sat)
        try settle(ctx, sat, sat)
        #expect(try entries(ctx, "penalty").map(\.points) == [-25])
    }

    /// Made up on day 2: that day's deduction is not applied, day 1's stays, and the make-up pays half.
    @Test func lateMakeUpStopsFurtherDeductions() throws {
        let ctx = try Fixtures.context()
        let o = occurrence(ctx, routine(ctx), due: sat)
        try settle(ctx, sat)
        #expect(try Completion.completeRoutine(o, on: sun, tier: .normal, in: ctx, timeZone: tz) == 25)
        try settle(ctx, sun, mon)
        #expect(try entries(ctx, "penalty").map(\.points) == [-25])
        #expect(!o.skipped)
        #expect(try Economy.balance(ctx) == 0)
    }

    @Test func doneOnTheDueDayIsNeverPenalized() throws {
        let ctx = try Fixtures.context()
        let o = occurrence(ctx, routine(ctx), due: sat)
        try Completion.completeRoutine(o, on: sat, tier: .normal, in: ctx, timeZone: tz)
        try settle(ctx, sat, sun, mon)
        #expect(try entries(ctx, "penalty").isEmpty)
        #expect(try entries(ctx, "skip").isEmpty)
    }

    /// `PLAN.md` §4 "Non-scoring routines": not penalized, but the round still ends on day 4.
    @Test func nonScoringRoutinesAreSkippedButNotPenalized() throws {
        let ctx = try Fixtures.context()
        let o = occurrence(ctx, routine(ctx, countsForClear: false), due: sat)
        try settle(ctx, sat, sun, mon)
        #expect(try entries(ctx, "penalty").isEmpty)
        #expect(o.skipped)
    }

    /// Two routines overdue at once stack; there is no daily cap.
    @Test func noDailyCap() throws {
        let ctx = try Fixtures.context()
        occurrence(ctx, routine(ctx, "a", base: 50), due: sat)
        occurrence(ctx, routine(ctx, "b", base: 50), due: sat)
        try settle(ctx, sat)
        #expect(try Economy.balance(ctx) == -50)
    }

    // MARK: flexible routines

    @Test func flexibleIsNotPenalizedDaily() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx, "Workout: running", spec: "TUE", base: 25, flexible: true)
        let o = occurrence(ctx, r, due: "2026-09-15")
        try settle(ctx, "2026-09-15", "2026-09-16", "2026-09-17", "2026-09-18")
        #expect(try entries(ctx, "penalty").isEmpty)
        #expect(!o.skipped)                  // still open until Sunday
    }

    /// Weight training SAT,SUN, target 2, nothing done: one deduction on Sunday, 50% per miss.
    @Test func sundayChargesHalfBasePerShortfall() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx, "Workout: weight training", spec: "SAT,SUN", base: 30, target: 2, flexible: true)
        let a = occurrence(ctx, r, due: sat)
        let b = occurrence(ctx, r, due: sun)
        try settle(ctx, sat)
        #expect(try entries(ctx, "penalty").isEmpty)
        try settle(ctx, sun)
        #expect(try entries(ctx, "penalty").map(\.points) == [-15, -15])
        #expect(try entries(ctx, "penalty").allSatisfy { $0.dayKey == sun })
        #expect(a.skipped && b.skipped)
        #expect(try entries(ctx, "skip").allSatisfy { $0.dayKey == mon })
        #expect(try Economy.balance(ctx) == -30)

        try settle(ctx, sun)                 // idempotent
        #expect(try Economy.balance(ctx) == -30)
    }

    /// Saturday's session moved to Sunday: the Saturday occurrence is completed on Sunday at full
    /// pay, and only the one still missing is charged.
    @Test func movedWithinTheWeekPaysInFullAndCounts() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx, "Workout: weight training", spec: "SAT,SUN", base: 30, target: 2, flexible: true)
        let a = occurrence(ctx, r, due: sat)
        let b = occurrence(ctx, r, due: sun)
        try settle(ctx, sat)
        #expect(try Completion.completeRoutine(a, on: sun, tier: .normal, in: ctx, timeZone: tz) == 30)
        try settle(ctx, sun)
        #expect(try entries(ctx, "penalty").map(\.points) == [-15])
        #expect(try entries(ctx, "penalty").first?.refID == b.id)
        #expect(b.skipped && !a.skipped)
    }

    @Test func flexibleCanBeDoneAnyLaterDayOfItsWeekButNotAfter() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx, "Workout: running", spec: "TUE", base: 25, flexible: true)
        let o = occurrence(ctx, r, due: "2026-09-15")
        #expect(throws: Completion.Failure.self) {
            try Completion.completeRoutine(o, on: mon, tier: .normal, in: ctx, timeZone: tz)   // next week
        }
        #expect(try Completion.completeRoutine(o, on: sun, tier: .normal, in: ctx, timeZone: tz) == 25)
    }

    /// Target 2, but the app only saw Sunday (Saturday was never generated): judged against what
    /// actually came due, like a fixed routine on a day the app never opened.
    @Test func shortfallIsCappedByWhatCameDue() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx, "Work on project", spec: "SAT,SUN", base: 30, target: 2, flexible: true)
        occurrence(ctx, r, due: sun)
        try settle(ctx, sun)
        #expect(try Economy.balance(ctx) == -15)
    }

    /// Change bedsheets (first Saturday, flexible): a week it isn't due is not a shortfall.
    @Test func weeksWithNothingDueAreNotCharged() throws {
        let ctx = try Fixtures.context()
        routine(ctx, "Change bedsheets", spec: "1:SAT", base: 15, flexible: true)
            .kind = .nthWeekdayOfMonth
        try settle(ctx, sun)
        #expect(try entries(ctx, "penalty").isEmpty)
    }

    // MARK: end to end through ensureToday

    /// Generated Saturday, then not opened again until Tuesday: catch-up judges Sat, Sun and Mon.
    @Test func catchUpAppliesTheWholeLadder() throws {
        let ctx = try Fixtures.context()
        _ = routine(ctx)
        var rng = SeededRNG(seed: 1)
        try DayService.ensureToday(ctx, now: Fixtures.date(sat), in: tz, rng: &rng)
        #expect(try entries(ctx, "penalty").isEmpty)          // today is never judged
        try DayService.ensureToday(ctx, now: Fixtures.date(tue), in: tz, rng: &rng)
        #expect(try entries(ctx, "penalty").map(\.points) == [-25, -38, -50])
        let o = try #require(try DayService.occurrences(dueOn: sat, in: ctx).first)
        #expect(o.skipped)
    }

    // MARK: what the page lists

    @Test func overdueExcludesFlexibleAndBacklogListsSkipped() throws {
        let ctx = try Fixtures.context()
        let fixed = occurrence(ctx, routine(ctx, "fixed"), due: sat)
        let flex = routine(ctx, "flex", spec: "SAT,SUN", target: 2, flexible: true)
        let f = occurrence(ctx, flex, due: sat)
        let flexIDs: Set<UUID> = [flex.id]

        #expect(Schedule.overdue([fixed, f], flexible: flexIDs, on: sun, in: tz).map(\.textSnapshot) == ["fixed"])
        #expect(Schedule.openThisWeek([fixed, f], flexible: flexIDs, on: sun, in: tz).map(\.textSnapshot) == ["flex"])
        #expect(Schedule.openThisWeek([fixed, f], flexible: flexIDs, on: mon, in: tz).isEmpty)

        try settle(ctx, sat, sun, mon)
        #expect(Schedule.backlog([fixed, f]).map(\.textSnapshot) == ["fixed", "flex"])
    }
}
