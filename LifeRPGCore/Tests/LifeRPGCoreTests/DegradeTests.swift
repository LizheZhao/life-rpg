import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// Downgrade versions (`PLAN.md` §4): on a low-tier day a routine that offers lighter versions is
/// swapped for one automatically. The version is a routine row of its own, so it pays its own
/// points and brings its own auto-verify rule. Decided when the occurrence is created; the
/// original wording stays in `textSnapshot`, the light one sits beside it.
/// W38: Wed 2026-09-16, Fri 18, Sat 19.
struct DegradeTests {
    private let tz = Fixtures.tokyo
    private let wed = "2026-09-16", fri = "2026-09-18", sat = "2026-09-19"

    /// "Workout: running" (25) with "Incline walk, 30 minutes" (10) as its downgrade version.
    @discardableResult
    private func running(_ ctx: ModelContext, downgrades: [String] = ["Incline walk, 30 minutes"],
                         spec: String = "FRI", flexible: Bool = false) -> RoutineTask {
        let r = RoutineTask()
        r.text = "Workout: running"; r.spec = spec; r.basePoints = 25
        r.flexibleWithinWeek = flexible
        ctx.insert(r)
        for text in downgrades {
            let light = RoutineTask()
            light.text = text; light.basePoints = 10; light.difficulty = .easy
            ctx.insert(light)
            r.downgradeIDs.append(light.id)
        }
        return r
    }

    private func generate(_ ctx: ModelContext, _ day: String, tier: Tier) throws -> [RoutineOccurrence] {
        var rng = SeededRNG(seed: 1)
        try DayService.ensureToday(ctx, now: Fixtures.date(day), in: tz,
                                   inputs: DayInputs(tier: tier), rng: &rng)
        return try DayService.occurrences(dueOn: day, in: ctx)
    }

    /// One rule for "a low day", shared by the 1.3× multiplier and the swap.
    @Test func lowMeansLowAndVeryLow() {
        #expect(Tier.veryLow.isLow)
        #expect(Tier.low.isLow)
        #expect(!Tier.normal.isLow)
        #expect(!Tier.high.isLow)
    }

    @Test func aLowDaySwapsInTheLightVersion() throws {
        for tier in [Tier.low, .veryLow] {
            let ctx = try Fixtures.context()
            running(ctx)
            let o = try #require(try generate(ctx, fri, tier: tier).first)
            #expect(o.usedDegraded)
            #expect(o.degradedTextSnapshot == "Incline walk, 30 minutes")
            #expect(o.degradedBasePoints == 10)
            #expect(o.textSnapshot == "Workout: running")         // the original is kept
            #expect(o.displayText == "Incline walk, 30 minutes")
        }
    }

    @Test func normalAndHighDaysKeepTheOriginal() throws {
        for tier in [Tier.normal, .high] {
            let ctx = try Fixtures.context()
            running(ctx)
            let o = try #require(try generate(ctx, fri, tier: tier).first)
            #expect(!o.usedDegraded)
            #expect(o.degradedTextSnapshot == nil)
            #expect(o.displayText == "Workout: running")
        }
    }

    @Test func withoutALightVersionNothingChanges() throws {
        let ctx = try Fixtures.context()
        running(ctx, downgrades: [])
        let o = try #require(try generate(ctx, fri, tier: .veryLow).first)
        #expect(!o.usedDegraded)
        #expect(o.degradedTextSnapshot == nil)
        #expect(o.effectiveBasePoints == 25)
    }

    /// A downgrade version is a routine row, but it never comes due by itself — it is only ever
    /// reached through the routine that offers it.
    @Test func downgradeVersionsAreNeverScheduled() throws {
        let ctx = try Fixtures.context()
        let r = running(ctx)
        let light = try #require(Degrade.versions(of: r, in: try ctx.fetch(FetchDescriptor<RoutineTask>())).first)
        light.spec = "FRI"                       // even given a frequency of its own
        let due = try generate(ctx, fri, tier: .normal)
        #expect(due.count == 1)
        #expect(due.first?.textSnapshot == "Workout: running")
    }

    /// The light version pays what the light version is worth: 10 × 1.3 = 13 on a low day, not
    /// the 33 the full session would have paid.
    @Test func theLightVersionPaysItsOwnPoints() throws {
        let ctx = try Fixtures.context()
        running(ctx)
        let o = try #require(try generate(ctx, fri, tier: .low).first)
        #expect(o.effectiveBasePoints == 10)
        #expect(try Completion.completeRoutine(o, on: fri, tier: .low, in: ctx, timeZone: tz) == 13)
    }

    /// Feeling up to it: the original can be picked instead — and then it pays the original's
    /// points. `usedDegraded` records which version was done, and can flip until it is closed.
    @Test func theOriginalCanBeChosenAndPaysTheOriginal() throws {
        let ctx = try Fixtures.context()
        running(ctx)
        let o = try #require(try generate(ctx, fri, tier: .low).first)
        try Degrade.choose(light: false, for: o, in: ctx)
        #expect(!o.usedDegraded)
        #expect(o.displayText == "Workout: running")
        #expect(o.degradedTextSnapshot == "Incline walk, 30 minutes")   // kept, so it can come back
        try Degrade.choose(light: true, for: o, in: ctx)
        #expect(o.usedDegraded)
        try Degrade.choose(light: false, for: o, in: ctx)
        #expect(try Completion.completeRoutine(o, on: fri, tier: .low, in: ctx, timeZone: tz) == 33)

        // Done is final: the version it was done in is part of the record.
        #expect(throws: Degrade.Failure.closed) { try Degrade.choose(light: true, for: o, in: ctx) }
        #expect(!o.usedDegraded)
    }

