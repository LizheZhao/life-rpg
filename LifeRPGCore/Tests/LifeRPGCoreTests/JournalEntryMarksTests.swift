import Foundation
import Testing
@testable import LifeRPGCore

struct JournalEntryMarksTests {
    private func day(_ dayKey: String, words: Int) -> JournalEntryDay {
        JournalEntryDay(dayKey: dayKey,
                        document: JournalDocument(blocks: [.text(id: UUID(), text: Array(repeating: "w", count: words).joined(separator: " "))]),
                        isDone: false, writtenAt: Date())
    }

    @Test func theBandsAreFixedAtOneHundredAndThreeHundredWords() {
        #expect(JournalMarks.level(forWords: 0) == 1)
        #expect(JournalMarks.level(forWords: 1) == 1)
        #expect(JournalMarks.level(forWords: 99) == 1)
        #expect(JournalMarks.level(forWords: 100) == 2)
        #expect(JournalMarks.level(forWords: 299) == 2)
        #expect(JournalMarks.level(forWords: 300) == 3)
        #expect(JournalMarks.level(forWords: 5_000) == 3)
    }

    @Test func entryDaysGetTheirBandWhateverTheOtherDaysAre() {
        let days = [day("2026-09-01", words: 99), day("2026-09-02", words: 100), day("2026-09-03", words: 299),
                    day("2026-09-04", words: 300)]
        #expect(JournalMarks.levels(entryDays: days) == ["2026-09-01": 1, "2026-09-02": 2, "2026-09-03": 2, "2026-09-04": 3])
        // A lone short day is still light, where the turn-based thirds called it medium.
        #expect(JournalMarks.levels(entryDays: [day("2026-09-01", words: 5)]) == ["2026-09-01": 1])
        #expect(JournalMarks.levels(entryDays: []) == [:])
    }

    @Test func aDayOfOnlyEmojiIsStillMarkedLightest() {
        let emoji = JournalEntryDay(dayKey: "2026-09-01", document: JournalDocument(blocks: [.text(id: UUID(), text: "😀")]),
                                    isDone: false, writtenAt: Date())
        #expect(emoji.wordCount == 0)
        #expect(JournalMarks.levels(entryDays: [emoji]) == ["2026-09-01": 1])
    }

    @Test func theCalendarCarriesTheEntryLevel() {
        let marks = CalendarMarks.marks(quests: [], occurrences: [],
                                        journalLevels: JournalMarks.levels(entryDays: [day("2026-09-17", words: 150)]))
        #expect(marks["2026-09-17"] == DayMarks(journalLevel: 2))
    }
}
