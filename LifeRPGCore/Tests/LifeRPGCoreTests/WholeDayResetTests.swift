import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// Reset today: the debug tool that puts the day back as if it had just been opened — everything
/// dated today is gone and the day is generated again — while every other day is left as it was.
struct WholeDayResetTests {
    private let tz = Fixtures.tokyo
    private let thursday = "2026-09-17", friday = "2026-09-18"

    private func routine(_ ctx: ModelContext, _ text: String, spec: String, base: Int = 20,
                         flexible: Bool = false) -> RoutineTask {
        let r = RoutineTask()
        r.text = text; r.spec = spec; r.basePoints = base; r.flexibleWithinWeek = flexible
        ctx.insert(r)
        return r
    }

    private func opened(_ ctx: ModelContext, on day: String, seed: UInt64 = 4,
                        tier: Tier = .normal) throws -> SeededRNG {
        var rng = SeededRNG(seed: seed)
        try DayService.ensureToday(ctx, now: Fixtures.date(day), in: tz, inputs: DayInputs(tier: tier), rng: &rng)
        return rng
    }

    private func reset(_ ctx: ModelContext, _ day: String = "2026-09-18", seed: UInt64 = 99) throws -> DayReset.Reset {
        var rng = SeededRNG(seed: seed)
        return try DayReset.reset(ctx, dayKey: day, now: Fixtures.date(day), in: tz, rng: &rng)
    }

    private func playEverything(_ ctx: ModelContext, on day: String, rng: inout SeededRNG) throws {
        for quest in try DayService.quests(on: day, in: ctx) where !(quest.slot == .epic && !quest.isHiddenSlot) {
            quest.trivialDone = quest.trivialDone.map { _ in true }
            try Completion.complete(quest, tier: .normal, in: ctx, now: Fixtures.date(day), rng: &rng)
        }
        for o in try DayService.occurrences(dueOn: day, in: ctx) {
            try Completion.completeRoutine(o, on: day, tier: .normal, in: ctx, now: Fixtures.date(day), timeZone: tz)
        }
    }

    // MARK: the day comes back whole

    @Test func theDayIsGeneratedAgainAndOpen() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        routine(ctx, "Piano", spec: "FRI")
        try ctx.save()
        var rng = try opened(ctx, on: friday, tier: .low)
        try playEverything(ctx, on: friday, rng: &rng)
        try AdHoc.add(.custom(text: "An extra", difficulty: .easy), on: friday, in: ctx, timeZone: tz)
        #expect(try Economy.balance(ctx) > 0)

