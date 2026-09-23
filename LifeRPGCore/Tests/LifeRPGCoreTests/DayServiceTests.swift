import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// Generating a day: idempotency, the catch-up loop, and what actually lands in the slots.
struct DayServiceTests {
    private let tz = Fixtures.tokyo
    private let friday = "2026-09-18"
    private let saturday = "2026-09-19"

    // MARK: generation

    @Test func generatesOneDayWithThreeSlotsAtNoRoutineLoad() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 1)
        let day = try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz, rng: &rng)

        #expect(day.dayKey == friday)
        #expect(day.randomSlots == 3)
        let quests = try DayService.quests(on: friday, in: ctx)
        #expect(quests.count == 3)
        #expect(quests.allSatisfy { $0.weekKey == "2026-W38" })
        #expect(quests.allSatisfy { !$0.textSnapshot.isEmpty })   // text is snapshotted, not referenced
    }

    /// Called again the same day it must change nothing — the guard is the `DailyContext`, so a day
    /// where every draw failed still counts as generated.
    @Test func isIdempotentWithinTheDay() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 1)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday, hour: 8), in: tz, rng: &rng)
        let first = try DayService.quests(on: friday, in: ctx).map(\.id)

        var rng2 = SeededRNG(seed: 99)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday, hour: 23), in: tz, rng: &rng2)
        #expect(try DayService.quests(on: friday, in: ctx).map(\.id) == first)
        #expect(try ctx.fetch(FetchDescriptor<DailyContext>()).count == 1)
    }

    @Test func emptyLibraryStillMarksTheDayGenerated() throws {
        let ctx = try Fixtures.context()
        var rng = SeededRNG(seed: 1)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz, rng: &rng)
        #expect(try DayService.quests(on: friday, in: ctx).isEmpty)
        #expect(try DayService.dailyContext(for: friday, in: ctx) != nil)
    }

    private func seedRoutines(_ ctx: ModelContext) throws {
        // Header only on the side: the stock library supplies the quests.
        let sideHeader = try Fixtures.csv("side_quests.csv").split(separator: "\n")[0] + "\n"
        try SeedImporter.mergeSeeds(ctx, sideQuestsCSV: String(sideHeader),
                                    routinesCSV: Fixtures.csv("routine_quests.csv"))
    }

    /// `PLAN.md` §3: "Saturday with 5 gets only 1". The load is counted from the seed, not passed in.
    @Test func saturdayRoutinesShrinkTheSlotsToOne() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        try seedRoutines(ctx)
        var rng = SeededRNG(seed: 4)
        let day = try DayService.ensureToday(ctx, now: Fixtures.date(saturday), in: tz, rng: &rng)
        #expect(day.routineLoad == 5)
        #expect(day.randomSlots == 1)
        #expect(try DayService.quests(on: saturday, in: ctx).count == 1)
        #expect(try DayService.occurrences(dueOn: saturday, in: ctx).count == 5)
    }

    @Test func fridayWithOneRoutineKeepsThreeSlots() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        try seedRoutines(ctx)
        var rng = SeededRNG(seed: 4)
        let day = try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz, rng: &rng)
        #expect(day.routineLoad == 1)
        #expect(day.randomSlots == 3)
    }

    @Test func occurrencesSnapshotTheRoutine() throws {
        let ctx = try Fixtures.context()
        let r = RoutineTask()
        r.text = "Take out the trash"; r.spec = "SAT"; r.basePoints = 5; r.countsForClear = false
        ctx.insert(r)
        var rng = SeededRNG(seed: 1)
        try DayService.ensureToday(ctx, now: Fixtures.date(saturday), in: tz, rng: &rng)

        let o = try #require(try DayService.occurrences(dueOn: saturday, in: ctx).first)
        #expect(o.routineID == r.id)
        #expect(o.weekKey == "2026-W38")
        #expect(o.basePoints == 5)
        #expect(!o.countsForClear)

        r.text = "Renamed"; r.basePoints = 50          // later edits don't reach history
        #expect(o.textSnapshot == "Take out the trash")
        #expect(o.basePoints == 5)
    }

    @Test func routinesAreScheduledOncePerDay() throws {
        let ctx = try Fixtures.context()
        try seedRoutines(ctx)
        var rng = SeededRNG(seed: 1)
        try DayService.ensureToday(ctx, now: Fixtures.date(saturday, hour: 8), in: tz, rng: &rng)
        try DayService.ensureToday(ctx, now: Fixtures.date(saturday, hour: 22), in: tz, rng: &rng)
        #expect(try ctx.fetch(FetchDescriptor<RoutineOccurrence>()).count == 5)
    }

    /// Friday's run is still open on Saturday (day 2 of its round), but only routines due Saturday
    /// size Saturday's random draw.
    @Test func overdueRoutinesDontCountTowardLoad() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        try seedRoutines(ctx)
        var rng = SeededRNG(seed: 1)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz, rng: &rng)
        let day = try DayService.ensureToday(ctx, now: Fixtures.date(saturday), in: tz, rng: &rng)
        #expect(day.routineLoad == 5)
        #expect(try DayService.occurrences(dueOn: friday, in: ctx).allSatisfy { $0.completedDayKey == nil })
    }

    @Test func hiddenStaysLockedUntilTheRoutinesAreDone() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        let r = RoutineTask(); r.text = "Workout: running"; r.spec = "FRI"; r.basePoints = 25
        ctx.insert(r)
        var rng = SeededRNG(seed: 1)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz, rng: &rng)
        for q in try DayService.quests(on: friday, in: ctx) {
            if q.isTrivialGroup { q.trivialDone = [true, true, true] }
            try Completion.complete(q, tier: .normal, in: ctx, rng: &rng)
        }
        #expect(try !DayService.hiddenUnlocked(on: friday, in: ctx))

        let o = try #require(try DayService.occurrences(dueOn: friday, in: ctx).first)
        try Completion.completeRoutine(o, on: friday, tier: .normal, in: ctx, timeZone: tz)
        #expect(try DayService.hiddenUnlocked(on: friday, in: ctx))
    }

    @Test func drawsAreNeverRepeatedWithinADay() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx, each: 3)
        for seed in UInt64(0)..<25 {
            let ctx = try Fixtures.context()
            Fixtures.stockLibrary(ctx, each: 3)
            var rng = SeededRNG(seed: seed)
            try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz, rng: &rng)
            let quests = try DayService.quests(on: friday, in: ctx)
            let ids = quests.compactMap(\.templateID) + quests.flatMap(\.trivialTemplateIDs)
            #expect(Set(ids).count == ids.count)
        }
    }

    /// Everything drawn gets `lastServedDayKey`, so an unfinished quest can't reappear tomorrow.
    @Test func drawingStampsTheOneDayCooldown() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 6)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz, rng: &rng)
        let today = try DayService.quests(on: friday, in: ctx)
        let drawn = Set(today.compactMap(\.templateID) + today.flatMap(\.trivialTemplateIDs))
        let stamped = try Sampling.activeTemplates(ctx).filter { $0.lastServedDayKey == friday }
        #expect(Set(stamped.map(\.id)) == drawn)

        var rng2 = SeededRNG(seed: 6)
        try DayService.ensureToday(ctx, now: Fixtures.date(saturday), in: tz, rng: &rng2)
        let next = try DayService.quests(on: saturday, in: ctx)
        let tomorrow = Set(next.compactMap(\.templateID) + next.flatMap(\.trivialTemplateIDs))
        #expect(tomorrow.intersection(drawn).isEmpty)
    }

    @Test func weekendOnlyQuestsNeverLandOnAWeekday() throws {
        let ctx = try Fixtures.context()
        for i in 0..<8 { Fixtures.quest(ctx, "weekend hike \(i)", .hard, weekendOnly: true) }
        Fixtures.quest(ctx, "weekday hard", .hard)
        for i in 0..<5 {
            Fixtures.quest(ctx, "easy \(i)", .easy)
            Fixtures.quest(ctx, "medium \(i)", .medium)
        }
        var rng = SeededRNG(seed: 12)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz, rng: &rng)
        let texts = try DayService.quests(on: friday, in: ctx).map(\.textSnapshot)
        #expect(!texts.contains { $0.hasPrefix("weekend hike") })
    }

    /// A T group takes one E slot: one `DailyQuest` holding three texts, not three rows.
    @Test func aVeryLowDayGetsOneTrivialSlot() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 3)
        let day = try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz,
                                             inputs: DayInputs(tier: .veryLow), rng: &rng)
        #expect(day.randomSlots == 3)
        let quests = try DayService.quests(on: friday, in: ctx)
        let groups = quests.filter(\.isTrivialGroup)
        #expect(quests.count == 3)
        #expect(groups.count == 1)
        #expect(groups[0].slot == .trivial)   // T is its own rung now, not an E slot
        #expect(groups[0].trivialGroup.count == 3)
        #expect(groups[0].trivialDone == [false, false, false])
        #expect(groups[0].trivialTemplateIDs.count == 3)
    }

    /// Fewer than three T items left: the slot quietly falls back to a normal E draw.
    @Test func trivialSlotFallsBackWhenThePoolIsThin() throws {
        let ctx = try Fixtures.context()
        Fixtures.quest(ctx, "floss", .trivial)
        for i in 0..<5 { Fixtures.quest(ctx, "easy \(i)", .easy) }
        var rng = SeededRNG(seed: 8)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz,
                                   inputs: DayInputs(tier: .veryLow), rng: &rng)
        let quests = try DayService.quests(on: friday, in: ctx)
        #expect(quests.allSatisfy { !$0.isTrivialGroup })
        #expect(quests.count == 3)
    }

    // MARK: catch-up

    /// The range is `[last processed … yesterday]`. Both ends matter: 09-15 was generated but the
    /// day ran out before anything judged it, and 09-18 is today — it isn't over, so it isn't
    /// settled. Getting this wrong means Stage 2 penalises routines that are still due later today.
    @Test func catchUpVisitsEveryMissedDayInOrder() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 1)
        try DayService.ensureToday(ctx, now: Fixtures.date("2026-09-15"), in: tz, rng: &rng)

        var settled: [String] = []
        try DayService.ensureToday(ctx, now: Fixtures.date("2026-09-18"), in: tz, rng: &rng,
                                   settle: { day, _ in settled.append(day) })
        #expect(settled == ["2026-09-15", "2026-09-16", "2026-09-17"])
        // Only today is generated; the days that were slept through stay empty.
        #expect(try DayService.quests(on: "2026-09-16", in: ctx).isEmpty)
        #expect(try DayService.quests(on: "2026-09-18", in: ctx).count == 3)
    }

    /// Opening the app tomorrow settles today — and today only once, not again the day after.
    @Test func eachDayIsSettledExactlyOnceTheDayAfter() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 1)
        var settled: [String] = []
        let settle: (String, ModelContext) throws -> Void = { day, _ in settled.append(day) }

        for day in ["2026-09-15", "2026-09-16", "2026-09-17", "2026-09-18"] {
            try DayService.ensureToday(ctx, now: Fixtures.date(day), in: tz, rng: &rng, settle: settle)
        }
        #expect(settled == ["2026-09-15", "2026-09-16", "2026-09-17"])
    }

    /// Opening the app twice on the same day must not settle yesterday twice.
    @Test func reopeningTheSameDaySettlesNothingExtra() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 1)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday, hour: 7), in: tz, rng: &rng)

        var settled: [String] = []
        try DayService.ensureToday(ctx, now: Fixtures.date(saturday, hour: 8), in: tz, rng: &rng,
                                   settle: { day, _ in settled.append(day) })
        #expect(settled == [friday])
        settled = []
        try DayService.ensureToday(ctx, now: Fixtures.date(saturday, hour: 22), in: tz, rng: &rng,
                                   settle: { day, _ in settled.append(day) })
        #expect(settled.isEmpty)
    }

    @Test func firstEverLaunchSettlesNothing() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 1)
        var settled: [String] = []
        try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz, rng: &rng,
                                   settle: { day, _ in settled.append(day) })
        #expect(settled.isEmpty)
    }

    @Test func aSecondCallTheSameDaySettlesNothingAgain() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 1)
        try DayService.ensureToday(ctx, now: Fixtures.date("2026-09-15"), in: tz, rng: &rng)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday, hour: 7), in: tz, rng: &rng)

        var settled: [String] = []
        try DayService.ensureToday(ctx, now: Fixtures.date(friday, hour: 22), in: tz, rng: &rng,
                                   settle: { day, _ in settled.append(day) })
        #expect(settled.isEmpty)
    }

    /// Midnight: the same instant is a different day either side of it, and the day key is what
    /// decides — never the `Date`.
    @Test func crossingMidnightGeneratesTheNextDay() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 1)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday, hour: 23), in: tz, rng: &rng)
        try DayService.ensureToday(ctx, now: Fixtures.date(saturday, hour: 0), in: tz, rng: &rng)
        #expect(try ctx.fetch(FetchDescriptor<DailyContext>()).map(\.dayKey).sorted() == [friday, saturday])
    }

    // MARK: hidden

    @Test func hiddenUnlocksOnlyAfterEveryRandomSlotIsDone() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 21)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz, rng: &rng)
        #expect(try !DayService.hiddenUnlocked(on: friday, in: ctx))
        #expect(try DayService.drawHidden(ctx, on: friday, in: tz, rng: &rng) == nil)

        for quest in try DayService.quests(on: friday, in: ctx) {
            quest.trivialDone = quest.trivialDone.map { _ in true }
            try Completion.complete(quest, tier: .normal, in: ctx,
                                    now: Fixtures.date(friday, hour: 20), rng: &rng)
        }
        #expect(try DayService.hiddenUnlocked(on: friday, in: ctx))

        let hidden = try DayService.drawHidden(ctx, on: friday, in: tz, rng: &rng)
        #expect(hidden?.isHiddenSlot == true)
        // Once drawn it isn't drawn again, and it doesn't re-lock the day.
        #expect(try DayService.drawHidden(ctx, on: friday, in: tz, rng: &rng) == nil)
    }

    @Test func anIncompleteRoutineKeepsHiddenLocked() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 21)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz, rng: &rng)
        let occurrence = RoutineOccurrence()
        occurrence.dueDayKey = friday
        occurrence.textSnapshot = "take out the trash"
        ctx.insert(occurrence)
        for quest in try DayService.quests(on: friday, in: ctx) {
            quest.trivialDone = quest.trivialDone.map { _ in true }
            try Completion.complete(quest, tier: .normal, in: ctx, rng: &rng)
        }
        #expect(try !DayService.hiddenUnlocked(on: friday, in: ctx))

        occurrence.completedDayKey = friday
        try ctx.save()
        #expect(try DayService.hiddenUnlocked(on: friday, in: ctx))
    }

    /// A `counts_for_clear = false` routine (the check-in kind) is recorded but never gates the
    /// day — otherwise forgetting to log "went to the office" would lock hidden out forever.
    @Test func aCheckInRoutineDoesNotGateHidden() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 21)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz, rng: &rng)
        Fixtures.occurrence(ctx, "go to the office", due: friday, countsForClear: false)
        Fixtures.occurrence(ctx, "take out the trash", due: friday, completed: friday)
        for quest in try DayService.quests(on: friday, in: ctx) {
            quest.trivialDone = quest.trivialDone.map { _ in true }
            try Completion.complete(quest, tier: .normal, in: ctx, rng: &rng)
        }
        #expect(try DayService.hiddenUnlocked(on: friday, in: ctx))
    }

    /// Flexible only moves the *penalty* to Sunday; the day it is due, it still has to be done for
    /// that day's full clear. Moving it to a later day costs that day's hidden quest.
    @Test func aFlexibleRoutineDueTodayGatesHidden() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        let r = RoutineTask(); r.text = "Workout: running"; r.spec = "FRI"
        r.flexibleWithinWeek = true; r.basePoints = 25
        ctx.insert(r)
        var rng = SeededRNG(seed: 21)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz, rng: &rng)
        for quest in try DayService.quests(on: friday, in: ctx) {
            quest.trivialDone = quest.trivialDone.map { _ in true }
            try Completion.complete(quest, tier: .normal, in: ctx, rng: &rng)
        }
        #expect(try !DayService.hiddenUnlocked(on: friday, in: ctx))

        let occurrence = try #require(try DayService.occurrences(dueOn: friday, in: ctx).first)
        try Completion.completeRoutine(occurrence, on: friday, tier: .normal, in: ctx, timeZone: tz)
        #expect(try DayService.hiddenUnlocked(on: friday, in: ctx))
    }

    // MARK: parameterized templates

    /// The variant is drawn once, at generation, and snapshotted — history keeps the prompt you
    /// actually got, and the template's own wording stays the row's identity.
    @Test func aParameterizedTemplateSnapshotsOneVariant() throws {
        let prompts = ["What drained me", "What I avoided", "Who surprised me"]
        for seed in UInt64(0)..<12 {
            let ctx = try Fixtures.context()
            Fixtures.quest(ctx, "Write a journal entry", .easy, variants: prompts)
            var rng = SeededRNG(seed: seed)
            try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz,
                                       inputs: DayInputs(tier: .low), rng: &rng)
            let quest = try #require(try DayService.quests(on: friday, in: ctx).first)
            #expect(quest.textSnapshot == "Write a journal entry")
            #expect(prompts.contains(try #require(quest.variantSnapshot)))
        }
    }

    @Test func aTemplateWithoutVariantsSnapshotsNone() throws {
        let ctx = try Fixtures.context()
        Fixtures.quest(ctx, "Go for a walk", .easy)
        var rng = SeededRNG(seed: 2)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz,
                                   inputs: DayInputs(tier: .low), rng: &rng)
        let quest = try #require(try DayService.quests(on: friday, in: ctx).first)
        #expect(quest.variantSnapshot == nil)
    }

    /// The T group carries one variant slot per item, parallel to the texts.
    @Test func theTrivialGroupCarriesAVariantPerItem() throws {
        let ctx = try Fixtures.context()
        Fixtures.quest(ctx, "floss", .trivial, variants: ["upper", "lower"])
        Fixtures.quest(ctx, "water the plants", .trivial)
        Fixtures.quest(ctx, "wipe the desk", .trivial)
        for i in 0..<4 { Fixtures.quest(ctx, "easy \(i)", .easy) }
        var rng = SeededRNG(seed: 5)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz,
                                   inputs: DayInputs(tier: .veryLow), rng: &rng)
        let group = try #require(try DayService.quests(on: friday, in: ctx).first(where: \.isTrivialGroup))
        #expect(group.trivialVariants.count == group.trivialGroup.count)
        let flossIndex = try #require(group.trivialGroup.firstIndex(of: "floss"))
        #expect(["upper", "lower"].contains(group.trivialVariants[flossIndex]))
    }
}
