import Foundation
import Testing
@testable import LifeRPGCore

struct JournalPageTextTests {
    typealias F = JournalFixtures
    private let tz = Fixtures.tokyo

    @Test func wordsAreSingularForOne() {
        #expect(JournalPageText.words(0) == "0 words")
        #expect(JournalPageText.words(1) == "1 word")
        #expect(JournalPageText.words(412) == "412 words")
    }

    @Test func writingTimeIsWholeMinutesAndNothingWithoutTime() {
        #expect(JournalPageText.writingTime(seconds: 0) == nil)
        #expect(JournalPageText.writingTime(seconds: 59) == "Writing for under a minute")
        #expect(JournalPageText.writingTime(seconds: 60) == "Writing for 1 min")
        #expect(JournalPageText.writingTime(seconds: 389) == "Writing for 6 min")
    }

    @Test func theWritingHeadingNamesTheDayAndTheMoment() {
        #expect(JournalPageText.writingHeading(dayKey: "2026-10-04", evening: true, language: .en, timeZone: tz)
                == "Sunday, October 4 · tonight")
        #expect(JournalPageText.writingHeading(dayKey: "2026-10-04", evening: false, language: .en, timeZone: tz)
                == "Sunday, October 4 · today")
        #expect(JournalPageText.writingHeading(dayKey: "2026-10-04", evening: true, language: .zhHans, timeZone: tz)
                .hasSuffix("· 今晚"))
    }

    @Test func theReadingHeadingNamesTheDayAndTheTimeItWasWritten() throws {
        let turn = F.freeWriting("some words", on: "2026-10-01", hour: 23)
        turn.answeredAt = Fixtures.date("2026-10-01", hour: 23).addingTimeInterval(14 * 60)
        let day = try #require(JournalHistory.days(from: [turn], language: .en).first)
        // The system puts a narrow no-break space before PM, which keeps "PM" off a line of its own.
        #expect(JournalPageText.readingHeading(day: day, language: .en, timeZone: tz)
                == "Thursday, October 1 · 11:14\u{202F}PM")
    }

    @Test func aNeighbourButtonIsTheShortDate() {
        #expect(JournalPageText.shortDate(dayKey: "2026-09-30", language: .en, timeZone: tz) == "Sep 30")
    }

    @Test func aMalformedKeyIsShownAsItIs() {
        #expect(JournalPageText.writingHeading(dayKey: "nope", evening: true, language: .en, timeZone: tz)
                == "nope · tonight")
    }

    @Test func chipsAreWordsQuestsAndTheKindOfDay() throws {
        let day = try #require(JournalHistory.days(from: [F.freeWriting("one two three")], language: .en).first)
        let facts = JournalDayFacts(completed: 3, tierText: Tier.normal.dayText)
        #expect(JournalPageText.chips(day: day, facts: facts) == ["3 words", "3 quests done", "normal day"])
        #expect(JournalPageText.chips(day: day, facts: JournalDayFacts(completed: 1, tierText: nil))
                == ["3 words", "1 quest done"])
        #expect(JournalPageText.chips(day: day, facts: JournalDayFacts(completed: 0, tierText: "low day"))
                == ["3 words", "low day"])
    }

    // MARK: layout

    @Test func aDayOfOneFreeWritingTurnIsEditedAsOneText() {
        let turns = [F.freeWriting("All of it.")]
        #expect(JournalReading.layout(of: turns) == .freeWriting)
        #expect(!JournalReading.canAddFreeWriting(to: turns))
    }

    @Test func aDayWithAQuestionIsEditedPerTurn() {
        let turns = [F.turn(.opening, "Fine.", index: 0), F.turn(.good, "Tea.", index: 1)]
        #expect(JournalReading.layout(of: turns) == .turns)
        #expect(JournalReading.entries(of: turns).map(\.answer) == ["Fine.", "Tea."])
        #expect(JournalReading.entries(of: turns).map(\.question) == ["question", "question"])
        #expect(JournalReading.canAddFreeWriting(to: turns))
    }

    @Test func aQuestionedDayWithFreeWritingGivesItsOwnFieldAndNoAddField() {
        let turns = [F.turn(.opening, "Fine.", index: 0), F.freeWriting("More.", index: 1)]
        #expect(JournalReading.layout(of: turns) == .turns)
        #expect(!JournalReading.canAddFreeWriting(to: turns))
    }

    @Test func twoFreeWritingTurnsAreNotOneText() {
        // The page's turn is only the last; showing one text would hide the other from editing.
        let turns = [F.freeWriting("First.", index: 0), F.freeWriting("Second.", index: 1)]
        #expect(JournalReading.layout(of: turns) == .turns)
    }

    @Test func skippedAndBlankTurnsAreNotInTheEntries() {
        let turns = [F.turn(.opening, "", index: 0, outcome: .skipped), F.turn(.good, "Tea.", index: 1),
                     F.freeWriting("  ", index: 2)]
        #expect(JournalReading.entries(of: turns).map(\.answer) == ["Tea."])
        #expect(JournalReading.layout(of: turns) == .turns)
        #expect(JournalReading.layout(of: []) == .empty)
        #expect(JournalReading.layout(of: [F.freeWriting("")]) == .empty)
    }

    @Test func aClearedFreeWritingRowStillLetsTheDayAddFreeWriting() {
        let turns = [F.turn(.opening, "Fine.", index: 0), F.freeWriting("", index: 1)]
        #expect(JournalReading.canAddFreeWriting(to: turns))
    }
}
