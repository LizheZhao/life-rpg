import Foundation
import Testing
@testable import LifeRPGCore

struct JournalTrendsWordsTests {
    typealias Words = JournalTrends.Words

    private func entries(_ period: [(String, String)], others: [(String, String)] = [],
                         language: JournalLanguage = .en, limit: Int = 5) -> [Words.Entry] {
        Words.distinctive(period: TrendsFixtures.days(texts: period), others: TrendsFixtures.days(texts: others),
                          language: language, limit: limit)
    }

    private func pairs(_ result: [Words.Entry]) -> [String] { result.map { "\($0.word) \($0.count)" } }

    @Test func theWordsOfAMonthRankByCountAndRepeatingPairsBecomePhrases() {
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

    @Test func aWordWrittenEveryMonthDoesNotBeatOneThatIsNew() {
        let result = entries([
            ("2026-09-01", "running running running running running"),
            ("2026-09-02", "garden garden garden"),
        ], others: [
            ("2026-08-01", "running running running running running"),
            ("2026-08-02", "office meeting office meeting office"),
        ])
        #expect(result.first?.word == "garden")
        #expect(pairs(result).contains("running 5"))
    }

    @Test func withNothingToCompareAgainstTheOrderIsByCountThenAlphabet() {
        let result = entries([("2026-09-01", "zebra zebra apple apple mango mango mango")])
        #expect(pairs(result) == ["mango 3", "apple 2", "zebra 2"])
    }

    @Test func aWordSaidOnceIsNotWhatTheMonthWasAbout() {
        #expect(entries([("2026-09-01", "kayaking once, painting twice painting")]).map(\.word) == ["painting"])
    }

    @Test func fillerStopWordsNumbersAndShortWordsNeverWin() {
        let text = "Today today I’m I’m felt felt like like just just got got didn't didn't the the and and "
            + "ok ok ok 1:1 1:1 1:1 2026 2026 3.5 3.5 😀 😀"
        #expect(entries([("2026-09-01", text)]).isEmpty)
    }

    @Test func onlyTheUsersAnswersAreReadNotTheQuestionOrTheStarter() throws {
        let asked = JournalFixtures.turn(.good, "Yes, kayaking", index: 0, on: "2026-09-01")
        asked.questionText = "Did you enjoy kayaking kayaking kayaking kayaking?"
        let free = JournalFixtures.freeWriting("Grateful for sunshine, sunshine and soup", index: 1, on: "2026-09-01")
        let days = JournalHistory.days(from: [asked, free], language: .en)
        let result = Words.distinctive(period: days, others: [], language: .en, limit: 5)
        #expect(pairs(result) == ["sunshine 2"])
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
        ], language: .zhHans)
        #expect(result.first?.word.contains("散步") == true)
    }

    @Test func theFallbackTokenizerSplitsLetterRunsAndKeepsApostrophesAndHyphens() {
        let tokens = Words.fallbackTokens(in: "don't stop, well-known light version")
        #expect(tokens.map(\.text) == ["don't", "stop", "well-known", "light", "version"])
        #expect(tokens.map(\.joinsPrevious) == [false, true, false, true, true])
    }

    @Test func theFallbackCutsChineseRunsIntoOverlappingPairsAndNeverJoinsThem() {
        let tokens = Words.fallbackTokens(in: "跑步训练 walk小猫")
        #expect(tokens.map(\.text) == ["跑步", "步训", "训练", "walk", "小猫"])
        #expect(tokens.map(\.joinsPrevious) == [false, false, false, false, false])
        #expect(Words.fallbackTokens(in: "猫").map(\.text) == ["猫"])
    }

    @Test func theSystemTokenizerStraightensCurlyApostrophesAndMarksPhraseJoins() {
        let tokens = Words.tokens(in: "I’m here. Light version, light version", language: .en)
        #expect(tokens.map(\.text) == ["i'm", "here", "light", "version", "light", "version"])
        #expect(tokens.map(\.joinsPrevious) == [false, true, false, true, false, true])
    }
}
