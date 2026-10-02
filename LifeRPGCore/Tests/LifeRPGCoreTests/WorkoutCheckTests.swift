import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// What "Check for workouts now" tells the user (`WorkoutCheck`), and the before/after diff of
/// what the check auto-verified.
struct WorkoutCheckTests {
    private let tz = Fixtures.tokyo
    private let sat = "2026-09-19"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var start: Date { now.addingTimeInterval(-14 * 86_400) }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Fixtures.date(sat, hour: hour, in: tz).addingTimeInterval(Double(minute) * 60)
    }

    private func event(_ title: String, hour: Int = 18, minutes: Int = 45, calendar: String = "cal",
                       allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(calendarID: calendar, title: title, start: at(hour),
                      end: at(hour).addingTimeInterval(Double(minutes) * 60), isAllDay: allDay)
    }

    private func make(access: Bool = true, calendars: CalendarSelection = .all,
                      keywords: [String] = ["Workout"], events: [CalendarEvent] = [],
                      evidence: DayEvidence = DayEvidence(),
                      before: [AutoVerifiedItem] = [], after: [AutoVerifiedItem] = []) -> WorkoutCheck {
        WorkoutCheck.make(checkedAt: now, windowStart: start, calendarAccess: access,
                          filter: WorkoutFilter(calendars: calendars, keywords: keywords),
                          events: events, todayEvidence: evidence, before: before, after: after)
    }

    // MARK: outcome

    @Test func withoutCalendarAccessNothingElseIsBlamed() {
        let c = make(access: false, calendars: .none, keywords: [])
        #expect(c.outcome == .noCalendarAccess)
    }

    @Test func noCalendarsSelected() {
        #expect(make(calendars: .none, keywords: []).outcome == .noCalendarsSelected)
    }

    @Test func noKeywords() {
        #expect(make(keywords: [], events: [event("Workout")]).outcome == .noKeywords)
        #expect(make(keywords: [" ", ""], events: [event("Workout")]).outcome == .noKeywords)
    }

    @Test func noEventsInTheWindow() {
        let c = make()
        #expect(c.outcome == .noEventsInWindow)
        #expect(c.eventsRead == 0)
    }

    @Test func eventsThatNoneMatchListUpToThreeTitlesNewestFirst() {
        let events = [event("Standup", hour: 9), event("Lunch", hour: 12), event("Review", hour: 15),
                      event("Planning", hour: 16), event("Workout", hour: 18, allDay: true)]
        let c = make(events: events)
        #expect(c.outcome == .noneMatched)
        #expect(c.eventsRead == 5)
        #expect(c.matched == 0)
        #expect(c.unmatched == [.init(title: "Workout", isAllDay: true),
                                .init(title: "Planning", isAllDay: false),
                                .init(title: "Review", isAllDay: false)])
    }

    @Test func matchedCountsOnlyWhatTheFilterAccepts() {
        let events = [event("Morning workout", hour: 7), event("Standup", hour: 9),
                      event("Workout", hour: 19, calendar: "other")]
        let c = make(calendars: .some(["cal"]), events: events)
        #expect(c.outcome == .matched)
        #expect(c.eventsRead == 3)
        #expect(c.matched == 1)
        #expect(c.unmatched.map(\.title) == ["Workout", "Standup"])
    }

    // MARK: evidence

    @Test func todaysEvidenceIsCarriedAsWholeMinutes() {
        let c = make(evidence: DayEvidence(mindfulMinutes: 14.6, workoutMinutes: [45, 30.4]))
        #expect(c.mindfulMinutes == 14)
        #expect(c.workoutMinutes == [45, 30])
    }

    // MARK: verified

    @Test func verifiedIsWhatTheCheckAddedNotWhatWasAlreadyThere() {
        let walk = AutoVerifiedItem(id: UUID(), title: "Walk")
        let run = AutoVerifiedItem(id: UUID(), title: "Run")
        let c = make(before: [walk], after: [walk, run])
        #expect(c.verified == ["Run"])
        #expect(make(before: [walk], after: [walk]).verified == [])
    }

    // MARK: AutoVerify.verifiedItems

    @Test func verifiedItemsListsOnlyHealthKitCompletionsOfThatDay() throws {
        let ctx = try Fixtures.context()
        let r = RoutineTask()
        r.text = "Workout: running"; r.spec = "SAT"; r.basePoints = 25
        r.autoVerifyRule = "calendar_workout:25"
        ctx.insert(r)
        let o = RoutineOccurrence(routine: r, dueDayKey: sat, weekKey: DayKey.weekKey(of: sat, in: tz)!)
        ctx.insert(o)
        let byHand = RoutineTask()
        byHand.text = "Stretch"; byHand.spec = "SAT"; byHand.basePoints = 10
        ctx.insert(byHand)
        let manual = RoutineOccurrence(routine: byHand, dueDayKey: sat, weekKey: DayKey.weekKey(of: sat, in: tz)!)
        ctx.insert(manual)
        try Completion.completeRoutine(manual, on: sat, tier: .normal, in: ctx, now: at(9), timeZone: tz)

        #expect(try AutoVerify.verifiedItems(on: sat, in: ctx).isEmpty)

        var rng = SeededRNG(seed: 1)
        try AutoVerify.run(on: sat, evidence: DayEvidence(workoutMinutes: [30]), in: ctx, now: at(21),
                           timeZone: tz, rng: &rng)
        let items = try AutoVerify.verifiedItems(on: sat, in: ctx)
        #expect(items == [AutoVerifiedItem(id: o.id, title: "Workout: running")])
        #expect(try AutoVerify.verifiedItems(on: "2026-09-20", in: ctx).isEmpty)
    }

    @Test func aWorkoutSyncedAfterTodayWasGeneratedVerifiesTodaysOpenQuest() throws {
        let ctx = try Fixtures.context()
        Fixtures.quest(ctx, "Tidy the desk", .medium)
        let t = Fixtures.quest(ctx, "Walk by the river", .medium)
        t.autoVerifyRule = "calendar_workout:20"
        t.isActive = false
        var rng = SeededRNG(seed: 1)
        try DayService.ensureToday(ctx, now: at(8), in: tz, rng: &rng)
        let q = DailyQuest(template: t, slot: .medium, dayKey: sat, weekKey: DayKey.weekKey(of: sat, in: tz)!)
        ctx.insert(q)

        let before = try AutoVerify.verifiedItems(on: sat, in: ctx)
        try DayService.ensureToday(ctx, now: at(12), in: tz,
                                   evidence: [sat: DayEvidence(workoutMinutes: [30])], rng: &rng)
        let after = try AutoVerify.verifiedItems(on: sat, in: ctx)

        #expect(before.isEmpty)
        #expect(after == [AutoVerifiedItem(id: q.id, title: "Walk by the river")])
        #expect(q.sourceType == .healthKit)
    }
}
