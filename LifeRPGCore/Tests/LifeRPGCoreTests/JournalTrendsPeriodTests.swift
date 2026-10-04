import Foundation
import Testing
@testable import LifeRPGCore

struct JournalTrendsPeriodTests {
    private let tz = Fixtures.tokyo

    private func range(_ period: JournalTrends.Period, _ dayKey: String) throws -> [String] {
        let r = try #require(JournalTrends.range(of: period, containing: dayKey, in: tz))
        return [r.first, r.last]
    }

    private func previous(_ period: JournalTrends.Period, _ dayKey: String) throws -> [String] {
        let r = try #require(JournalTrends.previous(of: period, containing: dayKey, in: tz))
        return [r.first, r.last]
    }

    @Test func aWeekRunsMondayToSunday() throws {
        // 2026-09-17 is a Thursday.
        #expect(try range(.week, "2026-09-17") == ["2026-09-14", "2026-09-20"])
        #expect(try range(.week, "2026-09-14") == ["2026-09-14", "2026-09-20"])
        #expect(try range(.week, "2026-09-20") == ["2026-09-14", "2026-09-20"])
    }

    @Test func aWeekCanCrossAMonthAndAYear() throws {
        #expect(try range(.week, "2026-09-30") == ["2026-09-28", "2026-10-04"])
        #expect(try range(.week, "2027-01-01") == ["2026-12-28", "2027-01-03"])
    }

    @Test func aMonthIsTheCalendarMonthIncludingALeapFebruary() throws {
        #expect(try range(.month, "2026-09-17") == ["2026-09-01", "2026-09-30"])
        #expect(try range(.month, "2026-09-30") == ["2026-09-01", "2026-09-30"])
        #expect(try range(.month, "2026-12-31") == ["2026-12-01", "2026-12-31"])
        #expect(try range(.month, "2028-02-10") == ["2028-02-01", "2028-02-29"])
        #expect(try range(.month, "2026-02-10") == ["2026-02-01", "2026-02-28"])
    }

    @Test func aYearIsTheCalendarYear() throws {
        #expect(try range(.year, "2026-09-17") == ["2026-01-01", "2026-12-31"])
        #expect(try range(.year, "2027-01-01") == ["2027-01-01", "2027-12-31"])
    }

    @Test func previousIsTheWholePeriodBeforeThisOne() throws {
        #expect(try previous(.week, "2026-09-17") == ["2026-09-07", "2026-09-13"])
        #expect(try previous(.week, "2027-01-01") == ["2026-12-21", "2026-12-27"])
        #expect(try previous(.month, "2026-09-17") == ["2026-08-01", "2026-08-31"])
        #expect(try previous(.month, "2027-01-15") == ["2026-12-01", "2026-12-31"])
        #expect(try previous(.month, "2026-03-05") == ["2026-02-01", "2026-02-28"])
        #expect(try previous(.year, "2027-06-01") == ["2026-01-01", "2026-12-31"])
    }

    @Test func aMalformedKeyHasNoRange() {
        #expect(JournalTrends.range(of: .week, containing: "nope", in: tz) == nil)
        #expect(JournalTrends.range(of: .month, containing: "2026-13-01", in: tz) == nil)
        #expect(JournalTrends.previous(of: .year, containing: "", in: tz) == nil)
    }

    @Test func daysListsEveryKeyOfTheRangeInOrder() throws {
        let week = try #require(JournalTrends.range(of: .week, containing: "2026-09-30", in: tz))
        #expect(week.days(in: tz) == ["2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01",
                                      "2026-10-02", "2026-10-03", "2026-10-04"])
        let year = try #require(JournalTrends.range(of: .year, containing: "2028-05-05", in: tz))
        #expect(year.days(in: tz).count == 366)
    }

    @Test func containsComparesKeysAsStrings() throws {
        let month = try #require(JournalTrends.range(of: .month, containing: "2026-09-17", in: tz))
        #expect(month.contains("2026-09-01") && month.contains("2026-09-30"))
        #expect(!month.contains("2026-08-31") && !month.contains("2026-10-01"))
    }
}
