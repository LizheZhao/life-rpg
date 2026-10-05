import Foundation
import Testing
@testable import LifeRPGCore

/// The all-entries page: what its header, its rows and its search say.
struct JournalEntriesListTests {
    private typealias F = EntryFixtures
    private let tz = Fixtures.tokyo

    private func entry(_ dayKey: String, _ blocks: [JournalBlock], done: Bool = true) -> JournalEntryDay {
        JournalEntryDay(dayKey: dayKey, document: JournalDocument(blocks: blocks), isDone: done,
                        writtenAt: Fixtures.date(dayKey, hour: 22))
    }

    private func page(_ days: [JournalEntryDay], today: String = "2026-10-04", hour: Int = 21,
                      query: String = "") -> JournalEntriesList.Page {
        JournalEntriesList.page(days: days, today: today, now: Fixtures.date(today, hour: hour, in: tz), query: query,
                                language: .en, timeZone: tz)
    }

    // MARK: header lines

    @Test func theSubtitleCountsEntriesAndTheNightStreak() {
        #expect(JournalEntriesList.subtitle(entries: 57, streak: 16) == "57 entries \u{00B7} 16 night streak")
        #expect(JournalEntriesList.subtitle(entries: 1, streak: 1) == "1 entry \u{00B7} 1 night streak")
    }

    @Test func noStreakLeavesItOutOfTheSubtitle() {
        #expect(JournalEntriesList.subtitle(entries: 3, streak: 0) == "3 entries")
        #expect(JournalEntriesList.subtitle(entries: 0, streak: 0) == "No entries yet")
    }

    @Test func theCalendarCardSaysHowManyEntriesAndTheOrder() {
        #expect(JournalEntriesList.cardLine(entries: 57) == "57 entries, newest first")
        #expect(JournalEntriesList.cardLine(entries: 1) == "1 entry, newest first")
        #expect(JournalEntriesList.cardLine(entries: 0) == "Nothing written yet")
    }

    @Test func theStreakInTheSubtitleIsTheTrendsStreak() {
        // Today, yesterday and the day before are written, the day before that is not.
        let days = ["2026-10-04", "2026-10-03", "2026-10-02", "2026-09-30"].map { entry($0, [F.text(1, "x")]) }
        #expect(page(days).subtitle == "4 entries \u{00B7} 3 night streak")
        // Today not written yet: the run ending yesterday still counts, as on Trends.
        #expect(page(Array(days.dropFirst())).subtitle == "3 entries \u{00B7} 2 night streak")
    }

    // MARK: the rows

    @Test func aRowIsTheDayThePreviewTheWordsAndThePromptTag() {
        let day = entry("2026-10-03", [F.text(1, "Cat grooming went fine"), F.text(2, "a b"),
                                       F.prompt(3, "Why?", answer: "c d e"), F.prompt(4, "Grateful?", answer: "")])
        let row = page([day]).sections[0].rows[0]
        #expect(row.dayKey == "2026-10-03")
        #expect(row.dayNumber == 3)
        #expect(row.weekday == "Sat")
        #expect(row.preview == "Cat grooming went fine")
        #expect(row.words == "9 words")
        #expect(row.promptTag == "2 prompts")
    }

    @Test func oneWordAndOnePromptAreSingular() {
        let day = entry("2026-10-02", [F.text(1, "Tired"), F.prompt(2, "Why?", answer: "")])
        let row = page([day]).sections[0].rows[0]
        #expect(row.words == "1 word")
        #expect(row.promptTag == "1 prompt")
    }

    @Test func anEntryWithoutPromptsHasNoTag() {
        #expect(page([entry("2026-10-02", [F.text(1, "Short one.")])]).sections[0].rows[0].promptTag == nil)
    }

    // MARK: month sections

