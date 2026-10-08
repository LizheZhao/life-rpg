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

    @Test func aQuestNeedsText() throws {
        let ctx = try Fixtures.context()
        #expect(throws: LibrarySave.Failure.emptyText) {
            try LibrarySave.saveQuest(text: "   ", .init(difficulty: .easy), in: ctx)
        }
    }

    // MARK: quests of every tier (a quest has no points of its own: its tier's range decides)

    @Test func aQuestCanBeAnyOfTheFiveTiers() throws {
        let ctx = try Fixtures.context()
        for d in Difficulty.allCases {
            let t = try LibrarySave.saveQuest(text: "mine-\(d.rawValue)", .init(difficulty: d), in: ctx)
            #expect(t.difficulty == d && t.origin == .user && t.isActive)
        }
        #expect(try ctx.fetch(FetchDescriptor<QuestTemplate>()).count == 5)
    }

    @Test func theTiersOnOfferDependOnWhatIsBeingSaved() {
        #expect(LibrarySave.difficulties(for: .quest) == [.trivial, .easy, .medium, .hard, .epic])
        #expect(LibrarySave.difficulties(for: .routine) == [.easy, .medium, .hard])
    }

    /// An epic is one a week, not a daily slot, so "weekends only" means nothing to it; and the
    /// hidden quest is a light daily bonus, which an epic would not be. Whatever the form held when
    /// the tier was switched, an epic is saved without either.
    @Test func anEpicIsNeverHiddenEligibleOrWeekendOnly() throws {
        let ctx = try Fixtures.context()
        #expect(!LibrarySave.allowsHiddenAndWeekend(.epic))
        for d in [Difficulty.trivial, .easy, .medium, .hard] { #expect(LibrarySave.allowsHiddenAndWeekend(d)) }

        let epic = try LibrarySave.saveQuest(text: "Write a short story",
                                             .init(difficulty: .epic, hiddenEligible: true, weekendOnly: true), in: ctx)
        #expect(!epic.hiddenEligible && !epic.weekendOnly)
        #expect(Sampling.eligibleHidden([epic], dayKey: "2026-09-26", in: tz).isEmpty)       // a Saturday
    }

    /// A micro-action is a quest like the seed's: it may be the hidden quest, and the seed has
    /// some that are.
    @Test func aTrivialQuestKeepsHiddenAndWeekendChoices() throws {
        let ctx = try Fixtures.context()
        let t = try LibrarySave.saveQuest(text: "Stretch for one minute",
                                          .init(difficulty: .trivial, hiddenEligible: true, weekendOnly: true), in: ctx)
        #expect(t.hiddenEligible && t.weekendOnly && t.difficulty == .trivial)
    }

    /// The T group is three distinct trivial rows drawn at random, so a row the user wrote is just
    /// one more candidate: no pairing is asked for.
    @Test func savedTrivialsJoinTheTGroupPool() throws {
        let ctx = try Fixtures.context()
        let mine = try (0..<3).map {
            try LibrarySave.saveQuest(text: "micro \($0)", .init(difficulty: .trivial), in: ctx)
        }
        let pool = Sampling.eligible(try Sampling.activeTemplates(ctx), difficulty: .trivial,
                                     dayKey: "2026-09-23", in: tz)                           // a Wednesday
        #expect(Set(pool.map(\.id)) == Set(mine.map(\.id)))
        var rng = SeededRNG(seed: 7)
        #expect(Sampling.pickDistinct(3, from: pool, rng: &rng).count == 3)
    }

    /// The weekly draw reads every active epic template, whoever wrote it, and the cooldown is the
    /// tier's own.
    @Test func aSavedEpicIsDrawnForTheWeek() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        let mine = try LibrarySave.saveQuest(text: "Write a short story", .init(difficulty: .epic), in: ctx)
        try ctx.save()
        var rng = SeededRNG(seed: 1)
        _ = try DayService.ensureToday(ctx, now: Fixtures.date("2026-09-21"), in: tz, rng: &rng)   // a Monday
        let epic = try #require(try ctx.fetch(FetchDescriptor<DailyQuest>()).first { $0.slot == .epic })
        #expect(epic.templateID == mine.id && epic.textSnapshot == "Write a short story")
        #expect(mine.effectiveCooldownDays == Difficulty.epic.cooldownDays)
    }

    @Test func aRoutineStillNeedsEMH() throws {
        let ctx = try Fixtures.context()
        for d in [Difficulty.trivial, .epic] {
            #expect(throws: LibrarySave.Failure.noDifficulty) {
                try LibrarySave.saveRoutine(text: "x", .init(difficulty: d, every: .weekly([.friday])), in: ctx)
            }
        }
        var draft = LibrarySave.Draft()
        draft.kind = .routine
        draft.days = [.monday]
        #expect(throws: LibrarySave.Failure.noDifficulty) { try draft.save(text: "y", difficulty: .epic, in: ctx) }
    }

    @Test func aTrivialAndAnEpicDraftSaveAsQuests() throws {
        let ctx = try Fixtures.context()
        let draft = LibrarySave.Draft()
        for d in [Difficulty.trivial, .epic] {
            guard case .quest(let t) = try draft.save(text: "q-\(d.rawValue)", difficulty: d, in: ctx) else {
                Issue.record("expected a quest"); return
            }
            #expect(t.difficulty == d)
        }
    }

    @Test func savedTrivialAndEpicRowsSurviveABackupAndPassTheAudit() throws {
        let source = try Fixtures.context()
        try LibrarySave.saveQuest(text: "Stretch for one minute", .init(difficulty: .trivial), in: source)
        try LibrarySave.saveQuest(text: "Write a short story", .init(difficulty: .epic), in: source)

        let target = try Fixtures.context()
        let plan = try JSONImport.plan(try JSONExport.data(source), against: target)
        try JSONImport.apply(plan, to: target)
        let back = try target.fetch(FetchDescriptor<QuestTemplate>())
        #expect(Dictionary(uniqueKeysWithValues: back.map { ($0.text, $0.difficulty) })
                == ["Stretch for one minute": .trivial, "Write a short story": .epic])
        #expect(try StoreAudit.issues(target).isEmpty)
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
        let full = try #require(try JSONExport.snapshot(ctx).fullLibrary)
        #expect(full.quests.map(\.text) == ["Call grandma"] && full.routines.map(\.text) == ["Piano"])
        #expect(full.quests.first?.origin == "user" && full.routines.first?.origin == "user")
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
