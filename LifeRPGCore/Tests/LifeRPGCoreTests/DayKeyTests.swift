import Foundation
import Testing
@testable import LifeRPGCore

/// Every test pins the time zone explicitly: the point of these helpers is that the keys don't
/// move with the device's region.
struct DayKeyTests {
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    private let newYork = TimeZone(identifier: "America/New_York")!
    /// DST there starts at midnight, so 2026-03-08 has no 00:00 — the round trip must survive it.
    private let havana = TimeZone(identifier: "America/Havana")!

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    @Test func dayKeyFormat() {
        #expect(date("2026-09-17T12:00:00Z").dayKey(in: tokyo) == "2026-09-17")
        #expect(date("2026-01-05T08:30:00Z").dayKey(in: tokyo) == "2026-01-05")
    }

    /// Same instant, two zones, two different local days.
    @Test func dayKeyIsPerTimeZone() {
        let instant = date("2026-09-17T23:00:00Z")
        #expect(instant.dayKey(in: tokyo) == "2026-09-18")
        #expect(instant.dayKey(in: newYork) == "2026-09-17")
    }

    /// ISO week-year, not the calendar year: 2027-01-01 is a Friday and still belongs to 2026.
    @Test(arguments: [
        ("2026-09-17T12:00:00Z", "2026-W38"),
        ("2026-01-01T12:00:00Z", "2026-W01"),   // Thursday → week 1
        ("2027-01-01T12:00:00Z", "2026-W53"),
        ("2026-12-28T12:00:00Z", "2026-W53"),   // Monday starts that week
    ])
    func weekKeyAtYearBoundaries(instant: String, expected: String) {
        #expect(date(instant).weekKey(in: tokyo) == expected)
    }

    /// A Gregorian/ISO mix-up or a region with a different first weekday would show up here:
    /// Sunday must close the week, not open it.
    @Test func weekRunsMondayToSunday() {
        #expect(DayKey.weekKey(of: "2026-09-14", in: tokyo) == "2026-W38")   // Monday
        #expect(DayKey.weekKey(of: "2026-09-20", in: tokyo) == "2026-W38")   // Sunday
        #expect(DayKey.weekKey(of: "2026-09-21", in: tokyo) == "2026-W39")   // next Monday
    }

    @Test func weekdayAndWeekend() {
        #expect(DayKey.weekday(of: "2026-09-17", in: tokyo) == .thursday)
        #expect(DayKey.isWeekend("2026-09-19", in: tokyo))    // Saturday
        #expect(DayKey.isWeekend("2026-09-20", in: tokyo))    // Sunday
        #expect(!DayKey.isWeekend("2026-09-21", in: tokyo))
    }

    @Test(arguments: ["2026-02-30", "2026-13-01", "2026-9-17", "20260917", "", "2026-09-17T00:00"])
    func malformedKeysAreRejected(key: String) {
        #expect(DayKey.date(key, in: tokyo) == nil)
        #expect(!DayKey.isValid(key, in: tokyo))
    }

    @Test func leapDay() {
        #expect(DayKey.isValid("2028-02-29", in: tokyo))
        #expect(!DayKey.isValid("2026-02-29", in: tokyo))
    }

    /// Midnight doesn't exist on this day in Havana; noon anchoring keeps the round trip intact.
    @Test func roundTripAcrossMidnightDST() {
        for key in ["2026-03-07", "2026-03-08", "2026-03-09", "2026-11-01"] {
            let d = try! #require(DayKey.date(key, in: havana))
            #expect(d.dayKey(in: havana) == key)
        }
    }

    @Test func addingCrossesMonthAndYear() {
        #expect(DayKey.adding(1, to: "2026-09-30", in: tokyo) == "2026-10-01")
        #expect(DayKey.adding(-1, to: "2026-01-01", in: tokyo) == "2025-12-31")
        #expect(DayKey.adding(1, to: "2026-03-08", in: havana) == "2026-03-09")
        #expect(DayKey.adding(0, to: "2026-09-17", in: tokyo) == "2026-09-17")
    }

    /// The catch-up loop's day list: exclusive of the last processed day, inclusive of today.
    @Test func rangeIsExclusiveOfStart() {
        #expect(DayKey.range(after: "2026-09-17", through: "2026-09-20", in: tokyo)
                == ["2026-09-18", "2026-09-19", "2026-09-20"])
        #expect(DayKey.range(after: "2026-09-17", through: "2026-09-17", in: tokyo).isEmpty)
        #expect(DayKey.range(after: "2026-09-18", through: "2026-09-17", in: tokyo).isEmpty)
        #expect(DayKey.range(after: "2025-12-30", through: "2026-01-02", in: tokyo)
                == ["2025-12-31", "2026-01-01", "2026-01-02"])
    }

    @Test func rangeSpansDSTWithoutDuplicates() {
        let days = DayKey.range(after: "2026-03-06", through: "2026-03-10", in: havana)
        #expect(days == ["2026-03-07", "2026-03-08", "2026-03-09", "2026-03-10"])
    }

    @Test func daysBetweenIgnoresDST() {
        #expect(DayKey.daysBetween("2026-03-06", "2026-03-10", in: havana) == 4)
        #expect(DayKey.daysBetween("2026-09-20", "2026-09-17", in: tokyo) == -3)
        #expect(DayKey.daysBetween("2026-09-17", "bad", in: tokyo) == nil)
    }

    /// Keys sort chronologically as plain strings — business logic relies on `<` everywhere.
    @Test func keysSortLexicographically() {
        let keys = ["2026-10-01", "2026-09-30", "2025-12-31", "2026-01-02"]
        #expect(keys.sorted() == ["2025-12-31", "2026-01-02", "2026-09-30", "2026-10-01"])
    }

    // MARK: inclusive range (the catch-up loop's list)

    @Test func inclusiveRangeCoversBothEnds() {
        #expect(DayKey.range(from: "2026-09-15", through: "2026-09-18", in: tokyo)
                == ["2026-09-15", "2026-09-16", "2026-09-17", "2026-09-18"])
    }

    @Test func inclusiveRangeOfOneDayIsThatDay() {
        #expect(DayKey.range(from: "2026-09-18", through: "2026-09-18", in: tokyo) == ["2026-09-18"])
    }

    /// The catch-up loop relies on this: reopening the app the same day gives `yesterday < last`,
    /// which must settle nothing rather than walking backwards.
    @Test func inclusiveRangeIsEmptyWhenEndPrecedesStart() {
        #expect(DayKey.range(from: "2026-09-18", through: "2026-09-17", in: tokyo).isEmpty)
    }

    @Test func inclusiveRangeCrossesMonthAndYearBoundaries() {
        #expect(DayKey.range(from: "2026-12-30", through: "2027-01-02", in: tokyo)
                == ["2026-12-30", "2026-12-31", "2027-01-01", "2027-01-02"])
    }

    @Test func inclusiveRangeRejectsAMalformedKey() {
        #expect(DayKey.range(from: "2026-02-30", through: "2026-03-02", in: tokyo).isEmpty)
        #expect(DayKey.range(from: "nonsense", through: "2026-03-02", in: tokyo).isEmpty)
    }
}
