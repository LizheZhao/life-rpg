import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// "Save to library": a task the user typed becomes a quest in the random pool, or a routine on a
/// schedule. What it pays follows from its difficulty (the same midpoints a custom ad-hoc task
/// pays), and a routine always counts toward clearing the day.
struct LibrarySaveTests {
    private let tz = Fixtures.tokyo

    private func routines(_ ctx: ModelContext) throws -> [RoutineTask] { try ctx.fetch(FetchDescriptor<RoutineTask>()) }

    // MARK: quests

    @Test func aSavedQuestJoinsThePoolAsTheUsersOwn() throws {
        let ctx = try Fixtures.context()
        let t = try LibrarySave.saveQuest(text: "  Call grandma \n",
                                          .init(difficulty: .medium, hiddenEligible: true, weekendOnly: true), in: ctx)
        #expect(t.text == "Call grandma")
        #expect(t.origin == .user && t.isActive && t.difficulty == .medium)
        #expect(t.hiddenEligible && t.weekendOnly)
        #expect(try ctx.fetch(FetchDescriptor<QuestTemplate>()).map(\.text) == ["Call grandma"])
    }

    @Test func aQuestNeedsTextAndAnEMHDifficulty() throws {
        let ctx = try Fixtures.context()
        #expect(throws: LibrarySave.Failure.emptyText) {
            try LibrarySave.saveQuest(text: "   ", .init(difficulty: .easy), in: ctx)
        }
        #expect(throws: LibrarySave.Failure.noDifficulty) {
            try LibrarySave.saveQuest(text: "x", .init(difficulty: .epic), in: ctx)
        }
        #expect(throws: LibrarySave.Failure.noDifficulty) {
            try LibrarySave.saveQuest(text: "x", .init(difficulty: .trivial), in: ctx)
        }
    }

    /// Text is a row's identity (the seed merge and the restore both match on it), so a second row
    /// with the same words — in any case — would be one the app can't tell apart.
    @Test func textThatIsTakenIsRefused() throws {
        let ctx = try Fixtures.context()
        Fixtures.quest(ctx, "Sing a song out loud at home")
        try ctx.save()
        #expect(throws: LibrarySave.Failure.textTaken) {
            try LibrarySave.saveQuest(text: "sing a SONG out loud at home", .init(difficulty: .easy), in: ctx)
        }
        // A routine of the same words is another table, and another identity.
        _ = try LibrarySave.saveRoutine(text: "Sing a song out loud at home",
                                        .init(difficulty: .easy, every: .weekly([.monday])), in: ctx)
    }

    // MARK: routines — what they pay

    @Test func aRoutinePaysByItsDifficulty() throws {
        let ctx = try Fixtures.context()
        let pays = try [Difficulty.easy, .medium, .hard].map { d in
            try LibrarySave.saveRoutine(text: "r-\(d.rawValue)",
                                        .init(difficulty: d, every: .weekly([.friday])), in: ctx).basePoints
        }
        #expect(pays == [10, 21, 38])               // the midpoints of 5–15, 12–30 and 25–50
        #expect(throws: LibrarySave.Failure.noDifficulty) {
            try LibrarySave.saveRoutine(text: "x", .init(difficulty: .epic, every: .weekly([.friday])), in: ctx)
        }
    }

    @Test func aSavedRoutineAlwaysCountsTowardClearing() throws {
        let ctx = try Fixtures.context()
        let r = try LibrarySave.saveRoutine(text: "Piano", .init(difficulty: .medium, every: .weekly([.monday])), in: ctx)
        #expect(r.countsForClear && r.isActive && r.origin == .user && r.difficulty == .medium)
        #expect(r.lastCompletedDayKey == nil && r.downgradeIDs.isEmpty)
    }

    // MARK: routines — weekly

    @Test func weeklyOnSetDaysIsDueThoseDaysAndAsksForEach() throws {
        let ctx = try Fixtures.context()
        let r = try LibrarySave.saveRoutine(text: "Piano",
                                            .init(difficulty: .easy, every: .weekly([.thursday, .monday, .monday])),
                                            in: ctx)
        #expect(r.kind == .weekly && r.spec == "MON,THU")          // sorted, once each
        #expect(r.weeklyTarget == 2 && !r.flexibleWithinWeek)
    }

    @Test func weeklyNeedsAtLeastOneDay() throws {
        let ctx = try Fixtures.context()
        #expect(throws: LibrarySave.Failure.noWeekday) {
            try LibrarySave.saveRoutine(text: "x", .init(difficulty: .easy, every: .weekly([])), in: ctx)
        }
    }

    /// Flexible: the days are when it comes due, and any day that week does; the target is how many
    /// of them have to be done, between one and the number of days.
    @Test func flexibleWeeklyCountsTimesPerWeekWithinTheDaysChosen() throws {
        let ctx = try Fixtures.context()
        func target(_ times: Int?, _ name: String) throws -> Int {
            try LibrarySave.saveRoutine(text: name,
                                        .init(difficulty: .medium, every: .weekly([.monday, .wednesday, .friday]),
                                              flexible: true, timesPerWeek: times), in: ctx).weeklyTarget
        }
        #expect(try target(nil, "a") == 3)           // not said: every day chosen
        #expect(try target(2, "b") == 2)
        #expect(try target(9, "c") == 3)             // never more than the days there are
        #expect(try target(0, "d") == 1)             // never less than one
        let flexible = try routines(ctx).first { $0.text == "b" }
        #expect(flexible?.flexibleWithinWeek == true)
    }

    // MARK: routines — monthly

    @Test func monthlyIsTheFirstOrLastGivenWeekdayOfTheMonth() throws {
        let ctx = try Fixtures.context()
        let last = try LibrarySave.saveRoutine(text: "Review the budget",
                                               .init(difficulty: .hard, every: .monthly(.last, .saturday)), in: ctx)
        #expect(last.kind == .nthWeekdayOfMonth && last.spec == "-1:SAT" && last.weeklyTarget == 1)
        #expect(!last.flexibleWithinWeek)
        let first = try LibrarySave.saveRoutine(text: "Plan the month",
                                                .init(difficulty: .easy, every: .monthly(.first, .monday), flexible: true),
                                                in: ctx)
        #expect(first.spec == "1:MON" && first.flexibleWithinWeek)
    }

    // MARK: and the calendar agrees

    @Test func theScheduleSeesWhatWasSaved() throws {
        let ctx = try Fixtures.context()
        let weekly = try LibrarySave.saveRoutine(text: "Piano",
                                                 .init(difficulty: .easy, every: .weekly([.monday, .thursday])), in: ctx)
        let monthly = try LibrarySave.saveRoutine(text: "Budget",
                                                  .init(difficulty: .easy, every: .monthly(.last, .saturday)), in: ctx)
        func due(_ r: RoutineTask, _ day: String) -> Bool {
            !Schedule.dueRoutines([r], occurrences: [], on: day, in: tz).isEmpty
        }
        #expect(due(weekly, "2026-09-21") && due(weekly, "2026-09-24"))       // a Monday, a Thursday
        #expect(!due(weekly, "2026-09-22"))                                     // a Tuesday
        #expect(due(monthly, "2026-09-26"))                                     // the last Saturday of September
        #expect(!due(monthly, "2026-09-19"))
    }

    @Test func savedRowsTravelInTheBackup() throws {
        let ctx = try Fixtures.context()
        try LibrarySave.saveQuest(text: "Call grandma", .init(difficulty: .easy), in: ctx)
        try LibrarySave.saveRoutine(text: "Piano", .init(difficulty: .easy, every: .weekly([.monday])), in: ctx)
        let mine = try #require(try JSONExport.snapshot(ctx).userLibrary)
        #expect(mine.quests.map(\.text) == ["Call grandma"] && mine.routines.map(\.text) == ["Piano"])
    }

    // MARK: the form's state (`Draft`)

    @Test func aDraftIsAQuestUntilToldOtherwise() throws {
        let ctx = try Fixtures.context()
        var draft = LibrarySave.Draft()
        draft.hiddenEligible = true
        guard case .quest(let t) = try draft.save(text: "Call grandma", difficulty: .hard, in: ctx) else {
            Issue.record("expected a quest"); return
        }
        #expect(t.hiddenEligible && !t.weekendOnly && t.difficulty == .hard && t.origin == .user)
    }

    @Test func aWeeklyRoutineDraftNeedsADayAndRemembersHowManyTimes() throws {
        let ctx = try Fixtures.context()
        var draft = LibrarySave.Draft()
        draft.kind = .routine
        #expect(draft.problem == .noWeekday)                       // nothing picked yet
        draft.days = [.tuesday, .friday]
        #expect(draft.problem == nil)
        #expect(draft.timesRange == 1...2)
        draft.flexible = true
        draft.timesPerWeek = 1
        guard case .routine(let r) = try draft.save(text: "Piano", difficulty: .medium, in: ctx) else {
            Issue.record("expected a routine"); return
        }
        #expect(r.spec == "TUE,FRI" && r.weeklyTarget == 1 && r.flexibleWithinWeek && r.basePoints == 21)
    }

    /// The monthly choice carries no day list, so a leftover pick from the weekly one is ignored,
    /// and "times a week" does not apply to it.
    @Test func aMonthlyRoutineDraftIgnoresWhatOnlyWeeklyUses() throws {
        let ctx = try Fixtures.context()
        var draft = LibrarySave.Draft()
        draft.kind = .routine
        draft.frequency = .monthly
        draft.days = []                                             // nothing to pick for a month
        draft.position = .first
        draft.monthlyWeekday = .monday
        draft.flexible = true
        draft.timesPerWeek = 5
        #expect(draft.problem == nil)
        guard case .routine(let r) = try draft.save(text: "Plan the month", difficulty: .easy, in: ctx) else {
            Issue.record("expected a routine"); return
        }
        #expect(r.spec == "1:MON" && r.weeklyTarget == 1 && r.flexibleWithinWeek)
    }

    @Test func aDraftThatIsAQuestNeverComplainsAboutDays() {
        var draft = LibrarySave.Draft()
        draft.kind = .quest
        draft.frequency = .weekly
        #expect(draft.problem == nil)
    }
}
