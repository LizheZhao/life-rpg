import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// Which days a routine comes due on. September 2026 starts on a Tuesday: its Saturdays are the
/// 5th, 12th, 19th and 26th, and W38 runs Mon 14 … Sun 20.
struct ScheduleTests {
    private let tz = Fixtures.tokyo

    private func due(_ spec: FrequencySpec, _ dayKey: String,
                     _ history: Schedule.History = Schedule.History()) -> Bool {
        Schedule.isDue(spec, on: dayKey, history: history, in: tz)
    }

    // MARK: weekly

    @Test func weeklyIsDueOnItsWeekdaysOnly() {
        let spec = FrequencySpec.weekly([.wednesday, .saturday])
        #expect(due(spec, "2026-09-16"))      // Wed
        #expect(due(spec, "2026-09-19"))      // Sat
        #expect(!due(spec, "2026-09-17"))     // Thu
        #expect(!due(spec, "2026-09-20"))     // Sun
    }

    // MARK: monthly

    @Test func monthlyIsDueOnThatDay() {
        #expect(due(.monthly(day: 15), "2026-09-15"))
        #expect(!due(.monthly(day: 15), "2026-09-14"))
        #expect(!due(.monthly(day: 15), "2026-09-16"))
    }

    @Test func monthlyFallsBackToTheLastDayOfAShortMonth() {
        #expect(due(.monthly(day: 31), "2026-09-30"))
        #expect(!due(.monthly(day: 31), "2026-09-29"))
        #expect(due(.monthly(day: 31), "2026-10-31"))
        #expect(!due(.monthly(day: 31), "2026-10-30"))
        #expect(due(.monthly(day: 30), "2026-02-28"))     // 2026 is not a leap year
        #expect(!due(.monthly(day: 29), "2028-02-28"))    // 2028 is
        #expect(due(.monthly(day: 29), "2028-02-29"))
    }

    // MARK: nthWeekdayOfMonth

    @Test func firstSaturday() {
        let spec = FrequencySpec.nthWeekdayOfMonth(n: 1, weekday: .saturday)
        #expect(due(spec, "2026-09-05"))
        #expect(!due(spec, "2026-09-12"))
        #expect(!due(spec, "2026-09-06"))     // first Sunday, wrong weekday
        #expect(due(spec, "2026-10-03"))
    }

    @Test func lastSaturday() {
        let spec = FrequencySpec.nthWeekdayOfMonth(n: -1, weekday: .saturday)
        #expect(due(spec, "2026-09-26"))
        #expect(!due(spec, "2026-09-19"))
        #expect(due(spec, "2026-10-31"))      // a month with five Saturdays: the fifth
        #expect(!due(spec, "2026-10-24"))
        #expect(due(spec, "2026-02-28"))      // the month's very last day
    }

    @Test func fourthSaturdayIsNotTheLastWhenThereAreFive() {
        let spec = FrequencySpec.nthWeekdayOfMonth(n: 4, weekday: .saturday)
        #expect(due(spec, "2026-10-24"))
        #expect(!due(spec, "2026-10-31"))
    }

    // MARK: everyNDays

    @Test func everyNDaysNeverCompletedIsDueRightAway() {
        #expect(due(.everyNDays(3), "2026-09-17"))
    }

    @Test func everyNDaysCountsFromTheLastCompletion() {
        let h = Schedule.History(lastCompletedDayKey: "2026-09-14",
                                 latestDueDayKey: "2026-09-14", latestCompleted: true)
        #expect(!due(.everyNDays(3), "2026-09-15", h))
        #expect(!due(.everyNDays(3), "2026-09-16", h))
        #expect(due(.everyNDays(3), "2026-09-17", h))
        #expect(due(.everyNDays(3), "2026-09-18", h))     // not generated on the 17th: still due
    }

    /// A late completion moves the count: done on day 3 of the round, the next one is 3 days later.
    @Test func everyNDaysCountsFromALateCompletion() {
        let h = Schedule.History(lastCompletedDayKey: "2026-09-19",
                                 latestDueDayKey: "2026-09-17", latestCompleted: true)
        #expect(!due(.everyNDays(3), "2026-09-21", h))
        #expect(due(.everyNDays(3), "2026-09-22", h))
    }

