import Foundation
import Testing
@testable import LifeRPGCore

/// Which HealthKit samples make up a day's reading.
struct HealthBucketsTests {
    private let tz = Fixtures.tokyo
    private let sun = "2026-09-20", mon = "2026-09-21"

    private func at(_ day: String, _ hour: Int, _ minute: Int = 0) -> Date {
        Fixtures.date(day, hour: hour, in: tz).addingTimeInterval(Double(minute) * 60)
    }

    private func span(_ d1: String, _ h1: Int, _ d2: String, _ h2: Int, _ m2: Int = 0) -> DateInterval {
        DateInterval(start: at(d1, h1), end: at(d2, h2, m2))
    }

    @Test func theSleepWindowIsSixPMTheDayBeforeToNoon() throws {
        let w = try #require(HealthBuckets.sleepWindow(for: mon, in: tz))
        #expect(w.start == at(sun, 18))
        #expect(w.end == at(mon, 12))
    }

    @Test func overlappingSamplesAreCountedOnce() {
        // 23:00–07:00 from the Watch and 00:00–06:30 from Oura: the night is 8 h, not 14.5.
        let hours = HealthBuckets.unionHours([span(sun, 23, mon, 7), span(mon, 0, mon, 6, 30)])
        #expect(hours == 8)
    }

    @Test func separateStretchesAdd() {
        // 23:00–03:00, awake, 04:00–07:30 → 7.5 h.
        #expect(HealthBuckets.unionHours([span(sun, 23, mon, 3), span(mon, 4, mon, 7, 30)]) == 7.5)
    }

    @Test func sleepBelongsToTheMorningItEndsOn() {
        let asleep = [
            span(sun, 23, mon, 7),                  // Sunday night → Monday
            span(mon, 13, mon, 14),                 // Monday afternoon nap: ends after noon, not counted
            span("2026-09-19", 23, sun, 6),         // Saturday night → Sunday
        ]
        let r = HealthBuckets.reading(for: mon, asleep: asleep, hrv: [], restingHR: [], in: tz)
        #expect(r.sleepHours == 8)
        #expect(r.hrv == nil && r.restingHR == nil)
    }

    @Test func hrvIsTheOvernightMean() {
        let hrv = [
            TimedValue(date: at(sun, 23), value: 40),
            TimedValue(date: at(mon, 3), value: 60),
            TimedValue(date: at(mon, 15), value: 99),   // afternoon, outside the window
            TimedValue(date: at(sun, 10), value: 99),   // Sunday morning, outside
        ]
        let r = HealthBuckets.reading(for: mon, asleep: [], hrv: hrv, restingHR: [], in: tz)
        #expect(r.hrv == 50)
    }

    @Test func restingHRIsTheLatestSinceYesterday() {
        let rhr = [
            TimedValue(date: at("2026-09-19", 8), value: 70),   // two days ago
            TimedValue(date: at(sun, 8), value: 56),            // yesterday
            TimedValue(date: at(mon, 8), value: 54),            // this morning: latest
            TimedValue(date: at(mon, 14), value: 80),           // after noon
        ]
        #expect(HealthBuckets.reading(for: mon, asleep: [], hrv: [], restingHR: rhr, in: tz).restingHR == 54)
        #expect(HealthBuckets.reading(for: mon, asleep: [], hrv: [], restingHR: Array(rhr.prefix(2)),
                                      in: tz).restingHR == 56)
    }

    @Test func nothingInTheWindowIsNil() {
        let r = HealthBuckets.reading(for: mon, asleep: [], hrv: [], restingHR: [], in: tz)
        #expect(r == HealthReading(dayKey: mon))
    }
}
