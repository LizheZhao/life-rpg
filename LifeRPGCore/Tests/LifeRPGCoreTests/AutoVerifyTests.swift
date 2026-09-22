import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// Auto-verification (`PLAN.md` §5): calendar workouts past a duration threshold and HealthKit
/// mindful minutes complete the matching quest or routine without a tap.
/// W38: Fri 2026-09-18, Sat 19, Sun 20; W39: Mon 21.
struct AutoVerifyTests {
    private let tz = Fixtures.tokyo
    private let fri = "2026-09-18", sat = "2026-09-19", sun = "2026-09-20", mon = "2026-09-21"
    private let filter = WorkoutFilter(calendarID: "cal-workouts", keywords: ["Workout", "运动"])

    private func at(_ day: String, _ hour: Int, _ minute: Int = 0) -> Date {
        Fixtures.date(day, hour: hour, in: tz).addingTimeInterval(Double(minute) * 60)
    }

    private func event(_ day: String, minutes: Int, title: String = "Workout",
                       calendar: String = "cal-workouts", allDay: Bool = false) -> CalendarEvent {
        let start = at(day, 18)
        return CalendarEvent(calendarID: calendar, title: title, start: start,
                             end: start.addingTimeInterval(Double(minutes) * 60), isAllDay: allDay)
    }

    private func routine(_ ctx: ModelContext, spec: String = "SAT", base: Int = 25,
                         rule: String? = "calendar_workout:25", flexible: Bool = false) -> RoutineTask {
        let r = RoutineTask()
        r.text = "Workout: running"; r.spec = spec; r.basePoints = base
        r.autoVerifyRule = rule; r.flexibleWithinWeek = flexible
        ctx.insert(r)
        return r
    }

    private func occurrence(_ ctx: ModelContext, _ r: RoutineTask, due: String) -> RoutineOccurrence {
        let o = RoutineOccurrence(routine: r, dueDayKey: due, weekKey: DayKey.weekKey(of: due, in: tz)!)
        ctx.insert(o)
        return o
    }

    private func quest(_ ctx: ModelContext, rule: String?, on day: String,
                       _ difficulty: Difficulty = .medium) -> DailyQuest {
        let t = Fixtures.quest(ctx, "Walk by the river", difficulty)
        t.autoVerifyRule = rule
        let q = DailyQuest(template: t, slot: difficulty, dayKey: day, weekKey: DayKey.weekKey(of: day, in: tz)!)
        ctx.insert(q)
        return q
    }

    private func run(_ ctx: ModelContext, _ day: String, _ evidence: DayEvidence) throws -> Int {
        var rng = SeededRNG(seed: 1)
        return try AutoVerify.run(on: day, evidence: evidence, in: ctx, now: at(day, 21), timeZone: tz, rng: &rng)
    }

    // MARK: evidence

    @Test func onlyEventsInTheChosenCalendarWithAKeywordCount() {
        let events = [
            event(sat, minutes: 45),                                   // counts
            event(sat, minutes: 30, title: "morning 运动"),              // counts — any keyword
            event(sat, minutes: 60, title: "workout (lower body)"),    // counts — case-insensitive
            event(sat, minutes: 90, title: "Team meeting"),            // right calendar, no keyword
            event(sat, minutes: 90, calendar: "cal-work"),             // keyword, wrong calendar
            event(sat, minutes: 1440, allDay: true),                   // all-day never counts
        ]
        let e = AutoVerify.evidence(events: events, mindful: [], filter: filter, in: tz)
        #expect(e[sat]?.workoutMinutes.sorted() == [30, 45, 60])
    }

    /// Both halves of the filter must be set — an unconfigured filter matches nothing rather than
    /// letting every long meeting count as a workout.
    @Test func anUnconfiguredFilterMatchesNothing() {
        let events = [event(sat, minutes: 45)]
        for f in [WorkoutFilter(calendarID: "", keywords: ["Workout"]),
                  WorkoutFilter(calendarID: "cal-workouts", keywords: []),
                  WorkoutFilter(calendarID: "cal-workouts", keywords: ["  "])] {
            #expect(AutoVerify.evidence(events: events, mindful: [], filter: f, in: tz)[sat] == nil)
        }
    }

    @Test func keywordsParseFromACommaSeparatedSetting() {
        #expect(WorkoutFilter.keywords(from: " Workout, 运动 ,,") == ["Workout", "运动"])
    }

