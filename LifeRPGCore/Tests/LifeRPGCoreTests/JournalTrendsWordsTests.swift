import Foundation
import Testing
@testable import LifeRPGCore

struct JournalTrendsWordsTests {
    typealias Words = JournalTrends.Words

    private let tz = Fixtures.tokyo
    private let september = JournalTrends.DayRange(first: "2026-09-01", last: "2026-09-30")

    /// The words of September, with `others` (any days outside it) as the rest of the corpus.
    private func result(_ period: [(String, String)], others: [(String, String)] = [],
                        kind: JournalTrends.Period = .month, range: JournalTrends.DayRange? = nil,
                        language: JournalLanguage = .en, limit: Int = 5) -> Words.Result {
        Words.top(in: TrendsFixtures.entryDays(texts: period + others), period: kind,
                  range: range ?? september, language: language, limit: limit, timeZone: tz)
    }

    private func entries(_ period: [(String, String)], others: [(String, String)] = [],
                         language: JournalLanguage = .en, limit: Int = 5) -> [Words.Entry] {
        result(period, others: others, language: language, limit: limit).entries
    }

    private func pairs(_ result: [Words.Entry]) -> [String] { result.map { "\($0.word) \($0.count)" } }

    // MARK: ranking

    @Test func theWordsOfAMonthRankByCountTimesRarityAndRepeatingPairsBecomePhrases() {
        let result = entries([
            ("2026-09-01", "Went climbing at the gym. Climbing again felt great. Pasta for dinner."),
            ("2026-09-02", "Climbing with Sam after work, tired but happy. Light version of the run today."),
            ("2026-09-03", "Climbing, then pasta. The light version of the workout was enough. Light version again."),
        ], others: [
            ("2026-08-01", "Pasta pasta pasta. Pasta night again. Work was busy, busy, busy. Tired."),
        ])
        // "light" and "version" are not also listed on their own: their occurrences belong to the phrase.
        #expect(pairs(result) == ["climbing 4", "light version 3", "pasta 2"])
    }

    @Test func aWordWrittenInEveryMonthLosesToANewOneThatIsSaidLessOften() {
        // Three months. Climbing is new (3 x 1.69), running is in all of them (4 x 1.0), garden too (2 x 1.0).
        let result = entries([
            ("2026-09-01", "climbing climbing climbing garden garden running running running running"),
        ], others: [
            ("2026-08-01", "running running running running running garden"),
            ("2026-10-01", "running running garden"),
        ])
        #expect(pairs(result) == ["climbing 3", "running 4", "garden 2"])
    }

    @Test func aWordInEveryMonthStillCountsWhenItIsTheOnlyOneSaid() {
        // Smoothed, so a word every document has is not scored zero and dropped.
        let result = entries([("2026-09-01", "running running")], others: [("2026-08-01", "running")])
        #expect(pairs(result) == ["running 2"])
    }

    @Test func rarityIsHowManyMonthsHaveTheWordNotHowOftenTheyWriteIt() {
        // Both words are said twice in September. "alpha" is in one other month, ten times over;
        // "gamma" is in two other months, once each. By documents alpha is the rarer.
        let result = entries([
            ("2026-09-01", "alpha alpha gamma gamma"),
        ], others: [
            ("2026-08-01", String(repeating: "alpha ", count: 10) + "gamma"),
            ("2026-10-01", "gamma"),
            ("2026-11-01", "other"),
        ])
        #expect(pairs(result) == ["alpha 2", "gamma 2"])
    }

    @Test func equalScoresFallBackToCountThenAlphabet() {
        let result = entries([("2026-09-01", "zebra zebra apple apple mango mango")], others: [("2026-08-01", "other")])
        #expect(pairs(result) == ["apple 2", "mango 2", "zebra 2"])
    }

    @Test func theCorpusIsOnlyThePeriodsOfTheSameKind() {
        // Three weeks in one month. As weeks the shown one has two others; as months it has none.
        let texts = [("2026-09-08", "sailing sailing sailing"), ("2026-09-15", "sailing sailing garden garden"),
                     ("2026-09-22", "sailing sailing sailing sailing")]
        let week = JournalTrends.DayRange(first: "2026-09-14", last: "2026-09-20")
        let asWeeks = result([texts[1]], others: [texts[0], texts[2]], kind: .week, range: week)
        // garden is only in the shown week (2 x 1.69) and sailing is in all three (2 x 1.0).
        #expect(asWeeks.kind == .distinctive)
        #expect(pairs(asWeeks.entries) == ["garden 2", "sailing 2"])
        let asMonths = result([texts[1]], others: [texts[0], texts[2]], kind: .month,
                              range: JournalTrends.DayRange(first: "2026-09-01", last: "2026-09-30"))
        #expect(asMonths.kind == .mostUsed)
    }

    @Test func aYearsCorpusIsTheOtherYears() {
        let year = JournalTrends.DayRange(first: "2026-01-01", last: "2026-12-31")
        // Same count in 2026, but only tea was also written in 2025.
        let result = result([("2026-03-01", "kayak kayak"), ("2026-09-01", "tea tea")],
                            others: [("2025-06-01", "tea tea tea tea tea")], kind: .year, range: year)
        #expect(result.kind == .distinctive)
        #expect(pairs(result.entries) == ["kayak 2", "tea 2"])
    }

