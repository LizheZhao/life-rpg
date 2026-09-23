import Foundation
import Testing
@testable import LifeRPGCore

/// Which day of a period a day is, and what that does to the tier (`PLAN.md` §5).
struct CycleTests {
    private let tz = Fixtures.tokyo

    private func day(_ dayKey: String, _ flow: [String]) -> Int? {
        Cycle.day(on: dayKey, flowDays: Set(flow), in: tz)
    }

    @Test func countsFromTheDayTheRoundStarted() {
        let flow = ["2026-09-17", "2026-09-18", "2026-09-19", "2026-09-20"]
        #expect(day("2026-09-17", flow) == 1)
        #expect(day("2026-09-18", flow) == 2)
        #expect(day("2026-09-19", flow) == 3)
        #expect(day("2026-09-20", flow) == 4)
    }

    /// Calendar days from the start, not logged days: forgetting to log day 2 doesn't restart the
    /// count, and doesn't cost day 3 its downgrade either.
    @Test func aMissedLogInTheMiddleStillCounts() {
        let flow = ["2026-09-17", "2026-09-19"]
        #expect(day("2026-09-17", flow) == 1)
        #expect(day("2026-09-18", flow) == 2)   // nothing logged, still inside the round
        #expect(day("2026-09-19", flow) == 3)
    }

    /// A period logged once and then forgotten doesn't hold the tier down forever: without flow,
    /// the count stops after the first three days.
    @Test func withoutFlowItStopsAfterTheEarlyDays() {
        let flow = ["2026-09-17"]
        #expect(day("2026-09-19", flow) == 3)
        #expect(day("2026-09-20", flow) == nil)
    }

    @Test func aGapTooWideStartsANewRound() {
        let flow = ["2026-08-20", "2026-09-17", "2026-09-18"]
        #expect(day("2026-09-17", flow) == 1)
        #expect(day("2026-09-18", flow) == 2)
    }

    @Test func daysBeforeAnyFlowAreOutside() {
        #expect(day("2026-09-16", ["2026-09-17"]) == nil)
        #expect(day("2026-09-17", []) == nil)
    }

    /// The whole of the new rule: days 1–3 are a low day, which is what drops the hard slot,
    /// pays the 1.3× multiplier and swaps routines for their downgrade version.
    @Test func theFirstThreeDaysAreALowDay() {
        for cycleDay in 1...3 {
            #expect(Energy.cap(.high, cycleDay: cycleDay) == .low)
            #expect(Energy.cap(.normal, cycleDay: cycleDay).isLow)
        }
        #expect(Energy.cap(.normal, cycleDay: 4) == .normal)
    }

    /// A day with no usable body reading is `normal` — but a cycle day still applies to it.
    @Test func cycleAppliesEvenWithoutBodyData() {
        let reading = HealthReading(dayKey: "2026-09-17")
        let inputs = Energy.inputs(today: reading, history: [], cycleDay: 1, in: tz)
        #expect(inputs.tier == .low)
        #expect(inputs.onCycle)
        #expect(inputs.cycleDay == 1)

        let later = Energy.inputs(today: reading, history: [], cycleDay: 6, in: tz)
        #expect(later.tier == .normal)
        #expect(later.onCycle)
    }
}
