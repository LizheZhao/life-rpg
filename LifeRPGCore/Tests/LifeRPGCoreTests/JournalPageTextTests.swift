import Foundation
import Testing
@testable import LifeRPGCore

struct JournalPageTextTests {
    private let tz = Fixtures.tokyo

    @Test func wordsAreSingularForOne() {
        #expect(JournalPageText.words(0) == "0 words")
        #expect(JournalPageText.words(1) == "1 word")
        #expect(JournalPageText.words(412) == "412 words")
    }

    @Test func aNeighbourButtonIsTheShortDate() {
        #expect(JournalPageText.shortDate(dayKey: "2026-09-30", language: .en, timeZone: tz) == "Sep 30")
    }

    @Test func aDayWithNothingWrittenIsHeadedByItsDate() {
        #expect(JournalPageText.dateHeading(dayKey: "2026-10-01", language: .en, timeZone: tz) == "Thursday, October 1")
    }

    // MARK: the editor and the reader of an entry

    private func heading(_ day: String, today: String = "2026-10-04", hour: Int, minute: Int = 0,
                         language: JournalLanguage = .en) -> String {
        let now = Fixtures.date("2026-10-04", hour: hour, in: tz).addingTimeInterval(Double(minute) * 60)
        return JournalPageText.editorHeading(dayKey: day, today: today, now: now, language: language, timeZone: tz)
    }

    @Test func theEditorHeadingOfTodayIsTodayByDayAndTonightFromTwenty() {
        #expect(heading("2026-10-04", hour: 4, minute: 59) == "Sunday, October 4 · tonight")
        #expect(heading("2026-10-04", hour: 5) == "Sunday, October 4 · today")
        #expect(heading("2026-10-04", hour: 19, minute: 59) == "Sunday, October 4 · today")
        #expect(heading("2026-10-04", hour: 20) == "Sunday, October 4 · tonight")
        #expect(heading("2026-10-04", hour: 23, minute: 59) == "Sunday, October 4 · tonight")
    }

    @Test func theEditorHeadingOfAnotherDayIsTheDateAtAnyHour() {
        #expect(heading("2026-10-01", hour: 21) == "Thursday, October 1")
        #expect(heading("2026-10-01", hour: 12) == "Thursday, October 1")
    }

    @Test func theChineseEditorHeadingFollowsTheSameHours() {
        #expect(heading("2026-10-04", hour: 12, language: .zhHans).hasSuffix("· 今天"))
        #expect(heading("2026-10-04", hour: 21, language: .zhHans).hasSuffix("· 今晚"))
    }

    @Test func aMalformedKeyIsShownAsItIs() {
        #expect(heading("nope", today: "nope", hour: 21) == "nope · tonight")
    }

    @Test func theReadingHeadingOfAnEntryHasTheTimeItWasWritten() {
        let written = Fixtures.date("2026-10-01", hour: 23).addingTimeInterval(14 * 60)
        let entry = JournalEntryDay(dayKey: "2026-10-01", document: EntryFixtures.doc(EntryFixtures.text(1, "x")),
                                    isDone: true, writtenAt: written)
        // The system puts a narrow no-break space before PM, which keeps "PM" off a line of its own.
        #expect(JournalPageText.readingHeading(entry: entry, language: .en, timeZone: tz)
                == "Thursday, October 1 · 11:14\u{202F}PM")
    }

    @Test func theTagsOfAnEntryAreWordsQuestsAndTheDayType() {
        let entry = JournalEntryDay(dayKey: "2026-10-01",
                                    document: EntryFixtures.doc(EntryFixtures.text(1, "one two three")),
                                    isDone: false, writtenAt: Date())
        let facts = JournalDayFacts(completed: 3, tierText: Tier.normal.dayText)
        #expect(JournalPageText.chips(entry: entry, facts: facts) == ["3 words", "3 quests done", "normal day"])
        #expect(JournalPageText.chips(entry: entry, facts: JournalDayFacts(completed: 1, tierText: nil))
                == ["3 words", "1 quest done"])
        #expect(JournalPageText.chips(entry: entry, facts: nil) == ["3 words"])
        #expect(JournalPageText.chips(entry: entry, facts: JournalDayFacts(completed: 0, tierText: "low day"))
                == ["3 words", "low day"])
    }
}