        let result = try reset(ctx)
        #expect(result.occurrences >= 2 && result.quests > 0)
        #expect(try Economy.balance(ctx) == 0)                       // every payout of the day is gone
        let day = try #require(try DayService.dailyContext(for: friday, in: ctx))
        #expect(day.tier == .low)                                    // the day keeps the tier it had
        #expect(try DayService.quests(on: friday, in: ctx).allSatisfy { $0.completedAt == nil && !$0.replaced })
        let occurrences = try DayService.occurrences(dueOn: friday, in: ctx)
        #expect(occurrences.map(\.textSnapshot) == ["Piano"])        // scheduled again; the extra is gone
        #expect(occurrences.allSatisfy { $0.completedDayKey == nil && $0.awardedPoints == nil })
    }

    @Test func aRerolledOrSwappedSlotComesBackAsADrawnOne() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = try opened(ctx, on: friday)
        let slot = try #require(try DayService.quests(on: friday, in: ctx).first { !$0.isTrivialGroup && !$0.isHiddenSlot })
        try AdHoc.replace(slot, with: .custom(text: "A swap", difficulty: slot.slot), in: ctx, timeZone: tz)
        _ = rng.next()

        try reset(ctx)
        let after = try DayService.quests(on: friday, in: ctx)
        #expect(after.allSatisfy { !$0.replaced })
        #expect(try DayService.occurrences(dueOn: friday, in: ctx).allSatisfy { $0.textSnapshot != "A swap" })
    }

    // MARK: what is undone with it

    @Test func ratingsAndNotesGivenToTheDaysThingsGoWithThem() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = try opened(ctx, on: friday)
        let quest = try #require(try DayService.quests(on: friday, in: ctx).first { $0.templateID != nil })
        try Completion.complete(quest, tier: .normal, in: ctx, now: Fixtures.date(friday), rng: &rng)
        Feedback.rate(ctx, target: .quest, id: quest.templateID, questID: quest.id, text: "x", rating: 2, dayKey: friday)
        Feedback.comment(ctx, target: .quest, id: quest.templateID, questID: quest.id, text: "x", comment: "c", dayKey: friday)
        // A note about the library row itself, written on the Library page, is not the day's.
        Feedback.comment(ctx, target: .quest, id: quest.templateID, text: "x", comment: "general", dayKey: friday)
        try ctx.save()

        try reset(ctx)
        #expect(try ctx.fetch(FetchDescriptor<QuestRating>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<QuestComment>()).map(\.comment) == ["general"])
    }

    @Test func cooldownsStartedByTheDayAreGivenBack() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        // Weekend-only keeps it out of Friday's pool: if the draw picked and finished it, its stamp
        // would be today's and reset would rightly clear it, which is not what this test is about.
        let old = Fixtures.quest(ctx, "Done a week ago", weekendOnly: true, completed: "2026-09-10", served: "2026-09-10")
        var rng = try opened(ctx, on: friday)
        try playEverything(ctx, on: friday, rng: &rng)
        #expect(try ctx.fetch(FetchDescriptor<QuestTemplate>()).contains { $0.lastCompletedDayKey == friday })

        try reset(ctx)
        // None of the new draw has been completed, and an older stamp is not today's to clear.
        #expect(try ctx.fetch(FetchDescriptor<QuestTemplate>()).allSatisfy { $0.lastCompletedDayKey != friday })
        #expect(old.lastCompletedDayKey == "2026-09-10")
    }

    @Test func aReplacedRoutineComesBack() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx, "Piano", spec: "FRI", base: 20)
        try ctx.save()
        _ = try opened(ctx, on: friday)
        let o = try #require(try DayService.occurrences(dueOn: friday, in: ctx).first)
        try AdHoc.replaceRoutine(o, flexible: false, with: .custom(text: "Heavier", difficulty: .hard),
                                 on: friday, in: ctx, timeZone: tz)

        try reset(ctx)
        let today = try DayService.occurrences(dueOn: friday, in: ctx)
        #expect(today.map(\.textSnapshot) == ["Piano"])
        #expect(today.allSatisfy { !$0.skipped && $0.replacedByID == nil })
        _ = r
    }

    // MARK: routines done on today but not due today

    @Test func aLateMakeUpIsReopenedAndTheRoutinesStampRecomputed() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx, "Trash", spec: "WED", base: 10)
        try ctx.save()
        // Wednesday's occurrence, done on Thursday morning's day: due 09-16, completed 09-17 — a day
        // that is not the one being reset — then Friday's make-up of a different, older round.
        let earlier = RoutineOccurrence(routine: r, dueDayKey: "2026-09-09", weekKey: "2026-W37")
        earlier.completedDayKey = "2026-09-09"; earlier.awardedPoints = 10
        let late = RoutineOccurrence(routine: r, dueDayKey: "2026-09-16", weekKey: "2026-W38")
        ctx.insert(earlier); ctx.insert(late)
        r.lastCompletedDayKey = "2026-09-09"
        try ctx.save()
        _ = try opened(ctx, on: friday)
        try Completion.completeRoutine(late, on: friday, tier: .normal, in: ctx, now: Fixtures.date(friday), timeZone: tz)
        #expect(r.lastCompletedDayKey == friday && late.completedDayKey == friday)

        try reset(ctx)
        #expect(late.completedDayKey == nil && late.awardedPoints == nil && late.completedAt == nil)
        #expect(try Economy.balance(ctx) == 0)
        #expect(r.lastCompletedDayKey == "2026-09-09")               // back to the last completion still on record
        #expect(earlier.completedDayKey == "2026-09-09")
    }

    @Test func aSessionDoneAheadTodayDisappearsWithTheDay() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx, "Run", spec: "SAT", base: 25, flexible: true)
        try ctx.save()
        _ = try opened(ctx, on: friday)
        try Completion.completeAhead(r, on: friday, tier: .normal, light: false, in: ctx, timeZone: tz)
        #expect(try ctx.fetch(FetchDescriptor<RoutineOccurrence>()).contains { $0.dueDayKey == "2026-09-19" })

        try reset(ctx)
        #expect(try ctx.fetch(FetchDescriptor<RoutineOccurrence>()).allSatisfy { $0.dueDayKey != "2026-09-19" })
        #expect(try Economy.balance(ctx) == 0)
        #expect(r.lastCompletedDayKey == nil)
    }

    // MARK: the weekly epic stays

    @Test func theEpicDoneTodayIsReopenedNotRedrawn() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        Fixtures.quest(ctx, "Finish a book", .epic)
        var rng = try opened(ctx, on: friday)
        let epic = try #require(try ctx.fetch(FetchDescriptor<DailyQuest>()).first { $0.slot == .epic && !$0.isHiddenSlot })
        epic.extensionCount = 1
        try Completion.complete(epic, tier: .normal, in: ctx, now: Fixtures.date(friday), timeZone: tz, rng: &rng)
        #expect(epic.points != nil)

        try reset(ctx)
        let after = try ctx.fetch(FetchDescriptor<DailyQuest>()).filter { $0.slot == .epic && !$0.isHiddenSlot }
        #expect(after.map(\.id) == [epic.id])                         // the same row, not a new draw
        #expect(epic.points == nil && epic.completedAt == nil && epic.extensionCount == 1)
        #expect(try Economy.balance(ctx) == 0)
    }

    // MARK: other days, and what the day's opening did to yesterday

    @Test func otherDaysAreLeftAlone() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        routine(ctx, "Piano", spec: "THU,FRI")
        try ctx.save()
        var rng = try opened(ctx, on: thursday, seed: 5)
        try playEverything(ctx, on: thursday, rng: &rng)
        let earned = try Economy.balance(ctx)
        _ = try opened(ctx, on: friday, seed: 6)

        try reset(ctx)
        #expect(try Economy.balance(ctx) == earned)
        #expect(try DayService.quests(on: thursday, in: ctx).allSatisfy { $0.completedAt != nil })
        #expect(try DayService.occurrences(dueOn: thursday, in: ctx).allSatisfy { $0.completedDayKey == thursday })
    }

    /// Opening Friday judged Thursday; resetting Friday must not un-judge it, or the missed routine
    /// would be charged again when the day is opened again.
    @Test func yesterdaysSettlementDatedTodayStays() throws {
        let ctx = try Fixtures.context()
        routine(ctx, "Trash", spec: "THU", base: 20)
        try ctx.save()
        _ = try opened(ctx, on: thursday)                           // due Thursday, left undone
        _ = try opened(ctx, on: friday)                             // Friday's opening charges Thursday: −10
        let charged = try Economy.balance(ctx)
        #expect(charged == -10)

        try reset(ctx)
        #expect(try Economy.balance(ctx) == charged)
        let o = try #require(try ctx.fetch(FetchDescriptor<RoutineOccurrence>()).first { $0.dueDayKey == thursday })
        #expect(o.penaltyApplied == 10 && !o.skipped)
    }

    // MARK: a recovery day

    /// The day keeps the recovery mark it was drawn with, as it keeps its tier: drawn again without
    /// it, the reset day would ask for the heavy routine and be judged with penalties.
    @Test func aRecoveryDayIsDrawnAgainAsARecoveryDay() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        let heavy = routine(ctx, "Long run", spec: "FRI")
        heavy.difficulty = .hard
        try ctx.save()
        let stretch = RecoveryPeriod(firstDayKey: friday, lastDayKey: "2026-09-30")
        var rng = SeededRNG(seed: 4)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz,
                                   inputs: Recovery.applied(stretch, to: DayInputs(tier: .high), on: friday), rng: &rng)
        try playEverything(ctx, on: friday, rng: &rng)

        try reset(ctx)
        let day = try #require(try DayService.dailyContext(for: friday, in: ctx))
        #expect(day.isRecovery)
        #expect(day.tier == .veryLow)
        let quests = try DayService.quests(on: friday, in: ctx).filter { !$0.replaced && !$0.isHiddenSlot }
        #expect(!quests.contains { $0.slot == .epic })
        #expect(quests.map(\.slot.code).sorted() == ["E", "E", "T"])
        #expect(try DayService.occurrences(dueOn: friday, in: ctx).allSatisfy { $0.routineID != heavy.id })
    }

    @Test func anOrdinaryDayStaysOrdinary() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        _ = try opened(ctx, on: friday)
        try reset(ctx)
        #expect(try DayService.dailyContext(for: friday, in: ctx)?.isRecovery == false)
    }
}
