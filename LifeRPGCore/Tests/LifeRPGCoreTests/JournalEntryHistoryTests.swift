import Foundation
import Testing
@testable import LifeRPGCore

struct JournalEntryHistoryTests {
    private typealias F = EntryFixtures

    private func entry(_ dayKey: String, _ blocks: [JournalBlock], done: Bool = false, hour: Int = 21) -> JournalEntry {
        let row = JournalEntry()
        row.dayKey = dayKey
        row.blocks = blocks
        row.createdAt = Fixtures.date(dayKey, hour: hour)
        row.updatedAt = Fixtures.date(dayKey, hour: hour)
        row.doneAt = done ? Fixtures.date(dayKey, hour: hour) : nil
        return row
    }

    private func day(_ dayKey: String, _ blocks: JournalBlock...) -> JournalEntryDay {
        JournalEntryDay(entry(dayKey, blocks))
    }

    // MARK: the day

    @Test func aDayReadsItsFactsFromTheDocument() {
        let row = entry("2026-09-18", [F.text(1, "one two three"), F.prompt(2, "Why?", answer: "four", source: .llm),
                                       F.prompt(3, "Grateful?", answer: "", key: .gratefulFor)], done: true, hour: 22)
        let day = JournalEntryDay(row)
        #expect(day.dayKey == "2026-09-18")
        #expect(day.wordCount == 4)
        #expect(day.promptCount == 2)
        #expect(day.llmPromptCount == 1)
        #expect(day.isDone)
        #expect(day.writtenAt == Fixtures.date("2026-09-18", hour: 22))
        #expect(day.preview == "one two three")
        #expect(day.excerpt(limit: 9) == "one two\u{2026}")
        #expect(day.plainText() == "one two three\n\nWhy?\nfour")
    }

    @Test func aDayKeepsWhenItWasStartedApartFromWhenItWasLastSaved() {
        let row = entry("2026-09-18", [F.text(1, "one")], hour: 23)
        row.createdAt = Fixtures.date("2026-09-18", hour: 21)
        let day = JournalEntryDay(row)
        #expect(day.createdAt == Fixtures.date("2026-09-18", hour: 21))
        #expect(day.writtenAt == Fixtures.date("2026-09-18", hour: 23))
    }

    // MARK: the list

    @Test func daysAreNewestFirstAndOnlyEntriesWithSomethingWritten() {
        let days = JournalEntryHistory.days(from: [
            entry("2026-09-16", [F.text(1, "a")]),
            entry("2026-09-18", [F.text(2, "c")]),
            entry("2026-09-17", [F.prompt(3, "Only asked")]),
            entry("2026-09-15", []),
            entry("2026-09-19", [F.text(4, "d")]),
        ])
        #expect(days.map(\.dayKey) == ["2026-09-19", "2026-09-18", "2026-09-16"])
    }

    @Test func aDayWithTwoRowsShowsTheOneSavedLast() {
        let early = entry("2026-09-18", [F.text(1, "early")], hour: 20)
        let late = entry("2026-09-18", [F.text(2, "late")], hour: 23)
        let days = JournalEntryHistory.days(from: [late, early])
        #expect(days.count == 1)
        #expect(days[0].preview == "late")
    }

    @Test func neighborsSkipDaysWithoutAnEntry() {
        let days = [day("2026-09-20", F.text(1, "a")), day("2026-09-18", F.text(2, "b")), day("2026-09-10", F.text(3, "c"))]
        let mid = JournalEntryHistory.neighbors(of: "2026-09-18", in: days)
        #expect(mid.previous == "2026-09-10" && mid.next == "2026-09-20")
        let gap = JournalEntryHistory.neighbors(of: "2026-09-15", in: days)
        #expect(gap.previous == "2026-09-10" && gap.next == "2026-09-18")
        let newest = JournalEntryHistory.neighbors(of: "2026-09-20", in: days)
        #expect(newest.previous == "2026-09-18" && newest.next == nil)
        let oldest = JournalEntryHistory.neighbors(of: "2026-09-10", in: days)
        #expect(oldest.previous == nil && oldest.next == "2026-09-18")
        let none = JournalEntryHistory.neighbors(of: "2026-09-18", in: [])
        #expect(none.previous == nil && none.next == nil)
    }

    @Test func monthGroupsAreNewestMonthFirstAndNewestDayFirst() {
        let days = [day("2026-09-03", F.text(1, "a")), day("2026-10-02", F.text(2, "b")), day("2026-09-28", F.text(3, "c")),
                    day("2026-10-20", F.text(4, "d")), day("2025-12-31", F.text(5, "e"))]
        let groups = JournalEntryHistory.monthGroups(days)
        #expect(groups.map(\.monthKey) == ["2026-10", "2026-09", "2025-12"])
        #expect(groups.map { $0.days.map(\.dayKey) } == [["2026-10-20", "2026-10-02"], ["2026-09-28", "2026-09-03"], ["2025-12-31"]])
        #expect(JournalEntryHistory.monthGroups([]).isEmpty)
    }

    // MARK: search

    @Test func searchFindsTextAnswersAndQuestions() {
        let d = day("2026-09-18", F.text(1, "Rainy morning"), F.prompt(2, "What are you grateful for today?", answer: "Hot tea"))
        #expect(d.matches("rainy"))
        #expect(d.matches("tea"))
        #expect(d.matches("GRATEFUL"))
        #expect(!d.matches("coffee"))
    }

    @Test func searchIgnoresCaseAndDiacriticsInBothDirections() {
        #expect(day("2026-09-18", F.text(1, "A quiet Café")).matches("cafe"))
        #expect(day("2026-09-18", F.text(1, "cafe")).matches("CAFÉ"))
        #expect(day("2026-09-18", F.text(1, "今天很开心")).matches("很开"))
    }

    @Test func aBlankQueryMatchesEverythingAndAQueryMatchesNoAnswerlessPromptText() {
        let d = day("2026-09-18", F.text(1, "x"))
        #expect(d.matches(""))
        #expect(d.matches("   "))
        #expect(!d.matches("y"))
    }

    @Test func searchSeesAQuestionEvenWhenItsAnswerIsEmpty() {
        #expect(day("2026-09-18", F.text(1, "x"), F.prompt(2, "Tomorrow plans?")).matches("plans"))
    }
}
