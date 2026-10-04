import Foundation
import Testing
@testable import LifeRPGCore

struct JournalTimingTests {
    private let tz = Fixtures.tokyo

    private func evening(hour: Int, minute: Int, day: String = "2026-09-18", in zone: TimeZone? = nil) -> Bool {
        var c = DateComponents()
        let parts = day.split(separator: "-").map { Int($0)! }
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]; c.hour = hour; c.minute = minute
        let zone = zone ?? tz
        let date = LifeCalendar.gregorian(zone).date(from: c)!
        return JournalTiming.isEvening(at: date, timeZone: zone)
    }

    @Test func eveningStartsAtSixPM() {
        #expect(JournalTiming.eveningStartHour == 18)
    }

    @Test func theBoundariesAreFiveAndSix() {
        #expect(evening(hour: 4, minute: 59))
        #expect(!evening(hour: 5, minute: 0))
        #expect(!evening(hour: 17, minute: 59))
        #expect(evening(hour: 18, minute: 0))
    }

    @Test func lateNightAndPastMidnightAreStillTheEvening() {
        #expect(evening(hour: 23, minute: 30))
        #expect(evening(hour: 0, minute: 0))
        #expect(evening(hour: 2, minute: 15))
    }

    @Test func middayAndMorningAreNot() {
        #expect(!evening(hour: 9, minute: 0))
        #expect(!evening(hour: 12, minute: 0))
    }

    @Test func theHourIsReadInTheGivenTimeZone() {
        let instant = Fixtures.date("2026-09-18", hour: 19, in: Fixtures.tokyo)
        let newYork = TimeZone(identifier: "America/New_York")!
        #expect(JournalTiming.isEvening(at: instant, timeZone: Fixtures.tokyo))
        // 19:00 in Tokyo is 06:00 in New York.
        #expect(!JournalTiming.isEvening(at: instant, timeZone: newYork))
    }
}
