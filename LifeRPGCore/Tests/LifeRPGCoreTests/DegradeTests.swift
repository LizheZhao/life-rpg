import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// `degraded_text` (`PLAN.md` §4): on a low-tier day a routine that has a light version is swapped
/// for it automatically, and still pays full points. Decided when the occurrence is created; the
/// original wording stays in `textSnapshot`, the light one sits beside it.
/// W38: Wed 2026-09-16, Fri 18, Sat 19.
struct DegradeTests {
    private let tz = Fixtures.tokyo
    private let wed = "2026-09-16", fri = "2026-09-18", sat = "2026-09-19"

    private func running(_ ctx: ModelContext, degraded: String? = "Incline walk, 30 minutes",
                         spec: String = "FRI", flexible: Bool = false) -> RoutineTask {
        let r = RoutineTask()
        r.text = "Workout: running"; r.spec = spec; r.basePoints = 25
        r.degradedText = degraded; r.flexibleWithinWeek = flexible
        ctx.insert(r)
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
            _ = running(ctx)
            let o = try #require(try generate(ctx, fri, tier: tier).first)
            #expect(o.usedDegraded)
            #expect(o.degradedTextSnapshot == "Incline walk, 30 minutes")
            #expect(o.textSnapshot == "Workout: running")         // the original is kept
            #expect(o.displayText == "Incline walk, 30 minutes")
        }
    }

    @Test func normalAndHighDaysKeepTheOriginal() throws {
        for tier in [Tier.normal, .high] {
            let ctx = try Fixtures.context()
            _ = running(ctx)
            let o = try #require(try generate(ctx, fri, tier: tier).first)
            #expect(!o.usedDegraded)
            #expect(o.degradedTextSnapshot == nil)
            #expect(o.displayText == "Workout: running")
        }
    }

    /// Only routines with a non-empty `degraded_text` degrade; blank counts as none.
    @Test func withoutALightVersionNothingChanges() throws {
        for text in [nil, "", "   "] as [String?] {
            let ctx = try Fixtures.context()
            _ = running(ctx, degraded: text)
            let o = try #require(try generate(ctx, fri, tier: .veryLow).first)
            #expect(!o.usedDegraded)
            #expect(o.degradedTextSnapshot == nil)
        }
    }

    /// Full points for the light version: 25 × 1.3 = 32.5 → 33 on a low day.
    @Test func theLightVersionPaysFull() throws {
        let ctx = try Fixtures.context()
        _ = running(ctx)
        let o = try #require(try generate(ctx, fri, tier: .low).first)
        #expect(try Completion.completeRoutine(o, on: fri, tier: .low, in: ctx, timeZone: tz) == 33)
    }

    /// Feeling up to it: the original can be picked instead, for the same points. `usedDegraded`
    /// records which version was actually done, so it can flip until the occurrence is closed.
    @Test func theOriginalCanBeChosenForTheSamePoints() throws {
        let ctx = try Fixtures.context()
        _ = running(ctx)
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

    @Test func nothingToChooseWithoutALightVersion() throws {
        let ctx = try Fixtures.context()
        _ = running(ctx)
        let o = try #require(try generate(ctx, fri, tier: .normal).first)
        #expect(throws: Degrade.Failure.noLightVersion) { try Degrade.choose(light: true, for: o, in: ctx) }
    }

    /// Decided once, when the occurrence is created: an overdue one from a normal day stays the
    /// original on a low day, and a light one stays light if the next day is normal.
    @Test func decidedAtCreation() throws {
        let ctx = try Fixtures.context()
        _ = running(ctx)
        let o = try #require(try generate(ctx, fri, tier: .normal).first)
        _ = try generate(ctx, sat, tier: .veryLow)
        #expect(!o.usedDegraded)
    }

    /// Done ahead on a low day: the occurrence it creates is the light version.
    @Test func doneAheadOnALowDayIsLight() throws {
        let ctx = try Fixtures.context()
        let r = running(ctx, spec: "SAT", flexible: true)
        try Completion.completeAhead(r, on: wed, tier: .veryLow, in: ctx, timeZone: tz)
        let o = try #require(try ctx.fetch(FetchDescriptor<RoutineOccurrence>()).first)
        #expect(o.usedDegraded)
        #expect(o.awardedPoints == 33)
        #expect(Degrade.text(for: r, tier: .veryLow) == "Incline walk, 30 minutes")
        #expect(Degrade.text(for: r, tier: .normal) == nil)
    }

    /// Done ahead there is no open occurrence to switch afterwards, so the choice is made when
    /// doing it: the original, for the same points, with the light version still on record.
    @Test func doneAheadCanBeTheOriginal() throws {
        let ctx = try Fixtures.context()
        let r = running(ctx, spec: "SAT", flexible: true)
        try Completion.completeAhead(r, on: wed, tier: .veryLow, light: false, in: ctx, timeZone: tz)
        let o = try #require(try ctx.fetch(FetchDescriptor<RoutineOccurrence>()).first)
        #expect(!o.usedDegraded)
        #expect(o.degradedTextSnapshot == "Incline walk, 30 minutes")
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
        _ = running(ctx)
        _ = try generate(ctx, fri, tier: .low)
        let o = try #require(try JSONExport.snapshot(ctx).routineOccurrences.first)
        #expect(o.usedDegraded)
        #expect(o.degradedText == "Incline walk, 30 minutes")
    }
}
