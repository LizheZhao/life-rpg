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

    @Test func theWritingHeadingNamesTheDayAndTheMoment() {
        #expect(JournalPageText.writingHeading(dayKey: "2026-10-04", evening: true, language: .en, timeZone: tz)
                == "Sunday, October 4 · tonight")
        #expect(JournalPageText.writingHeading(dayKey: "2026-10-04", evening: false, language: .en, timeZone: tz)
                == "Sunday, October 4 · today")
        #expect(JournalPageText.writingHeading(dayKey: "2026-10-04", evening: true, language: .zhHans, timeZone: tz)
                .hasSuffix("· 今晚"))
    }

    @Test func aNeighbourButtonIsTheShortDate() {
        #expect(JournalPageText.shortDate(dayKey: "2026-09-30", language: .en, timeZone: tz) == "Sep 30")
    }

    @Test func aDayWithNothingWrittenIsHeadedByItsDate() {
        #expect(JournalPageText.dateHeading(dayKey: "2026-10-01", language: .en, timeZone: tz) == "Thursday, October 1")
    }

    @Test func aMalformedKeyIsShownAsItIs() {
        #expect(JournalPageText.writingHeading(dayKey: "nope", evening: true, language: .en, timeZone: tz)
                == "nope · tonight")
    }

    // MARK: the editor and the reader of an entry

    @Test func theEditorHeadingIsTonightForTodayAndTheDateForAnotherDay() {
        #expect(JournalPageText.editorHeading(dayKey: "2026-10-04", today: "2026-10-04", language: .en, timeZone: tz)
                == "Sunday, October 4 · tonight")
        #expect(JournalPageText.editorHeading(dayKey: "2026-10-01", today: "2026-10-04", language: .en, timeZone: tz)
                == "Thursday, October 1")
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
