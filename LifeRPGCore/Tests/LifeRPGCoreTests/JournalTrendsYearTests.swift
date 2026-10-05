import Foundation
import Testing
@testable import LifeRPGCore

struct JournalTrendsYearTests {
    typealias Year = JournalTrends.Year

    @Test func monthCountsHaveTwelveEntriesOfTheGivenYearOnly() {
        let days = TrendsFixtures.entryDays([
            ("2026-01-05", 10), ("2026-01-06", 10), ("2026-03-31", 10), ("2026-09-01", 10),
            ("2026-09-30", 10), ("2026-09-17", 10), ("2025-12-31", 10), ("2027-01-01", 10),
        ])
        #expect(Year.monthCounts(of: days, year: 2026) == [2, 0, 1, 0, 0, 0, 0, 0, 3, 0, 0, 0])
        #expect(Year.monthCounts(of: [], year: 2026) == Array(repeating: 0, count: 12))
    }

    @Test func monthLevelsFollowTheDesignsBands() {
        let levels = [0, 1, 9, 10, 21, 22, 31].map(Year.level(for:))
        #expect(levels == [0, 1, 1, 2, 2, 3, 3])
    }
}