    /// Due the 17th and never done: it stays open on days 2–3, is skipped on day 4 (the 20th), and
    /// the next round is counted from the skip — no new occurrence every day it stays undone.
    @Test func everyNDaysSkippedRoundRestartsFromTheSkipDay() {
        let h = Schedule.History(lastCompletedDayKey: "2026-09-14",
                                 latestDueDayKey: "2026-09-17", latestCompleted: false)
        #expect(!due(.everyNDays(3), "2026-09-18", h))     // round still open
        #expect(!due(.everyNDays(3), "2026-09-19", h))
        #expect(!due(.everyNDays(3), "2026-09-20", h))     // day 4: skipped, count restarts
        #expect(!due(.everyNDays(3), "2026-09-22", h))
        #expect(due(.everyNDays(3), "2026-09-23", h))
    }

    @Test func everyNDaysNeverCompletedAndSkippedIsNotChasedDaily() {
        let h = Schedule.History(latestDueDayKey: "2026-09-17", latestCompleted: false)
        #expect(!due(.everyNDays(2), "2026-09-20", h))
        #expect(!due(.everyNDays(2), "2026-09-21", h))
        #expect(due(.everyNDays(2), "2026-09-22", h))
    }

    // MARK: everyNWeeksOnWeekday

    /// Before the first completion there is no anchor, so it comes due every week.
    @Test func everyNWeeksWithoutAnchorIsDueEveryWeek() {
        let spec = FrequencySpec.everyNWeeksOnWeekday(n: 2, weekday: .saturday)
        #expect(due(spec, "2026-09-12"))
        #expect(due(spec, "2026-09-19"))
        #expect(due(spec, "2026-09-26"))
        #expect(!due(spec, "2026-09-20"))
    }

    @Test func everyNWeeksCountsFromTheAnchorWeek() {
        let spec = FrequencySpec.everyNWeeksOnWeekday(n: 2, weekday: .saturday)
        let h = Schedule.History(anchorWeekKey: "2026-W38")
        #expect(due(spec, "2026-09-19", h))       // W38
        #expect(!due(spec, "2026-09-26", h))      // W39
        #expect(due(spec, "2026-10-03", h))       // W40
        #expect(!due(spec, "2026-09-18", h))      // W38, wrong weekday
    }

    /// 2026 has 53 ISO weeks, so W52 → W01 is two weeks, not one.
    @Test func everyNWeeksAcrossTheYearBoundary() {
        let spec = FrequencySpec.everyNWeeksOnWeekday(n: 2, weekday: .saturday)
        let h = Schedule.History(anchorWeekKey: "2026-W52")
        #expect(due(spec, "2026-12-26", h))       // 2026-W52
        #expect(!due(spec, "2027-01-02", h))      // 2026-W53
        #expect(due(spec, "2027-01-09", h))       // 2027-W01
    }

    @Test func mondayOfWeek() {
        #expect(DayKey.monday(ofWeek: "2026-W38", in: tz) == "2026-09-14")
        #expect(DayKey.monday(ofWeek: "2026-W53", in: tz) == "2026-12-28")
        #expect(DayKey.monday(ofWeek: "2027-W01", in: tz) == "2027-01-04")
        #expect(DayKey.monday(ofWeek: "2025-W53", in: tz) == nil)       // 2025 has 52 weeks
        #expect(DayKey.monday(ofWeek: "garbage", in: tz) == nil)
        #expect(DayKey.monday(of: "2026-09-20", in: tz) == "2026-09-14")  // Sunday → its Monday
        #expect(DayKey.monday(of: "2026-09-14", in: tz) == "2026-09-14")
    }

    // MARK: dueRoutines over the real seed

    private func seeded() throws -> (ModelContext, [RoutineTask]) {
        let ctx = try Fixtures.context()
        try SeedImporter.mergeSeeds(ctx, sideQuestsCSV: Fixtures.csv("side_quests.csv"),
                                    routinesCSV: Fixtures.csv("routine_quests.csv"))
        return (ctx, try ctx.fetch(FetchDescriptor<RoutineTask>()))
    }