    @Test func mindfulSessionsAccumulatePerDay() {
        let sessions = [
            MindfulSession(start: at(sat, 7), end: at(sat, 7, 10)),
            MindfulSession(start: at(sat, 22), end: at(sat, 22, 6)),
            MindfulSession(start: at(sun, 7), end: at(sun, 7, 5)),
        ]
        let e = AutoVerify.evidence(events: [], mindful: sessions, filter: filter, in: tz)
        #expect(e[sat]?.mindfulMinutes == 16)
        #expect(e[sun]?.mindfulMinutes == 5)
    }

    // MARK: run

    @Test func aLongEnoughWorkoutCompletesTheRoutine() throws {
        let ctx = try Fixtures.context()
        let o = occurrence(ctx, routine(ctx), due: sat)
        #expect(try run(ctx, sat, DayEvidence(workoutMinutes: [30])) == 1)
        #expect(o.completedDayKey == sat)
        #expect(o.awardedPoints == 25)
        #expect(o.sourceType == .healthKit)
        let ledger = try ctx.fetch(FetchDescriptor<LedgerEntry>())
        #expect(ledger.map(\.points) == [25])
    }

    @Test func aShortWorkoutDoesNot() throws {
        let ctx = try Fixtures.context()
        let o = occurrence(ctx, routine(ctx), due: sat)
        #expect(try run(ctx, sat, DayEvidence(workoutMinutes: [24])) == 0)
        #expect(o.completedDayKey == nil)
    }

    @Test func mindfulMinutesCompleteAQuest() throws {
        let ctx = try Fixtures.context()
        let q = quest(ctx, rule: "mindful:15", on: sat, .easy)
        #expect(try run(ctx, sat, DayEvidence(mindfulMinutes: 14)) == 0)
        #expect(try run(ctx, sat, DayEvidence(mindfulMinutes: 16)) == 1)
        #expect(q.completedAt != nil)
        #expect(q.sourceType == .healthKit)
        #expect(Difficulty.easy.range.contains(q.points ?? -1))
    }

    /// One workout is one workout: it can't pay for the routine and the quest both.
    @Test func oneEventVerifiesOneThing() throws {
        let ctx = try Fixtures.context()
        let o = occurrence(ctx, routine(ctx, rule: "calendar_workout:20"), due: sat)
        let q = quest(ctx, rule: "calendar_workout:20", on: sat)
        #expect(try run(ctx, sat, DayEvidence(workoutMinutes: [45])) == 1)
        #expect(o.completedDayKey == sat)                // routines are served first
        #expect(q.completedAt == nil)

        // A second session later that day covers the quest too.
        #expect(try run(ctx, sat, DayEvidence(workoutMinutes: [45, 20])) == 1)
        #expect(q.completedAt != nil)
    }

    /// Each item takes the shortest event that is long enough, leaving the long one for the
    /// threshold that needs it.
    @Test func theShortestSufficientEventIsUsed() throws {
        let ctx = try Fixtures.context()
        let short = occurrence(ctx, routine(ctx, rule: "calendar_workout:20"), due: sat)
        let long = occurrence(ctx, routine(ctx, rule: "calendar_workout:40"), due: sat)
        #expect(try run(ctx, sat, DayEvidence(workoutMinutes: [45, 25])) == 2)
        #expect(short.completedDayKey == sat && long.completedDayKey == sat)
    }

    /// Something already done that day — by hand or automatically — has used up its evidence, so
    /// the next foreground doesn't hand the same workout to a quest drawn since.
    @Test func somethingAlreadyDoneKeepsItsEvidence() throws {
        let ctx = try Fixtures.context()
        let o = occurrence(ctx, routine(ctx, rule: "calendar_workout:20"), due: sat)
        try Completion.completeRoutine(o, on: sat, tier: .normal, in: ctx, now: at(sat, 19), timeZone: tz)
        let q = quest(ctx, rule: "calendar_workout:20", on: sat)
        #expect(try run(ctx, sat, DayEvidence(workoutMinutes: [45])) == 0)
        #expect(q.completedAt == nil)
        #expect(o.sourceType == .manual)
    }

    @Test func runningTwiceChangesNothing() throws {
        let ctx = try Fixtures.context()
        _ = occurrence(ctx, routine(ctx), due: sat)
        _ = quest(ctx, rule: "mindful:15", on: sat, .easy)
        let evidence = DayEvidence(mindfulMinutes: 20, workoutMinutes: [30])
        #expect(try run(ctx, sat, evidence) == 2)
        #expect(try run(ctx, sat, evidence) == 0)
        #expect(try ctx.fetch(FetchDescriptor<LedgerEntry>()).count == 2)
    }

