import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// Energy score, readiness and tier (`PLAN.md` §5). Expected values are worked out by hand from the
/// formula in PLAN and written as literals — they are not recomputed with the code under test.
///
/// Baseline used throughout unless stated: HRV 50 ms, sleep 7.5 h, resting HR 55 bpm.
struct EnergyTests {
    private let tz = Fixtures.tokyo
    private let today = "2026-09-21"

    private let base = Energy.Baseline(hrv: 50, sleepHours: 7.5, restingHR: 55)

    private func reading(_ hrv: Double?, _ sleep: Double?, _ rhr: Double?,
                         on dayKey: String = "2026-09-21") -> HealthReading {
        HealthReading(dayKey: dayKey, hrv: hrv, sleepHours: sleep, restingHR: rhr)
    }

    /// `n` days of identical history ending yesterday.
    private func history(_ n: Int, hrv: Double? = 50, sleep: Double? = 7.5, rhr: Double? = 55) -> [HealthReading] {
        (1...n).map { reading(hrv, sleep, rhr, on: DayKey.adding(-$0, to: today, in: tz)!) }
    }

    // MARK: median

    @Test func medianOfOddAndEvenCounts() {
        #expect(Energy.median([3, 1, 2]) == 2)
        #expect(Energy.median([4, 1, 3, 2]) == 2.5)
        #expect(Energy.median([]) == nil)
    }

    // MARK: score

    @Test func aDayAtBaselineIsOne() throws {
        let e = try #require(Energy.score(reading(50, 7.5, 55), baseline: base))
        #expect(abs(e - 1.0) < 1e-9)
        #expect(Energy.readiness(e) == 75)
        #expect(Energy.tier(e) == .normal)
    }

    /// Stage 3's "done when": a bad night on its own drops the tier.
    /// sleep 5.25 / 7.5 = 0.7 → E = 0.45 + 0.35 × 0.7 + 0.20 = 0.895 → low; readiness 67.125 → 67.
    @Test func aShortNightAloneDropsTheTierToLow() throws {
        let e = try #require(Energy.score(reading(50, 5.25, 55), baseline: base))
        #expect(abs(e - 0.895) < 1e-9)
        #expect(Energy.tier(e) == .low)
        #expect(Energy.readiness(e) == 67)
    }

    /// hrv 40 / 50 = 0.8, sleep 4.5 / 7.5 = 0.6 → E = 0.36 + 0.21 + 0.20 = 0.77 → very low;
    /// readiness 57.75 → 58.
    @Test func lowHRVAndShortSleepIsVeryLow() throws {
        let e = try #require(Energy.score(reading(40, 4.5, 55), baseline: base))
        #expect(abs(e - 0.77) < 1e-9)
        #expect(Energy.tier(e) == .veryLow)
        #expect(Energy.readiness(e) == 58)
    }

    /// Resting HR is inverse: 55 / 50 = 1.1. E = 0.45 + 0.35 + 0.22 = 1.02 → still normal.
    @Test func aLowerRestingHRRaisesTheScore() throws {
        let e = try #require(Energy.score(reading(50, 7.5, 50), baseline: base))
        #expect(abs(e - 1.02) < 1e-9)
    }

    /// hrv 100 / 50 = 2.0 → clamped 1.4; sleep 2 / 7.5 = 0.267 → clamped 0.6.
    /// E = 0.63 + 0.21 + 0.20 = 1.04 → normal; readiness 78.
    @Test func eachRatioIsClampedSoOneOutlierCantDominate() throws {
        let e = try #require(Energy.score(reading(100, 2, 55), baseline: base))
        #expect(abs(e - 1.04) < 1e-9)
        #expect(Energy.tier(e) == .normal)
        #expect(Energy.readiness(e) == 78)
    }

    /// Every ratio at the 1.4 ceiling: E = 1.4, 105 → readiness capped at 100.
    @Test func readinessIsCappedAt100() throws {
        let e = try #require(Energy.score(reading(100, 15, 20), baseline: base))
        #expect(abs(e - 1.4) < 1e-9)
        #expect(Energy.readiness(e) == 100)
        #expect(Energy.tier(e) == .high)
    }

    @Test func readinessClampsBothEnds() {
        #expect(Energy.readiness(0.2) == 35)       // 15 → 35
        #expect(Energy.readiness(2.0) == 100)      // 150 → 100
        #expect(Energy.readiness(0.9) == 68)       // 67.5 rounds half up
    }

    /// No HRV (watch not worn): the remaining weights are renormalised.
    /// (0.35 × 0.7 + 0.20 × 1.0) / 0.55 = 0.445 / 0.55 = 0.80909… → very low; readiness 60.68 → 61.
    @Test func aMissingMetricRenormalisesTheOthers() throws {
        let e = try #require(Energy.score(reading(nil, 5.25, 55), baseline: base))
        #expect(abs(e - 0.445 / 0.55) < 1e-9)
        #expect(Energy.tier(e) == .veryLow)
        #expect(Energy.readiness(e) == 61)
    }

    /// A metric counts only when both today's value and its baseline exist.
    @Test func aMetricWithoutBaselineIsDroppedToo() throws {
        let noSleepBase = Energy.Baseline(hrv: 50, sleepHours: nil, restingHR: 55)
        // sleep would be terrible, but without a baseline it can't be judged: hrv + rhr at 1.0.
        let e = try #require(Energy.score(reading(50, 3, 55), baseline: noSleepBase))
        #expect(abs(e - 1.0) < 1e-9)
    }

