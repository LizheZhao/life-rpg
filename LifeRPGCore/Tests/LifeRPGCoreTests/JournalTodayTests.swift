import Foundation
import Testing
@testable import LifeRPGCore

struct JournalTodaySummaryTests {
    typealias F = JournalFixtures

    private func days(_ words: [String: String]) -> [JournalDay] {
        JournalHistory.days(from: words.map { F.turn(.opening, $0.value, on: $0.key) }, language: .en)
    }

    @Test func withNothingWrittenAtAllThereIsNoLastNight() {
        #expect(JournalToday.summary(days: [], today: "2026-09-18") == .notStarted(lastNight: nil))
    }

    @Test func notStartedNamesTheMostRecentEarlierDayAndItsWords() {
        let list = days(["2026-09-10": "one two three", "2026-09-17": "a b c d e", "2026-09-19": "from the future"])
        #expect(JournalToday.summary(days: list, today: "2026-09-18")
                == .notStarted(lastNight: .init(dayKey: "2026-09-17", words: 5)))
    }

    @Test func todayWrittenIsTheWordsOfToday() {
        let list = days(["2026-09-17": "yesterday words", "2026-09-18": "one two three four"])
        #expect(JournalToday.summary(days: list, today: "2026-09-18") == .written(words: 4))
    }

    @Test func aClearedPageOrSkippedTurnsLeaveTodayNotStarted() {
        let list = JournalHistory.days(from: [F.freeWriting(""), F.turn(.opening, "", index: 1, outcome: .skipped),
                                               F.turn(.opening, "last night", index: 0, on: "2026-09-17")],
                                       language: .en)
        #expect(JournalToday.summary(days: list, today: F.day) == .notStarted(lastNight: .init(dayKey: "2026-09-17", words: 2)))
    }
}