    /// A fixed routine done on round day 2 is a late make-up: half pay, like a tap would be.
    @Test func aLateWorkoutPaysTheLateRate() throws {
        let ctx = try Fixtures.context()
        let o = occurrence(ctx, routine(ctx, base: 50), due: sat)
        #expect(try run(ctx, sun, DayEvidence(workoutMinutes: [30])) == 1)
        #expect(o.completedDayKey == sun)
        #expect(o.awardedPoints == 25)
    }

    /// The day's own tier sets the multiplier: base 25 on a low day → 32.5 → 33.
    @Test func aLowDayPaysTheEffortMultiplier() throws {
        let ctx = try Fixtures.context()
        let day = DailyContext()
        day.dayKey = sat
        day.tier = .low
        ctx.insert(day)
        let o = occurrence(ctx, routine(ctx), due: sat)
        #expect(try run(ctx, sat, DayEvidence(workoutMinutes: [30])) == 1)
        #expect(o.awardedPoints == 33)
    }

    @Test func itemsWithoutARuleOrWithAWeeklyRuleAreLeftAlone() throws {
        let ctx = try Fixtures.context()
        let manual = occurrence(ctx, routine(ctx, rule: nil), due: sat)
        let weekly = quest(ctx, rule: "calendar_workout_weekly:4", on: sat)   // epic, Stage 5
        #expect(try run(ctx, sat, DayEvidence(mindfulMinutes: 60, workoutMinutes: [90, 90, 90, 90])) == 0)
        #expect(manual.completedDayKey == nil)
        #expect(weekly.completedAt == nil)
    }

    @Test func aReplacedSlotIsNotVerified() throws {
        let ctx = try Fixtures.context()
        let q = quest(ctx, rule: "mindful:15", on: sat, .easy)
        q.replaced = true
        #expect(try run(ctx, sat, DayEvidence(mindfulMinutes: 30)) == 0)
        #expect(q.completedAt == nil)
    }

    @Test func aRoutineNotDueYetIsNotVerified() throws {
        let ctx = try Fixtures.context()
        let o = occurrence(ctx, routine(ctx), due: sun)
        #expect(try run(ctx, sat, DayEvidence(workoutMinutes: [30])) == 0)
        #expect(o.completedDayKey == nil)
    }

    // MARK: ensureToday

    /// Worked out Saturday, didn't open the app until Monday: Saturday's evidence is applied
    /// before Saturday is judged, so there is no overdue penalty.
    @Test func catchUpVerifiesADayBeforeJudgingIt() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx, base: 50)
        var rng = SeededRNG(seed: 1)
        try DayService.ensureToday(ctx, now: at(sat, 8), in: tz, rng: &rng)
        let o = try #require(try DayService.occurrences(dueOn: sat, in: ctx).first)
        #expect(o.routineID == r.id)

        try DayService.ensureToday(ctx, now: at(mon, 8), in: tz,
                                   evidence: [sat: DayEvidence(workoutMinutes: [30])], rng: &rng)
        #expect(o.completedDayKey == sat)
        #expect(o.awardedPoints == 50)
        #expect(o.penaltyApplied == 0)
        let kinds = try ctx.fetch(FetchDescriptor<LedgerEntry>()).map(\.kind)
        #expect(!kinds.contains(Economy.Kind.penalty.rawValue))
    }

    /// Without the evidence the same Monday charges the day-1 penalty — the control for the above.
    @Test func withoutEvidenceTheDayIsStillJudged() throws {
        let ctx = try Fixtures.context()
        _ = routine(ctx, base: 50)
        var rng = SeededRNG(seed: 1)
        try DayService.ensureToday(ctx, now: at(sat, 8), in: tz, rng: &rng)
        try DayService.ensureToday(ctx, now: at(mon, 8), in: tz, rng: &rng)
        let o = try #require(try DayService.occurrences(dueOn: sat, in: ctx).first)
        #expect(o.completedDayKey == nil)
        #expect(o.penaltyApplied > 0)
    }

    /// Every foreground re-checks today, so a workout synced at noon lands without a tap.
    @Test func ensureTodayVerifiesTodayOnEveryCall() throws {
        let ctx = try Fixtures.context()
        _ = routine(ctx, spec: "FRI")
        var rng = SeededRNG(seed: 1)
        try DayService.ensureToday(ctx, now: at(fri, 8), in: tz, rng: &rng)
        let o = try #require(try DayService.occurrences(dueOn: fri, in: ctx).first)
        #expect(o.completedDayKey == nil)
        try DayService.ensureToday(ctx, now: at(fri, 12), in: tz,
                                   evidence: [fri: DayEvidence(workoutMinutes: [30])], rng: &rng)
        #expect(o.completedDayKey == fri)
        #expect(o.sourceType == .healthKit)
    }
}
