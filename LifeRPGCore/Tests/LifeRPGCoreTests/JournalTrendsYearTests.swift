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

    @Test func wordLevelsSplitTheWrittenDaysIntoThirds() {
        let six = [100, 200, 300, 400, 500, 600]
        #expect([0, 100, 200, 300, 400, 500, 600].map { Year.level(forWords: $0, among: six) }
                == [0, 1, 1, 2, 2, 3, 3])
    }

    @Test func aFewDaysStillGetTheDarkestShadeForTheLongest() {
        #expect(Year.level(forWords: 50, among: [50]) == 3)
        // Two days: the longer is darkest, the other is the lightest.
        #expect([40, 10].map { Year.level(forWords: $0, among: [40, 10]) } == [3, 1])
        // Four days: a third of four rounds down to one darkest, two thirds to two lighter-or-more.
        #expect([40, 30, 20, 10].map { Year.level(forWords: $0, among: [10, 20, 30, 40]) } == [3, 2, 1, 1])
    }

    @Test func tiesAtTheCutoffAreAllDarkest() {
        #expect([5, 5, 5, 5, 5, 5].map { Year.level(forWords: $0, among: [5, 5, 5, 5, 5, 5]) } == [3, 3, 3, 3, 3, 3])
        #expect([9, 7, 7, 1, 1, 1].map { Year.level(forWords: $0, among: [9, 7, 7, 1, 1, 1]) } == [3, 3, 3, 2, 2, 2])
    }

    @Test func noWordsIsAlwaysLevelZeroAndNoDaysIsTheLightestShade() {
        #expect(Year.level(forWords: 0, among: [10, 20, 30]) == 0)
        #expect(Year.level(forWords: 12, among: []) == 1)
    }
}