    /// The penalty follows the version the day actually asked for — a missed walk costs what a
    /// walk is worth (10 × 50% = 5 on round day 1), not what the session would have.
    @Test func thePenaltyFollowsTheChosenVersion() throws {
        let ctx = try Fixtures.context()
        running(ctx)
        let o = try #require(try generate(ctx, fri, tier: .low).first)
        try Overdue.settle(fri, in: ctx, timeZone: tz, now: Fixtures.date(fri, hour: 23))
        #expect(o.penaltyApplied == 5)
    }

    @Test func nothingToChooseWithoutALightVersion() throws {
        let ctx = try Fixtures.context()
        running(ctx)
        let o = try #require(try generate(ctx, fri, tier: .normal).first)
        #expect(throws: Degrade.Failure.noLightVersion) { try Degrade.choose(light: true, for: o, in: ctx) }
    }

    /// With several on offer, one is drawn — and on a strength routine every version on offer is
    /// a lighter *kind* of thing, which is what the cycle rule relies on.
    @Test func oneOfSeveralVersionsIsDrawn() throws {
        let ctx = try Fixtures.context()
        running(ctx, downgrades: ["Incline walk, 30 minutes", "Yoga, 20 minutes"])
        let o = try #require(try generate(ctx, fri, tier: .low).first)
        #expect(["Incline walk, 30 minutes", "Yoga, 20 minutes"].contains(o.degradedTextSnapshot ?? ""))
    }

    /// Decided once, when the occurrence is created: an overdue one from a normal day stays the
    /// original on a low day, and a light one stays light if the next day is normal.
    @Test func decidedAtCreation() throws {
        let ctx = try Fixtures.context()
        running(ctx)
        let o = try #require(try generate(ctx, fri, tier: .normal).first)
        _ = try generate(ctx, sat, tier: .veryLow)
        #expect(!o.usedDegraded)
    }

    /// Done ahead on a low day: the occurrence it creates is the light version, at the light
    /// version's points (10 × 1.3 = 13).
    @Test func doneAheadOnALowDayIsLight() throws {
        let ctx = try Fixtures.context()
        let r = running(ctx, spec: "SAT", flexible: true)
        try Completion.completeAhead(r, on: wed, tier: .veryLow, in: ctx, timeZone: tz)
        let o = try #require(try ctx.fetch(FetchDescriptor<RoutineOccurrence>()).first)
        #expect(o.usedDegraded)
        #expect(o.awardedPoints == 13)
    }

    /// Done ahead there is no open occurrence to switch afterwards, so the choice is made when
    /// doing it: the original, for the original's points, light version still on record.
    @Test func doneAheadCanBeTheOriginal() throws {
        let ctx = try Fixtures.context()
        let r = running(ctx, spec: "SAT", flexible: true)
        try Completion.completeAhead(r, on: wed, tier: .veryLow, light: false, in: ctx, timeZone: tz)
        let o = try #require(try ctx.fetch(FetchDescriptor<RoutineOccurrence>()).first)
        #expect(!o.usedDegraded)
        #expect(o.degradedTextSnapshot == nil)   // not chosen, so nothing was drawn
        #expect(o.displayText == "Workout: running")
        #expect(o.awardedPoints == 33)
    }

    /// Asking for the light version on a day that has none changes nothing.
    @Test func doneAheadLightWithoutOneIsTheOriginal() throws {
        let ctx = try Fixtures.context()
        let r = running(ctx, spec: "SAT", flexible: true)
        try Completion.completeAhead(r, on: wed, tier: .normal, light: true, in: ctx, timeZone: tz)
        let o = try #require(try ctx.fetch(FetchDescriptor<RoutineOccurrence>()).first)
        #expect(!o.usedDegraded)
        #expect(o.degradedTextSnapshot == nil)
    }

    /// An ad-hoc routine is chosen on purpose, on the spot: it is never swapped.
    @Test func adHocIsNeverSwapped() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        let r = running(ctx, spec: "MON")
        _ = try generate(ctx, fri, tier: .veryLow)
        let slot = try #require(try DayService.quests(on: fri, in: ctx).first)
        let o = try AdHoc.replace(slot, with: .routine(r), in: ctx, timeZone: tz)
        #expect(!o.usedDegraded)
        #expect(o.degradedTextSnapshot == nil)
    }

    @Test func exportCarriesTheLightVersion() throws {
        let ctx = try Fixtures.context()
        running(ctx)
        _ = try generate(ctx, fri, tier: .low)
        let o = try #require(try JSONExport.snapshot(ctx).routineOccurrences.first)
        #expect(o.usedDegraded)
        #expect(o.degradedText == "Incline walk, 30 minutes")
        #expect(o.degradedBasePoints == 10)
    }
}
