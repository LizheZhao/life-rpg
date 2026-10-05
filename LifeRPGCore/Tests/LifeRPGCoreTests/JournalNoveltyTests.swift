import Foundation
import Testing
@testable import LifeRPGCore

struct JournalNoveltyTests {
    private func similarity(_ a: String, _ b: String, _ language: JournalLanguage = .en) -> Double {
        JournalNovelty.similarity(a, b, language: language)
    }

    // MARK: similarity

    @Test func englishIsJaccardOverLowercasedWordsWithoutPunctuation() {
        #expect(similarity("What did you notice?", "what did you NOTICE") == 1)
        // 9 shared of 11 distinct words.
        #expect(similarity("What part of the morning walk felt easiest to you?",
                           "What part of the morning walk felt hardest to you?") == 9.0 / 11.0)
        #expect(similarity("red green blue", "yellow purple") == 0)
        #expect(similarity("How was the walk?", "How was the run?") == 3.0 / 5.0)
    }

    @Test func wordOrderAndRepeatsDoNotMatter() {
        #expect(similarity("walk the dog", "dog the walk walk") == 1)
    }

    @Test func chineseIsJaccardOverCharacterBigramsWithoutPunctuationOrSpaces() {
        #expect(similarity("今天有什么事，你想记住？", "今天有什么事 你想记住", .zhHans) == 1)
        // 8 of 10 bigrams shared: only 记住 and 记下 differ.
        #expect(similarity("今天有什么事，你想记住？", "今天有什么事，你想记下？", .zhHans) == 8.0 / 10.0)
        // 今天, 事你, 你想 shared out of 15 distinct.
        #expect(similarity("今天有什么事，你想记住？", "今天哪件事你想留下来？", .zhHans) == 3.0 / 15.0)
    }

    @Test func textWithNoTokensIsNotAlike() {
        #expect(similarity("", "") == 0)
        #expect(similarity("?!", "...") == 0)
        #expect(similarity("好", "好", .zhHans) == 1)
    }

    @Test func theClosestOfNoneIsZeroAndFreshMeansStrictlyBelowTheThreshold() {
        #expect(JournalNovelty.threshold == 0.6)
        #expect(JournalNovelty.closest("anything", to: [], language: .en) == 0)
        // Exactly 0.6 is rejected, 5/9 is not.
        #expect(!JournalNovelty.isFresh("How was the walk?", avoiding: ["How was the run?"], language: .en))
        #expect(JournalNovelty.isFresh("What did the quiet walk give you?",
                                       avoiding: ["What did the quiet walk teach us?"], language: .en))
    }
}
