import Foundation
import Testing
@testable import LifeRPGCore

struct JournalNoveltyTests {
    private func similarity(_ a: String, _ b: String, _ language: JournalLanguage = .en) -> Double {
        JournalNovelty.similarity(a, b, language: language)
    }

    // MARK: the closest question

    @Test func theClosestMatchNamesTheQuestionAndHowAlikeItIs() {
        let others = ["What was the best moment of your day?", "What did you think of the new album?"]
        #expect(JournalNovelty.closestMatch("what do you think about the new album", to: others, language: .en)
                == JournalNovelty.Match(question: "What did you think of the new album?", similarity: 1))
        // On a tie the question listed first is named.
        #expect(JournalNovelty.closestMatch("album?", to: ["new album", "old album"], language: .en)?.question == "new album")
        #expect(JournalNovelty.closestMatch("anything", to: [], language: .en) == nil)
        #expect(JournalNovelty.closest("anything", to: [], language: .en) == 0)
    }

    // MARK: similarity

    @Test func englishIsJaccardOverLowercasedContentWordsWithoutPunctuation() {
        #expect(similarity("What did you notice?", "what did you NOTICE") == 1)
        // part, morning, walk and felt are shared; easiest and hardest are not: 4 of 6.
        #expect(similarity("What part of the morning walk felt easiest to you?",
                           "What part of the morning walk felt hardest to you?") == 4.0 / 6.0)
        #expect(similarity("red green blue", "yellow purple") == 0)
        // The frame (how, was, the) is not what the question is about.
        #expect(similarity("How was the walk?", "How was the run?") == 0)
    }

    /// The frames a question is built from say nothing about what it asks, so they can not make two
    /// different questions alike. These are the pairs that scored 0.64, 0.60 and 0.60 over all words.
    @Test func theSameFrameAboutAnotherThingIsAnotherQuestion() {
        #expect(similarity("You finished Walk today. What was it like?",
                           "You finished Cook a meal today. What was it like?") == 2.0 / 5.0)
        #expect(similarity("Run 5 km was a hard one. What was the toughest moment?",
                           "Read 20 pages was a hard one. What was the toughest moment?") == 4.0 / 10.0)
        #expect(JournalNovelty.isFresh("You finished Walk today. What was it like?",
                                       avoiding: ["You finished Cook a meal today. What was it like?"], language: .en))
        // A one-word subject in each is the closest it gets: finished, like, and the subject differs.
        #expect(JournalNovelty.isFresh("You finished Walk today. What was it like?",
                                       avoiding: ["You finished Run today. What was it like?"], language: .en))
    }

    /// The question that came back as a copy of one in the last entries, with its verb reworded.
    @Test func aRewordedCopyOfAnEarlierQuestionIsStillAlike() {
        #expect(similarity("What did you think of the new album?", "What do you think about the new album?") == 1)
        #expect(!JournalNovelty.isFresh("What do you think about the new album?",
                                        avoiding: ["What did you think of the new album?"], language: .en))
        #expect(!JournalNovelty.isFresh("What was the best moment of today?",
                                        avoiding: ["What was the best moment of your day?"], language: .en))
    }

    /// A question made only of frame words has nothing else to compare, so it is compared whole:
    /// the same one is still the same.
    @Test func aQuestionOfNothingButFrameWordsIsComparedWhole() {
        #expect(similarity("What was it like?", "What was it like?") == 1)
        #expect(similarity("What was it?", "How was it?") == 2.0 / 4.0)
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
        // Exactly 0.6 (calm, morning, walk shared of five) is rejected, 2/4 is not.
        #expect(!JournalNovelty.isFresh("How did the calm morning walk feel?",
                                        avoiding: ["How did the calm morning walk go?"], language: .en))
        #expect(JournalNovelty.isFresh("What did the quiet walk give you?",
                                       avoiding: ["What did the quiet walk teach us?"], language: .en))
    }
}