    /// `PLAN.md` §3's own numbers: Friday 1, Wednesday 3, Saturday 5. The rest of the week is the
    /// seed CSV counted by hand ("Go to the office" is inactive, so Mon/Thu don't carry it).
    @Test func seedLoadAcrossAPlainWeek() throws {
        let (_, routines) = try seeded()
        func load(_ d: String) -> Int {
            Schedule.dueRoutines(routines, occurrences: [], on: d, in: tz).count
        }
        #expect(load("2026-09-18") == 1)       // Fri
        #expect(load("2026-09-16") == 3)       // Wed
        #expect(load("2026-09-19") == 5)       // Sat, neither first nor last of the month
        #expect(load("2026-09-14") == 1)       // Mon
        #expect(load("2026-09-15") == 2)       // Tue
        #expect(load("2026-09-17") == 1)       // Thu
        #expect(load("2026-09-20") == 4)       // Sun
        #expect(load("2026-09-26") == 6)       // last Saturday: + review bills
        #expect(load("2026-10-03") == 6)       // first Saturday: + change bedsheets
    }

    @Test func inactiveAndUnparseableRoutinesAreNeverDue() throws {
        let ctx = try Fixtures.context()
        let off = RoutineTask(); off.text = "off"; off.spec = "SAT"; off.isActive = false
        let bad = RoutineTask(); bad.text = "bad"; bad.spec = "SATURDAY"
        let on = RoutineTask(); on.text = "on"; on.spec = "SAT"
        [off, bad, on].forEach(ctx.insert)
        let due = Schedule.dueRoutines([off, bad, on], occurrences: [], on: "2026-09-19", in: tz)
        #expect(due.map(\.text) == ["on"])
    }

    /// History comes from the routine's own occurrences, and only from days before the one asked.
    @Test func dueRoutinesReadsHistoryFromOccurrences() throws {
        let ctx = try Fixtures.context()
        let r = RoutineTask(); r.text = "every 3"; r.kind = .everyNDays; r.spec = "3"
        let other = RoutineTask(); other.text = "other"; other.kind = .everyNDays; other.spec = "3"
        ctx.insert(r); ctx.insert(other)
        let open = Fixtures.occurrence(ctx, "every 3", due: "2026-09-17")
        open.routineID = r.id

        #expect(Schedule.dueRoutines([r, other], occurrences: [open], on: "2026-09-18", in: tz)
                    .map(\.text) == ["other"])
        // Asked about a day that already has its occurrence (done ahead, or already generated),
        // it isn't due a second time.
        #expect(Schedule.dueRoutines([r], occurrences: [open], on: "2026-09-17", in: tz).isEmpty)
    }

    // MARK: rounds

    @Test func roundDays() {
        #expect(Schedule.roundDay(due: "2026-09-19", on: "2026-09-18", in: tz) == nil)
        #expect(Schedule.roundDay(due: "2026-09-19", on: "2026-09-19", in: tz) == 1)
        #expect(Schedule.roundDay(due: "2026-09-19", on: "2026-09-21", in: tz) == 3)
        #expect(Schedule.roundDay(due: "2026-09-19", on: "2026-09-22", in: tz) == nil)   // day 4
    }

    @Test func overdueIsDayTwoAndThreeStillOpen() throws {
        let ctx = try Fixtures.context()
        let today = Fixtures.occurrence(ctx, "today", due: "2026-09-21")
        let day2 = Fixtures.occurrence(ctx, "day 2", due: "2026-09-20")
        let day3 = Fixtures.occurrence(ctx, "day 3", due: "2026-09-19")
        let day4 = Fixtures.occurrence(ctx, "day 4", due: "2026-09-18")
        let done = Fixtures.occurrence(ctx, "done", due: "2026-09-20", completed: "2026-09-20")
        let skipped = Fixtures.occurrence(ctx, "skipped", due: "2026-09-20")
        skipped.skipped = true
        let result = Schedule.overdue([today, day2, day3, day4, done, skipped], flexible: [],
                                      on: "2026-09-21", in: tz)
        #expect(result.map(\.textSnapshot) == ["day 3", "day 2"])
    }
}
