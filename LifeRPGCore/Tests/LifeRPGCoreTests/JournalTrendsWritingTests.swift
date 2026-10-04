import Foundation
import Testing
@testable import LifeRPGCore

struct JournalTrendsWritingTests {
    private let tz = Fixtures.tokyo
    private let september = JournalTrends.DayRange(first: "2026-09-01", last: "2026-09-30")
    private let week = JournalTrends.DayRange(first: "2026-09-14", last: "2026-09-20")

    private func writing(_ spec: [(String, Int)], in range: JournalTrends.DayRange? = nil,
                         hour: Int = 22) -> JournalTrends.Writing {
        JournalTrends.Writing(days: TrendsFixtures.days(spec, hour: hour), range: range ?? september, timeZone: tz)
    }

    @Test func entriesAndWordsCountOnlyTheDaysInTheRange() {
        let w = writing([("2026-08-31", 500), ("2026-09-01", 100), ("2026-09-15", 250), ("2026-09-30", 50), ("2026-10-01", 900)])
        #expect(w.entries == 3)
        #expect(w.totalWords == 400)
    }

    @Test func theAverageIsOverWrittenDaysAndRounded() {
        #expect(writing([("2026-09-01", 100), ("2026-09-02", 100), ("2026-09-03", 101)]).averageWords == 100)
        #expect(writing([("2026-09-01", 100), ("2026-09-02", 101)]).averageWords == 101)
        #expect(writing([]).averageWords == 0)
        #expect(writing([]).totalWords == 0)
    }

    @Test func wordsByDayHasEverySlotOfThePeriodWithZeroForAQuietDay() {
        let w = writing([("2026-09-15", 250), ("2026-09-18", 40)], in: week)
        #expect(w.wordsByDay.map(\.dayKey) == ["2026-09-14", "2026-09-15", "2026-09-16", "2026-09-17",
                                               "2026-09-18", "2026-09-19", "2026-09-20"])
        #expect(w.wordsByDay.map(\.words) == [0, 250, 0, 0, 40, 0, 0])
    }

    @Test func aQuietDayIsAnEmptyBarAndTheLongestThirdIsDarkest() {
        let w = writing([("2026-09-14", 10), ("2026-09-15", 20), ("2026-09-16", 30),
                         ("2026-09-17", 40), ("2026-09-18", 50), ("2026-09-19", 60)], in: week)
        #expect(w.wordsByDay.map(\.level) == [1, 1, 2, 2, 3, 3, 0])
        #expect(w.longestDayKeys == ["2026-09-18", "2026-09-19"])
    }

    @Test func theLongestSetHasAtLeastOneDayAndKeepsTies() {
        #expect(writing([("2026-09-14", 10)], in: week).longestDayKeys == ["2026-09-14"])
        #expect(writing([("2026-09-14", 10), ("2026-09-15", 10), ("2026-09-16", 10)], in: week).longestDayKeys
                == ["2026-09-14", "2026-09-15", "2026-09-16"])
        #expect(writing([], in: week).longestDayKeys.isEmpty)
    }

    @Test func theStreakCountsConsecutiveWrittenDaysEndingToday() {
        let w = writing([("2026-09-20", 5), ("2026-09-19", 5), ("2026-09-18", 5), ("2026-09-16", 5), ("2026-09-15", 5)])
        #expect(w.writingStreak(asOf: "2026-09-20") == 3)
    }

    @Test func theStreakSurvivesAnUnwrittenTodayUntilTheEveningIsOver() {
        let w = writing([("2026-09-19", 5), ("2026-09-18", 5), ("2026-09-17", 5)])
        #expect(w.writingStreak(asOf: "2026-09-20") == 3)
        #expect(w.writingStreak(asOf: "2026-09-21") == 0)
    }

    @Test func aGapEndsTheStreakAndAFutureDayIsNotCounted() {
        let w = writing([("2026-09-22", 5), ("2026-09-19", 5), ("2026-09-18", 5)])
        #expect(w.writingStreak(asOf: "2026-09-19") == 2)
        #expect(w.writingStreak(asOf: "2026-09-20") == 2)
        #expect(writing([]).writingStreak(asOf: "2026-09-20") == 0)
    }

    @Test func theStreakCrossesMonthAndYearEnds() {
        let w = writing([("2027-01-02", 5), ("2027-01-01", 5), ("2026-12-31", 5), ("2026-12-30", 5)])
        #expect(w.writingStreak(asOf: "2027-01-02") == 4)
    }

    @Test func theStreakIsNotLimitedToThePeriod() {
        let w = writing([("2026-10-02", 5), ("2026-10-01", 5), ("2026-09-30", 5)], in: week)
        #expect(w.writingStreak(asOf: "2026-10-02") == 3)
    }

    @Test func theUsualHourIsTheMedianOfTheDaysWrittenAtHourFrom0500() {
        let late = writing([("2026-09-01", 5), ("2026-09-02", 5), ("2026-09-03", 5), ("2026-09-04", 5), ("2026-09-05", 5)],
                           hour: 23)
        #expect(late.usualHour == 23)
    }

    @Test func aNightOwlsLateAndEarlyHoursAverageToMidnight() {
        let turns = [("2026-09-01", 23), ("2026-09-02", 23), ("2026-09-03", 0), ("2026-09-04", 1), ("2026-09-05", 1)]
            .map { JournalFixtures.freeWriting("word", on: $0.0, hour: $0.1) }
        let w = JournalTrends.Writing(days: JournalHistory.days(from: turns, language: .en), range: september, timeZone: tz)
        #expect(w.usualHour == 0)
    }

    @Test func theUsualHourNeedsFiveEntriesInThePeriod() {
        #expect(writing([("2026-09-01", 5), ("2026-09-02", 5), ("2026-09-03", 5), ("2026-09-04", 5)]).usualHour == nil)
        // The fifth is outside the period.
        let w = writing([("2026-09-01", 5), ("2026-09-02", 5), ("2026-09-03", 5), ("2026-09-04", 5), ("2026-10-01", 5)])
        #expect(w.usualHour == nil)
    }

    @Test func nightsWrittenAreAllTimeAndSevenUnlockTheTrends() {
        #expect(JournalTrends.Writing.unlockNights == 7)
        let six = writing((1...6).map { (String(format: "2026-08-%02d", $0), 5) }, in: week)
        #expect(six.nightsWritten == 6)
        #expect(!six.isUnlocked)
        let seven = writing((1...7).map { (String(format: "2026-08-%02d", $0), 5) }, in: week)
        #expect(seven.nightsWritten == 7)
        #expect(seven.isUnlocked)
    }
}
