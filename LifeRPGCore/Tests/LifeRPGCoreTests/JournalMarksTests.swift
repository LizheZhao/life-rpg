import Foundation
import Testing
@testable import LifeRPGCore

struct JournalMarksTests {
    @Test func thirdsOfAllWrittenDaysGiveTheShades() {
        let days = TrendsFixtures.days([("2026-08-30", 10), ("2026-09-02", 20), ("2026-09-03", 30),
                                        ("2026-09-04", 40), ("2026-09-05", 50), ("2026-10-01", 60)])
        #expect(JournalMarks.levels(days: days) == [
            "2026-08-30": 1, "2026-09-02": 1, "2026-09-03": 2, "2026-09-04": 2, "2026-09-05": 3, "2026-10-01": 3,
        ])
    }

    @Test func aShadeDoesNotDependOnWhichMonthIsOnScreen() {
        let all = TrendsFixtures.days([("2026-08-30", 100), ("2026-09-02", 200), ("2026-09-03", 300),
                                       ("2026-10-01", 400), ("2026-10-02", 500), ("2026-10-03", 600)])
        let levels = JournalMarks.levels(days: all)
        // September alone has two days, which would both read as medium.
        #expect(levels["2026-09-02"] == 1 && levels["2026-09-03"] == 2)
        #expect(levels["2026-10-03"] == 3)
    }

    @Test func withFewerThanThreeWrittenDaysEveryOneIsMedium() {
        #expect(JournalMarks.levels(days: []) == [:])
        #expect(JournalMarks.levels(days: TrendsFixtures.days([("2026-09-02", 5)])) == ["2026-09-02": 2])
        #expect(JournalMarks.levels(days: TrendsFixtures.days([("2026-09-02", 5), ("2026-09-03", 500)]))
                == ["2026-09-02": 2, "2026-09-03": 2])
    }

    @Test func aDayOfOnlyEmojiIsStillMarkedLightest() {
        let days = JournalHistory.days(from: [
            JournalFixtures.freeWriting("😀", on: "2026-09-02"),
            JournalFixtures.freeWriting("some words here", on: "2026-09-03"),
            JournalFixtures.freeWriting("many more words than the others had", on: "2026-09-04"),
        ], language: .en)
        #expect(JournalMarks.levels(days: days)["2026-09-02"] == 1)
    }

    @Test func theCalendarCarriesTheJournalLevelBesideTheOtherMarks() {
        let day = "2026-09-17"
        let quest = JournalFixtures.quest("walk", on: day)
        quest.slot = .medium
        let marks = CalendarMarks.marks(quests: [quest], occurrences: [],
                                        journalLevels: [day: 3, "2026-09-18": 1, "2026-09-19": 0])
        #expect(marks[day] == DayMarks(randomTiers: [.medium], journalLevel: 3))
        #expect(marks["2026-09-18"] == DayMarks(journalLevel: 1))
        #expect(marks["2026-09-19"] == nil)
    }

    @Test func withoutJournalLevelsTheMarksAreAsBefore() {
        let day = "2026-09-17"
        let quest = JournalFixtures.quest("walk", on: day)
        quest.slot = .easy
        let plain = CalendarMarks.marks(quests: [quest], occurrences: [])
        #expect(plain[day] == DayMarks(randomTiers: [.easy]))
        #expect(CalendarMarks.marks(quests: [], occurrences: []).isEmpty)
    }
}