    @Test func rowsAreGroupedByMonthNewestFirst() {
        let days = ["2026-10-03", "2026-10-01", "2026-09-30", "2026-09-29"].map { entry($0, [F.text(1, "x")]) }
        let sections = page(days).sections
        #expect(sections.map(\.monthKey) == ["2026-10", "2026-09"])
        #expect(sections[0].rows.map(\.dayNumber) == [3, 1])
        #expect(sections[1].rows.map(\.dayNumber) == [30, 29])
    }

    @Test func aMonthOfAnotherYearNamesTheYear() {
        let days = [entry("2026-10-03", [F.text(1, "x")]), entry("2025-10-03", [F.text(1, "x")])]
        #expect(page(days).sections.map(\.label) == ["October", "October 2025"])
    }

    // MARK: tonight

    @Test func aDraftTodayIsTheDarkCardAndLeavesTheRows() {
        let draft = entry("2026-10-04", [F.text(1, "one two three")], done: false)
        let older = entry("2026-10-03", [F.text(1, "x")])
        let page = page([draft, older])
        #expect(page.tonight == JournalEntriesList.Tonight(dayKey: "2026-10-04", title: "Tonight, in progress",
                                                           detail: "3 words \u{00B7} keep going"))
        #expect(page.sections.flatMap(\.rows).map(\.dayKey) == ["2026-10-03"])
        #expect(page.subtitle.hasPrefix("2 entries"))
    }

    @Test func theDraftCardIsNamedByTheHour() {
        let draft = entry("2026-10-04", [F.text(1, "one")], done: false)
        #expect(page([draft], hour: 12).tonight?.title == "Today, in progress")
        #expect(page([draft], hour: 19).tonight?.title == "Today, in progress")
        #expect(page([draft], hour: 20).tonight?.title == "Tonight, in progress")
    }

    @Test func aDoneEntryTodayIsARowNotTheCard() {
        let done = entry("2026-10-04", [F.text(1, "one")], done: true)
        let page = page([done])
        #expect(page.tonight == nil)
        #expect(page.sections.flatMap(\.rows).map(\.dayKey) == ["2026-10-04"])
    }

    @Test func aDraftOfAnotherDayIsNotTonight() {
        #expect(page([entry("2026-10-03", [F.text(1, "one")], done: false)]).tonight == nil)
    }

    // MARK: search

    @Test func searchFindsATextAnAnswerAndAQuestion() {
        let days = [
            entry("2026-10-03", [F.text(1, "walked by the harbour")]),
            entry("2026-10-02", [F.prompt(2, "What was hard?", answer: "the lighthouse visit")]),
            entry("2026-10-01", [F.prompt(3, "Where did you go?", answer: "nowhere")]),
        ]
        #expect(page(days, query: "harbour").sections.flatMap(\.rows).map(\.dayKey) == ["2026-10-03"])
        #expect(page(days, query: "LIGHTHOUSE").sections.flatMap(\.rows).map(\.dayKey) == ["2026-10-02"])
        #expect(page(days, query: "where did").sections.flatMap(\.rows).map(\.dayKey) == ["2026-10-01"])
    }

    @Test func nothingFoundSaysSoAndKeepsTheSubtitle() {
        let days = [entry("2026-10-03", [F.text(1, "walked")])]
        let result = page(days, query: "zebra")
        #expect(result.sections.isEmpty)
        #expect(result.emptyText == "No entries match \u{201C}zebra\u{201D}.")
        #expect(result.subtitle == "1 entry \u{00B7} 1 night streak")
    }

    @Test func searchingSetsTheDarkCardAsideAndFindsTodaysDraftAsARow() {
        let draft = entry("2026-10-04", [F.text(1, "harbour at dusk")], done: false)
        let result = page([draft], query: "harbour")
        #expect(result.tonight == nil)
        #expect(result.sections.flatMap(\.rows).map(\.dayKey) == ["2026-10-04"])
    }

    @Test func aBlankQueryIsNotASearch() {
        let draft = entry("2026-10-04", [F.text(1, "x")], done: false)
        #expect(page([draft], query: "   ").tonight != nil)
        #expect(page([], query: "").emptyText == "Nothing written yet.")
    }
}
