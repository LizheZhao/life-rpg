import Foundation
import Testing
@testable import LifeRPGCore

struct JournalTrendsWritingTests {
    private let tz = Fixtures.tokyo
    private let september = JournalTrends.DayRange(first: "2026-09-01", last: "2026-09-30")
    private let week = JournalTrends.DayRange(first: "2026-09-14", last: "2026-09-20")

    private func writing(_ spec: [(String, Int)], in range: JournalTrends.DayRange? = nil,
                         hour: Int = 22) -> JournalTrends.Writing {
        JournalTrends.Writing(days: TrendsFixtures.entryDays(spec, hour: hour), range: range ?? september, timeZone: tz)
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

    // The darkest bars are the days at or above the nearest-rank 90th percentile: the value at rank
    // ceil(0.9 * n) of the written days, ascending. Ties at the cutoff are all darkest.
    private func top(_ counts: [Int]) -> [Bool] {
        let spec = counts.enumerated().map { (String(format: "2026-09-%02d", $0.offset + 1), $0.element) }
        return writing(spec).wordsByDay.prefix(counts.count).map(\.isTop)
    }

    @Test func aTenDayPeriodsDarkestBarsAreTheNinthAndTenthLongest() {
        #expect(top([10, 20, 30, 40, 50, 60, 70, 80, 90, 100])
                == [false, false, false, false, false, false, false, false, true, true])
    }

    @Test func aTwentyDayPeriodsDarkestBarsAreTheThreeLongest() {
        let counts = (1...20).map { $0 * 10 }
        #expect(top(counts) == (1...20).map { $0 >= 18 })
    }

    @Test func fewDaysStillHaveADarkestOneAndTiesAtTheCutoffAreAllDarkest() {
        #expect(top([40]) == [true])
        #expect(top([10, 30, 20]) == [false, true, false])
        #expect(top([5, 5, 5]) == [true, true, true])
        // Ascending 1 x7, 7, 7, 9: rank 9 is 7, so both sevens and the nine.
        #expect(top([9, 7, 7, 1, 1, 1, 1, 1, 1, 1]) == [true, true, true, false, false, false, false, false, false, false])
    }

    @Test func aDayWithNoWordsIsNeverDarkestAndDoesNotCountTowardTheCutoff() {
        // Two written days of 50 and 80: the cutoff is 80. The four quiet days are not days with words.
        let w = writing([("2026-09-14", 50), ("2026-09-16", 80)], in: week)
        #expect(w.wordsByDay.map(\.isTop) == [false, false, true, false, false, false, false])
        #expect(writing([], in: week).wordsByDay.allSatisfy { !$0.isTop })
    }

    @Test func theHeatGridUsesTheCalendarGlyphsFixedTiers() {
        let w = writing([("2026-09-14", 99), ("2026-09-15", 100), ("2026-09-16", 299), ("2026-09-17", 300),
                         ("2026-09-18", 1000)], in: week)
        #expect(w.wordsByDay.map(\.tier) == [1, 2, 2, 3, 3, 0, 0])
    }

    @Test func anEntryOfOnlyEmojiHasTheLightestTierWhileADayWithNoEntryHasNone() {
        let emoji = TrendsFixtures.day("2026-09-14", text: "\u{1F600}")
        let w = JournalTrends.Writing(days: [emoji], range: week, timeZone: tz)
        #expect(w.wordsByDay.map(\.tier) == [1, 0, 0, 0, 0, 0, 0])
        #expect(w.wordsByDay.map(\.isTop) == Array(repeating: false, count: 7))
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

    /// Entries started at the given wall-clock times on consecutive days of September.
    private func writing(startedAt times: [(hour: Int, minute: Int)], editedAt editHour: Int? = nil) -> JournalTrends.Writing {
        let days = times.enumerated().map { index, time in
            let key = String(format: "2026-09-%02d", index + 1)
            let day = TrendsFixtures.day(key, text: "word", hour: time.hour, minute: time.minute)
            guard let editHour else { return day }
            return JournalEntryDay(dayKey: key, document: day.document, isDone: false,
                                   writtenAt: Fixtures.date(key, hour: editHour), createdAt: day.createdAt)
        }
        return JournalTrends.Writing(days: days, range: september, timeZone: tz)
    }

    @Test func theUsualHourIsTheHourMostEntriesWereStartedIn() {
        #expect(writing(startedAt: [(21, 5), (22, 0), (22, 59), (22, 30), (23, 0)]).usualHour == 22)
    }

    @Test func theUsualHourIsWhenTheEntryWasStartedNotWhenItWasLastEdited() {
        #expect(writing(startedAt: Array(repeating: (hour: 22, minute: 0), count: 5), editedAt: 2).usualHour == 22)
    }

    @Test func aNightOwlsHoursAreWallClockHoursSoMidnightIsNotFoldedIntoTheEvening() {
        let evening = writing(startedAt: [(23, 10), (23, 10), (23, 10), (0, 20), (0, 20)])
        #expect(evening.usualHour == 23)
        let afterMidnight = writing(startedAt: [(0, 20), (0, 20), (0, 20), (23, 10), (23, 10)])
        #expect(afterMidnight.usualHour == 0)
    }

    @Test func aTieGoesToTheHourOfTheMostRecentlyStartedEntryAmongTheTied() {
        // 23:xx on the 1st and 2nd, 00:xx on the 3rd and 4th, noon on the 5th.
        #expect(writing(startedAt: [(23, 10), (23, 10), (0, 20), (0, 20), (12, 0)]).usualHour == 0)
        #expect(writing(startedAt: [(0, 20), (0, 20), (23, 10), (23, 10), (12, 0)]).usualHour == 23)
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

    @Test func aDayCountsOnceNoMatterHowManyRowsItHasAndNeedsSomethingWritten() {
        let sixWritten = TrendsFixtures.entryDays((1...6).map { (String(format: "2026-08-%02d", $0), 5) })
        let duplicate = TrendsFixtures.day("2026-08-03", text: "again")
        let blank = TrendsFixtures.day("2026-08-07", [EntryFixtures.text(1, " \n "), EntryFixtures.prompt(2, "Asked", answer: "")])
        let writing = JournalTrends.Writing(days: sixWritten + [duplicate, blank], range: september, timeZone: tz)
        #expect(writing.nightsWritten == 6)
        #expect(!writing.isUnlocked)
        #expect(JournalTrends.Locked.progress(nightsWritten: writing.nightsWritten).text == "6 of 7 nights written")
    }

    @Test func aDayWithNothingWrittenIsNeitherAnEntryNorPartOfTheStreakOrTheHour() {
        let blank = TrendsFixtures.day("2026-09-20", [EntryFixtures.prompt(1, "Asked", answer: "")])
        let w = JournalTrends.Writing(days: [blank, TrendsFixtures.day("2026-09-19", text: "x")], range: september, timeZone: tz)
        #expect(w.entries == 1)
        #expect(w.writingStreak(asOf: "2026-09-20") == 1)
    }
}
