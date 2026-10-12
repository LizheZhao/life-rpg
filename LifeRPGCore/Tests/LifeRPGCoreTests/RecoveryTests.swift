import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// A recovery stretch set by hand (`PLAN.md` §5, "Recovery"): T, E, E random slots, nothing
/// heavier than easy among the routines, no new epic, and no penalty for a day inside it.
/// 2026-W39: Mon 21 … Sun 27.
struct RecoveryTests {
    private let tz = Fixtures.tokyo
    private let sun = "2026-09-20", mon = "2026-09-21", tue = "2026-09-22", wed = "2026-09-23",
                thu = "2026-09-24", fri = "2026-09-25"
    private var period: RecoveryPeriod { RecoveryPeriod(firstDayKey: mon, lastDayKey: thu) }

    @discardableResult
    private func routine(_ ctx: ModelContext, _ text: String, _ difficulty: Difficulty,
                         spec: String = "MON", light: [(String, Difficulty)] = []) -> RoutineTask {
        let r = RoutineTask()
        r.text = text; r.spec = spec; r.difficulty = difficulty; r.basePoints = 30
        ctx.insert(r)
        for (text, d) in light {
            let v = RoutineTask()
            v.text = text; v.difficulty = d; v.basePoints = 10
            ctx.insert(v)
            r.downgradeIDs.append(v.id)
        }
        return r
    }

    private func recovering(_ dayKey: String, measured: Tier = .high) -> DayInputs {
        Recovery.applied(period, to: DayInputs(tier: measured), on: dayKey)
    }

    @discardableResult
    private func open(_ ctx: ModelContext, _ dayKey: String, _ inputs: DayInputs) throws -> DailyContext {
        var rng = SeededRNG(seed: 4)
        return try DayService.ensureToday(ctx, now: Fixtures.date(dayKey), in: tz, inputs: inputs, rng: &rng)
    }

    private func regular(_ ctx: ModelContext, _ dayKey: String) throws -> [String] {
        try DayService.quests(on: dayKey, in: ctx)
            .filter { !$0.replaced && !$0.isHiddenSlot && $0.slot != .epic }
            .map(\.slot.code).sorted()
    }

    // MARK: the day's shape

    @Test func insideThePeriodTheTierIsVeryLowWhateverTheBodySays() {
        #expect(recovering(mon).tier == .veryLow)
        #expect(recovering(thu).tier == .veryLow)
        #expect(recovering(fri).tier == .high)
        #expect(recovering(sun).tier == .high)
        #expect(Recovery.applied(nil, to: DayInputs(tier: .high), on: mon).tier == .high)
    }