    // MARK: with nothing to compare against

    @Test func withOnlyOnePeriodTheListIsPlainCountsLabelledMostUsedAndOrderedByCountThenAlphabet() {
        let result = result([("2026-09-01", "zebra zebra apple apple mango mango mango")])
        #expect(result.kind == .mostUsed)
        #expect(pairs(result.entries) == ["mango 3", "apple 2", "zebra 2"])
    }

    @Test func anotherPeriodThatHoldsNothingWrittenIsNotACorpusDocument() {
        let blank = TrendsFixtures.day("2026-08-01", [EntryFixtures.prompt(1, "Asked", answer: "  ")])
        let days = TrendsFixtures.entryDays(texts: [("2026-09-01", "kayak kayak")]) + [blank]
        let result = Words.top(in: days, period: .month, range: september, language: .en, timeZone: tz)
        #expect(result.kind == .mostUsed)
        #expect(pairs(result.entries) == ["kayak 2"])
    }

    @Test func aPeriodWithNothingWrittenHasNoWordsAndIsMostUsed() {
        let result = result([], others: [("2026-08-01", "kayak kayak")])
        #expect(result.kind == .mostUsed)
        #expect(result.entries.isEmpty)
    }

    @Test func twoPeriodsAreEnoughToCompare() {
        let result = result([("2026-09-01", "kayak kayak")], others: [("2026-08-01", "tea")])
        #expect(result.kind == .distinctive)
    }

    // MARK: what is read

    @Test func aWordSaidOnceIsNotWhatTheMonthWasAbout() {
        #expect(entries([("2026-09-01", "kayaking once, painting twice painting")]).map(\.word) == ["painting"])
    }

    @Test func fillerStopWordsNumbersAndShortWordsNeverWin() {
        let text = "Today today I’m I’m felt felt like like just just got got didn't didn't the the and and "
            + "ok ok ok 1:1 1:1 1:1 2026 2026 3.5 3.5 😀 😀"
        #expect(entries([("2026-09-01", text)]).isEmpty)
    }

    @Test func onlyTextsAndAnswersAreReadNeverAQuestion() {
        let asked = EntryFixtures.prompt(1, "Did you enjoy kayaking kayaking kayaking kayaking?", answer: "Yes, kayaking")
        let free = EntryFixtures.text(2, "Sunshine again\nSunshine and soup")
        let unanswered = EntryFixtures.prompt(3, "What about whittling whittling whittling?")
        let days = [TrendsFixtures.day("2026-09-01", [asked, free, unanswered])]
        let result = Words.top(in: days, period: .month, range: september, language: .en, timeZone: tz)
        #expect(pairs(result.entries) == ["sunshine 2"])
    }

    @Test func aPhraseNeedsThreeRepeatsAndNeitherAPunctuationMarkNorAStopWordBetween() {
        let result = entries([
            ("2026-09-01", "Cold brew, cold brew. Cold brew again. Cold, brew. Cold and brew. Cold brew."),
        ])
        // Four neighbours make the phrase. The two left over are the "Cold, brew" and "Cold and brew"
        // that a comma and a stop word split.
        #expect(pairs(result) == ["cold brew 4", "brew 2", "cold 2"])
    }

    @Test func aZeroLimitReturnsNothing() {
        #expect(entries([("2026-09-01", "garden garden")], limit: 0).isEmpty)
    }

    // The system tokenizer decides where Chinese words end and may segment differently on another
    // OS release, so these check what must hold either way: the word the text repeats leads, and no
    // filler or particle is listed.
    @Test func chineseWordsAreFoundAndTheFillerIsLeftOut() {
        let result = entries([
            ("2026-09-01", "今天跑步训练很累。跑步让我觉得轻松。"),
            ("2026-09-02", "昨天也去跑步了，今天觉得很好。"),
        ], others: [
            ("2026-08-01", "今天看书。看书让我觉得平静。我觉得看书很好。"),
        ], language: .zhHans)
        #expect(result.first?.word.contains("跑步") == true)
        #expect((result.first?.count ?? 0) >= 3)
        for filler in ["今天", "昨天", "觉得", "我", "很", "了", "也"] {
            #expect(!result.contains { $0.word == filler }, "\(filler) listed")
        }
    }

    @Test func aChineseWordTheOtherMonthsAlsoWriteLosesToANewOne() {
        let result = entries([
            ("2026-09-01", "看书看书看书看书"),
            ("2026-09-02", "散步散步散步"),
        ], others: [
            ("2026-08-01", "看书看书看书看书看书看书"),
            ("2026-10-01", "看书看书"),
        ], language: .zhHans)
        #expect(result.first?.word.contains("散步") == true)
    }

    @Test func theSystemTokenizerStraightensCurlyApostrophesAndMarksPhraseJoins() {
        let tokens = Words.tokens(in: "I’m here. Light version, light version", language: .en)
        #expect(tokens.map(\.text) == ["i'm", "here", "light", "version", "light", "version"])
        #expect(tokens.map(\.joinsPrevious) == [false, true, false, true, false, true])
    }
}
