import Foundation
import Testing
@testable import LifeRPGCore

struct JournalHistoryTests {
    typealias F = JournalFixtures

    private func days(_ turns: [JournalTurn]) -> [JournalDay] {
        JournalHistory.days(from: turns, language: .en)
    }

    @Test func daysComeNewestFirstWhateverOrderTheTurnsArriveIn() {
        let turns = [
            F.turn(.opening, "b", index: 0, on: "2026-09-17"),
            F.turn(.opening, "c", index: 0, on: "2026-09-19"),
            F.turn(.opening, "a", index: 0, on: "2026-09-02"),
            F.turn(.good, "d", index: 1, on: "2026-09-19"),
        ]
        #expect(days(turns).map(\.dayKey) == ["2026-09-19", "2026-09-17", "2026-09-02"])
        #expect(days(turns).map(\.answeredCount) == [2, 1, 1])
    }

    @Test func aDayWithOnlySkippedMisfitSafetyOrBlankTurnsIsOmitted() {
        let turns = [
            F.turn(.opening, "", index: 0, on: "2026-09-17", outcome: .skipped),
            F.turn(.heavy, "left over", index: 1, on: "2026-09-17", outcome: .misfit),
            F.turn(.safety, "ok", index: 2, on: "2026-09-17"),
            F.turn(.opening, "  ", index: 0, on: "2026-09-18"),
            F.turn(.opening, "kept", index: 0, on: "2026-09-19"),
        ]
        #expect(days(turns).map(\.dayKey) == ["2026-09-19"])
    }

    @Test func aDayKeepsItsSkippedTurnsInIndexOrderButNotTheSafetyLine() throws {
        let turns = [
            F.turn(.closing, "bye", index: 3),
            F.turn(.safety, "line", index: 2),
            F.turn(.heavy, "", index: 1, outcome: .skipped),
            F.turn(.opening, "hello there", index: 0),
        ]
        let day = try #require(days(turns).first)
        #expect(day.turns.map(\.index) == [0, 1, 3])
        #expect(day.answeredCount == 2)
        #expect(day.preview == "hello there")
    }

    @Test func thePreviewIsTheFirstAnswerOnOneLine() throws {
        let turns = [
            F.turn(.opening, "", index: 0, outcome: .skipped),
            F.turn(.good, "the  walk\n\nhome,\t in the rain ", index: 1),
            F.turn(.closing, "later", index: 2),
        ]
        #expect(try #require(days(turns).first).preview == "the walk home, in the rain")
    }

    @Test func thePreviewIsCutAtEightyCharactersWithAnEllipsisOnlyWhenCut() throws {
        func preview(_ count: Int) throws -> String {
            try #require(days([F.turn(.opening, String(repeating: "a", count: count))]).first).preview
        }
        #expect(try preview(79) == String(repeating: "a", count: 79))
        #expect(try preview(80) == String(repeating: "a", count: 80))
        #expect(try preview(81) == String(repeating: "a", count: 80) + "…")
    }