    @Test func aRecoveryDayDrawsTrivialEasyEasy() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        let day = try open(ctx, mon, recovering(mon))
        #expect(day.isRecovery)
        #expect(day.tier == .veryLow)
        #expect(try regular(ctx, mon) == ["E", "E", "T"])
    }

    @Test func aDayAfterThePeriodIsOrdinary() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        let day = try open(ctx, fri, recovering(fri, measured: .normal))
        #expect(!day.isRecovery)
        #expect(try regular(ctx, fri) == ["E", "H", "M"])
    }

    /// Easy stays, a heavy one with an easy light version goes onto it, and a heavy one with
    /// nothing easy on offer isn't scheduled — so it can't be overdue and doesn't shrink the draw.
    @Test func routinesHeavierThanEasyAreLightenedOrRested() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        routine(ctx, "Stretch", .easy)
        routine(ctx, "Workout: running", .medium, light: [("Incline walk, 30 minutes", .easy)])
        routine(ctx, "Strength session", .hard)
        routine(ctx, "Long run", .hard, light: [("Tempo run", .medium)])

        let day = try open(ctx, mon, recovering(mon))
        let occurrences = try DayService.occurrences(dueOn: mon, in: ctx)
        #expect(occurrences.map(\.displayText).sorted() == ["Incline walk, 30 minutes", "Stretch"])
        #expect(day.routineLoad == 2)
        #expect(day.randomSlots == 3)
    }

    @Test func outsideThePeriodEveryRoutineIsScheduled() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        routine(ctx, "Strength session", .hard, spec: "FRI")
        try open(ctx, fri, recovering(fri, measured: .normal))
        #expect(try DayService.occurrences(dueOn: fri, in: ctx).map(\.displayText) == ["Strength session"])
    }

    // MARK: epic

    @Test func noEpicIsDrawnDuringRecovery() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        Fixtures.quest(ctx, "epic #0", .epic)
        try open(ctx, mon, recovering(mon))
        try open(ctx, tue, recovering(tue))
        #expect(try ctx.fetch(FetchDescriptor<DailyQuest>()).filter { $0.slot == .epic }.isEmpty)
    }

    @Test func anEpicAlreadyRunningIsKept() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        Fixtures.quest(ctx, "epic #0", .epic)
        let late = RecoveryPeriod(firstDayKey: tue, lastDayKey: thu)
        try open(ctx, mon, Recovery.applied(late, to: DayInputs(), on: mon))
        try open(ctx, tue, Recovery.applied(late, to: DayInputs(), on: tue))
        let epics = try ctx.fetch(FetchDescriptor<DailyQuest>()).filter { $0.slot == .epic }
        #expect(epics.map(\.dayKey) == [mon])
        #expect(try Epic.current(on: tue, in: ctx, timeZone: tz) != nil)
    }

    // MARK: judging

    /// Base 50 would cost −25 / −38 / −50 (`OverdueTests`); inside recovery it costs nothing, and
    /// the round still ends on day 4.
    @Test func aRecoveryDayChargesNothingButTheRoundStillEnds() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx, "Clean the apartment", .easy)
        r.basePoints = 50
        let o = RoutineOccurrence(routine: r, dueDayKey: mon, weekKey: "2026-W39")
        ctx.insert(o)
        for day in [mon, tue, wed] {
            try Overdue.settle(day, in: ctx, timeZone: tz, recovery: period)
        }
        try ctx.save()
        let ledger = try ctx.fetch(FetchDescriptor<LedgerEntry>())
        #expect(ledger.filter { $0.kind == "penalty" }.isEmpty)
        #expect(o.penaltyApplied == 0)
        #expect(o.skipped)
        #expect(ledger.filter { $0.kind == "skip" }.map(\.dayKey) == [thu])
    }

    @Test func aDayRecordedAsRecoveryIsJudgedAsOneAfterThePeriodIsGone() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx, "Clean the apartment", .easy)
        r.basePoints = 50
        ctx.insert(RoutineOccurrence(routine: r, dueDayKey: mon, weekKey: "2026-W39"))
        let day = DailyContext()
        day.dayKey = mon
        day.isRecovery = true
        ctx.insert(day)
        try Overdue.settle(mon, in: ctx, timeZone: tz)
        try Overdue.settle(tue, in: ctx, timeZone: tz)
        let penalties = try ctx.fetch(FetchDescriptor<LedgerEntry>()).filter { $0.kind == "penalty" }
        #expect(penalties.map(\.points) == [-38])
        #expect(penalties.map(\.dayKey) == [tue])
    }

    @Test func sundaysShortfallIsWaivedOnARecoverySunday() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx, "Yoga", .easy, spec: "MON,WED")
        r.flexibleWithinWeek = true
        r.weeklyTarget = 2
        r.basePoints = 30
        ctx.insert(RoutineOccurrence(routine: r, dueDayKey: mon, weekKey: "2026-W39"))
        let sunday = "2026-09-27"
        try Overdue.settle(sunday, in: ctx, timeZone: tz,
                           recovery: RecoveryPeriod(firstDayKey: mon, lastDayKey: sunday))
        #expect(try ctx.fetch(FetchDescriptor<LedgerEntry>()).filter { $0.kind == "penalty" }.isEmpty)
    }

    /// The bill the today page shows before Sunday is the same rule: none while Sunday is covered.
    @Test func theSundayBillPreviewIsWaivedToo() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx, "Yoga", .easy, spec: "MON,WED")
        r.flexibleWithinWeek = true
        r.weeklyTarget = 2
        r.basePoints = 30
        ctx.insert(RoutineOccurrence(routine: r, dueDayKey: mon, weekKey: "2026-W39"))
        let routines = try ctx.fetch(FetchDescriptor<RoutineTask>())
        let occurrences = try ctx.fetch(FetchDescriptor<RoutineOccurrence>())
        #expect(Overdue.weekly(routines, occurrences: occurrences, weekKey: "2026-W39", in: tz).total == 15)
        #expect(Overdue.weekly(routines, occurrences: occurrences, weekKey: "2026-W39",
                               recovery: period, in: tz).total == 15)       // ends Thursday
        let throughSunday = RecoveryPeriod(firstDayKey: mon, lastDayKey: "2026-09-27")
        let waived = Overdue.weekly(routines, occurrences: occurrences, weekKey: "2026-W39",
                                    recovery: throughSunday, in: tz)
        #expect(waived.total == 0)
        #expect(waived.closing.count == 1)
    }

    /// The app opened through the whole stretch: catch-up judges each day with the period.
    @Test func catchUpPassesThePeriodToTheSettlement() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        routine(ctx, "Stretch", .easy, spec: "SUN")
        try open(ctx, sun, DayInputs())
        try open(ctx, wed, recovering(wed))
        let penalties = try ctx.fetch(FetchDescriptor<LedgerEntry>()).filter { $0.kind == "penalty" }
        // Sunday was an ordinary day; Monday and Tuesday fell inside the period and cost nothing.
        #expect(penalties.map(\.dayKey) == [sun])
    }

    // MARK: turning it on for a day already on screen

    @Test func turningItOnReplansTodayWithoutTouchingWhatIsDone() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        routine(ctx, "Workout: running", .medium, light: [("Incline walk, 30 minutes", .easy)])
        routine(ctx, "Strength session", .hard)
        routine(ctx, "Stretch", .easy)
        try open(ctx, mon, DayInputs(tier: .normal))
        #expect(try regular(ctx, mon) == ["E", "M"])         // three routines leave two slots

        let inputs = recovering(mon)
        let change = try #require(try Replan.preview(ctx, on: mon, inputs: inputs, in: tz))
        #expect(change.toRecovery && !change.fromRecovery)
        #expect(change.restedRoutines == 1)
        #expect(change.adjustedRoutines == 1)

        var rng = SeededRNG(seed: 9)
        try Replan.apply(ctx, on: mon, inputs: inputs, in: tz, rng: &rng)
        #expect(try DayService.dailyContext(for: mon, in: ctx)?.isRecovery == true)
        #expect(try regular(ctx, mon) == ["E", "T"])

        let os = try DayService.occurrences(dueOn: mon, in: ctx)
        let strength = try #require(os.first { $0.textSnapshot == "Strength session" })
        #expect(strength.skipped)
        #expect(try Fixtures.missed(ctx).isEmpty)            // rested, not missed
        let running = try #require(os.first { $0.textSnapshot == "Workout: running" })
        #expect(running.displayText == "Incline walk, 30 minutes")
        #expect(os.first { $0.textSnapshot == "Stretch" }?.skipped == false)

        #expect(try Replan.preview(ctx, on: mon, inputs: inputs, in: tz) == nil)
    }

    @Test func aVeryLowDayStillAsksWhenRecoveryStarts() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        try open(ctx, mon, DayInputs(tier: .veryLow))
        let change = try #require(try Replan.preview(ctx, on: mon, inputs: recovering(mon), in: tz))
        #expect(change.droppedQuests == 0 && change.newQuests == 0)
        #expect(change.toRecovery)
    }

    // MARK: backup

    @Test func theBackupCarriesTheRecoveryMark() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        try open(ctx, mon, recovering(mon))
        let s = try JSONExport.snapshot(ctx)
        #expect(s.dailyContexts.map(\.isRecovery) == [true])
    }
}