    @Test func noUsableMetricMeansNoScore() {
        #expect(Energy.score(reading(nil, nil, nil), baseline: base) == nil)
        #expect(Energy.score(reading(50, 7.5, 55), baseline: .init(hrv: nil, sleepHours: nil, restingHR: nil)) == nil)
        // Zero or negative is a bad sample, not a value.
        #expect(Energy.score(reading(0, 0, 0), baseline: base) == nil)
    }

    // MARK: tier thresholds

    @Test func thresholds() {
        #expect(Energy.tier(0.8499) == .veryLow)
        #expect(Energy.tier(0.85) == .low)
        #expect(Energy.tier(0.9199) == .low)
        #expect(Energy.tier(0.92) == .normal)
        #expect(Energy.tier(1.06) == .normal)
        #expect(Energy.tier(1.0601) == .high)
    }

    // MARK: baseline

    @Test func baselineIsTheMedianOfThePast28DaysExcludingToday() {
        var h = history(28)
        h[0].hrv = 90                                      // yesterday: an outlier the median ignores
        h.append(reading(10, 1, 99))                       // today: never part of its own baseline
        h.append(reading(10, 1, 99, on: DayKey.adding(-29, to: today, in: tz)!))  // outside the window
        let b = Energy.baseline(h, before: today, in: tz)
        #expect(b.hrv == 50)
        #expect(b.sleepHours == 7.5)
        #expect(b.restingHR == 55)
    }

    @Test func aMetricNeedsSevenDaysOfHistoryForABaseline() {
        let six = Energy.baseline(history(6), before: today, in: tz)
        #expect(six.hrv == nil && six.sleepHours == nil && six.restingHR == nil)
        let seven = Energy.baseline(history(7), before: today, in: tz)
        #expect(seven.hrv == 50)
    }

    @Test func missingDaysDontCountTowardTheSeven() {
        // 10 days, but HRV only on 5 of them.
        var h = history(10)
        for i in 5..<10 { h[i].hrv = nil }
        let b = Energy.baseline(h, before: today, in: tz)
        #expect(b.hrv == nil)
        #expect(b.sleepHours == 7.5)
    }

    // MARK: inputs (the whole path)

    @Test func inputsFromABadNight() {
        let i = Energy.inputs(today: reading(50, 5.25, 55), history: history(28), cycleDay: nil, in: tz)
        #expect(i.tier == .low)
        #expect(i.readiness == 67)
        #expect(abs(i.energy - 0.895) < 1e-9)
        #expect(i.hrv == 50 && i.sleepHours == 5.25 && i.restingHR == 55)
        #expect(!i.onCycle)
    }

    /// First launch before any backfill, or no watch at all: the day stays normal.
    @Test func noDataFallsBackToNormal() {
        let i = Energy.inputs(today: reading(nil, nil, nil), history: [], cycleDay: nil, in: tz)
        #expect(i.tier == .normal)
        #expect(i.energy == 1.0)
        #expect(i.readiness == 75)
    }

    // MARK: cycle

    /// `PLAN.md` §5: a cycle day is capped at normal, but not pushed down.
    @Test func aCycleDayCapsHighAtNormal() {
        // Day 4 on: capped at normal, never pushed down (PLAN §5).
        #expect(Energy.cap(.high, cycleDay: 5) == .normal)
        #expect(Energy.cap(.normal, cycleDay: 5) == .normal)
        #expect(Energy.cap(.low, cycleDay: 5) == .low)
        #expect(Energy.cap(.veryLow, cycleDay: 5) == .veryLow)
        #expect(Energy.cap(.high, cycleDay: nil) == .high)

        // The first three days are held down to low — that is the whole downgrade rule.
        for day in 1...3 {
            #expect(Energy.cap(.high, cycleDay: day) == .low)
            #expect(Energy.cap(.normal, cycleDay: day) == .low)
            #expect(Energy.cap(.low, cycleDay: day) == .low)
            #expect(Energy.cap(.veryLow, cycleDay: day) == .veryLow)   // never pushed up
        }
    }

    @Test func inputsOnACycleDay() {
        // Every ratio at the ceiling would be high; the cycle caps it. Readiness is not capped.
        let i = Energy.inputs(today: reading(100, 15, 20), history: history(28), cycleDay: 5, in: tz)
        #expect(i.tier == .normal)
        #expect(i.readiness == 100)
        #expect(i.onCycle)
    }

    /// End to end: the inputs land on the day, and a low tier actually changes what is drawn.
    @Test func aBadNightReachesTheGeneratedDay() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        let inputs = Energy.inputs(today: reading(50, 5.25, 55), history: history(28), cycleDay: nil, in: tz)
        var rng = SeededRNG(seed: 3)
        let day = try DayService.ensureToday(ctx, now: Fixtures.date(today), in: tz, inputs: inputs, rng: &rng)
        #expect(day.tier == .low)
        #expect(day.readiness == 67)
        #expect(day.sleepHours == 5.25 && day.hrv == 50 && day.restingHR == 55)
        let slots = try DayService.quests(on: today, in: ctx).map(\.slot)
        #expect(!slots.contains(.hard))                     // low = 2 E + 1 M
    }
}