    @Test func theCutCountsCharactersAfterWhitespaceIsCollapsed() throws {
        // 40 + 3 spaces + 40 collapses to 81 characters, so it is cut; 40 + 1 space + 39 is 80 and is not.
        let long = String(repeating: "a", count: 40) + "   " + String(repeating: "b", count: 40)
        #expect(try #require(days([F.turn(.opening, long)]).first).preview
                == String(repeating: "a", count: 40) + " " + String(repeating: "b", count: 39) + "…")
        let exact = String(repeating: "a", count: 40) + "   " + String(repeating: "b", count: 39)
        #expect(try #require(days([F.turn(.opening, exact)]).first).preview
                == String(repeating: "a", count: 40) + " " + String(repeating: "b", count: 39))
    }

    @Test func aChineseAnswerIsCutByCharacterNotByByte() throws {
        let preview = try #require(days([F.turn(.opening, String(repeating: "字", count: 81))]).first).preview
        #expect(preview == String(repeating: "字", count: 80) + "…")
    }

    // MARK: the longer cut the day sheet shows

    private func excerpt(_ answer: String, limit: Int) throws -> String {
        try #require(days([F.turn(.opening, answer)]).first).excerpt(limit: limit)
    }

    @Test func anExcerptShorterThanTheLimitIsTheWholeEntryOnOneLine() throws {
        #expect(try excerpt("the walk\n\nhome,\t in the rain ", limit: 100) == "the walk home, in the rain")
        #expect(try excerpt("alpha beta", limit: 10) == "alpha beta")
    }

    @Test func anExcerptIsCutAtAWordBoundaryWithAnEllipsis() throws {
        // The limit falls inside "gamma": the whole word goes.
        #expect(try excerpt("alpha beta gamma delta", limit: 12) == "alpha beta\u{2026}")
        // The limit falls exactly on the space after "beta": nothing is lost but the rest.
        #expect(try excerpt("alpha beta gamma", limit: 10) == "alpha beta\u{2026}")
    }

    @Test func aCommaOrColonBeforeTheCutDoesNotStayBesideTheEllipsis() throws {
        #expect(try excerpt("one two, three four", limit: 9) == "one two\u{2026}")
    }

    @Test func textWithoutSpacesIsCutByCharacterAtTheLimit() throws {
        #expect(try excerpt(String(repeating: "字", count: 30), limit: 20) == String(repeating: "字", count: 20) + "\u{2026}")
    }

    @Test func aBoundaryInTheFirstHalfDoesNotLeaveAnAlmostEmptyExcerpt() throws {
        // Backing up to the only space would leave "a".
        #expect(try excerpt("a " + String(repeating: "b", count: 30), limit: 10) == "a bbbbbbbb\u{2026}")
    }

    @Test func theExcerptReadsTheUsersAnswersInOrderAndNeverAQuestion() throws {
        let turns = [
            F.turn(.good, "second", index: 2),
            F.turn(.heavy, "", index: 1, outcome: .skipped),
            F.turn(.opening, "first", index: 0),
            F.turn(.safety, "not mine", index: 3),
        ]
        #expect(try #require(days(turns).first).excerpt(limit: 100) == "first second")
    }

    @Test func isClosedAndTextFollowTheProgressAndComposerRules() throws {
        let open = [F.turn(.opening, "hello", index: 0)]
        let closed = open + [F.turn(.closing, "bye", index: 1)]
        let day = try #require(days(open).first)
        #expect(!day.isClosed)
        #expect(day.text == JournalComposer.text(turns: open, language: .en))
        #expect(day.text == "Journal 2026-09-18\n\nquestion\nhello")
        #expect(try #require(days(closed).first).isClosed)
        #expect(JournalHistory.days(from: closed, language: .zhHans).first?.text.hasPrefix("日记 2026-09-18") == true)
    }

    @Test func noTurnsIsNoDays() {
        #expect(days([]).isEmpty)
    }
}

// MARK: what the reading page shows

struct JournalReadingPageTests {
    typealias F = JournalFixtures

    private func day(_ turns: [JournalTurn]) throws -> JournalDay {
        try #require(JournalHistory.days(from: turns, language: .en).first)
    }

    /// The title ("Journal 2026-09-18") and the question lines are not the user's words.
    @Test func theWordCountIsTheUsersWordsAcrossTheWrittenAnswers() throws {
        let turns = [
            F.turn(.opening, "A walk home in the rain", index: 0),    // 6
            F.turn(.heavy, "", index: 1, outcome: .skipped),
            F.turn(.good, "今天 I walked 3 miles", index: 2),          // 6
            F.turn(.safety, "one two three", index: 3),
        ]
        #expect(try day(turns).wordCount == 12)
    }

    @Test func aFreeWritingDayCountsTheSameWordsAsThePage() throws {
        let text = "Grateful for rain.\n\nI don't mind it."
        #expect(try day([F.freeWriting(text)]).wordCount == JournalWords.count(text))
        #expect(try day([F.freeWriting(text)]).wordCount == 7)
    }

    @Test func writtenAtIsTheAnsweredTimeOfTheLastWrittenTurn() throws {
        let turns = [
            F.turn(.opening, "first", index: 0, hour: 20),
            F.turn(.closing, "last", index: 1, hour: 22),
            F.turn(.good, "", index: 2, outcome: .skipped, hour: 23),
        ]
        #expect(try day(turns).writtenAt == Fixtures.date(F.day, hour: 22))
    }

    @Test func writtenAtFollowsIndexOrderNotTheClock() throws {
        let turns = [F.turn(.opening, "late", index: 0, hour: 23), F.turn(.good, "early", index: 1, hour: 19)]
        #expect(try day(turns).writtenAt == Fixtures.date(F.day, hour: 19))
    }

    @Test func writingSecondsSumOverTheTurns() throws {
        let turns = [F.turn(.opening, "a", index: 0), F.freeWriting("b", index: 1, writingSeconds: 754),
                     F.freeWriting("c", index: 2, writingSeconds: 46)]
        #expect(try day(turns).writingSeconds == 800)
        #expect(try day([F.turn(.opening, "a")]).writingSeconds == 0)
    }

    // MARK: neighbors

    private func days(_ keys: [String]) -> [JournalDay] {
        JournalHistory.days(from: keys.map { F.turn(.opening, "x", on: $0) }, language: .en)
    }

    @Test func neighborsAreTheOlderAndTheNewerDayWithWriting() {
        let list = days(["2026-09-02", "2026-09-10", "2026-09-17", "2026-09-19"])
        let n = JournalHistory.neighbors(of: "2026-09-10", in: list)
        #expect(n.previous == "2026-09-02")
        #expect(n.next == "2026-09-17")
    }

    @Test func theNewestDayHasNoNextAndTheOldestNoPrevious() {
        let list = days(["2026-09-02", "2026-09-10"])
        let newest = JournalHistory.neighbors(of: "2026-09-10", in: list)
        #expect(newest.previous == "2026-09-02" && newest.next == nil)
        let oldest = JournalHistory.neighbors(of: "2026-09-02", in: list)
        #expect(oldest.previous == nil && oldest.next == "2026-09-10")
    }

    @Test func aDayNotInTheListStillFindsItsNeighborsAndAnEmptyListFindsNone() {
        let list = days(["2026-09-02", "2026-09-17"])
        let n = JournalHistory.neighbors(of: "2026-09-10", in: list)
        #expect(n.previous == "2026-09-02" && n.next == "2026-09-17")
        let none = JournalHistory.neighbors(of: "2026-09-10", in: [])
        #expect(none.previous == nil && none.next == nil)
    }

    @Test func theOrderOfTheListDoesNotMatter() {
        let list = Array(days(["2026-09-02", "2026-09-10", "2026-09-17"]).reversed())
        let n = JournalHistory.neighbors(of: "2026-09-10", in: list)
        #expect(n.previous == "2026-09-02" && n.next == "2026-09-17")
    }
}

struct JournalDayFactsTests {
    typealias F = JournalFixtures

    @Test func completedCountsQuestsAndRoutinesOfThatDayOnly() {
        let quests = [F.quest("A"), F.quest("B"), F.quest("Open", done: false), F.quest("Swapped", replaced: true),
                      F.quest("Yesterday", on: "2026-09-17")]
        let routines = [F.routineDone("Gym"), F.routineDone("Old", on: "2026-09-17")]
        let facts = JournalDayFacts.of(dayKey: F.day, quests: quests, occurrences: routines,
                                       context: F.context(tier: .normal))
        #expect(facts.completed == 3)
    }

    @Test func aDayWithNothingDoneIsZero() {
        #expect(JournalDayFacts.of(dayKey: F.day, quests: [], occurrences: [], context: nil).completed == 0)
    }

    @Test func theTierTextIsTheTodayPagesWording() {
        for (tier, text) in [(Tier.veryLow, "very low day"), (.low, "low day"), (.normal, "normal day"), (.high, "high day")] {
            #expect(JournalDayFacts.of(dayKey: F.day, quests: [], occurrences: [],
                                       context: F.context(tier: tier)).tierText == text)
            #expect(tier.dayText == text)
        }
    }

    @Test func aDayWithoutAContextHasNoTierText() {
        #expect(JournalDayFacts.of(dayKey: F.day, quests: [], occurrences: [], context: nil).tierText == nil)
    }

    @Test func theTodayPageHudStillSaysTheSameThing() {
        let hud = LevelCardState(totalEarned: 0, balance: 0, streak: 0, tier: .low, randomSlots: 1, goal: nil)
        #expect(hud.tierText == "low day")
    }
}
