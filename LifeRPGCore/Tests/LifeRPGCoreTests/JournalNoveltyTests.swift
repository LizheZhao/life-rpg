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

    // MARK: acceptQuestion

    private let example = "What from today do you want to remember?"

    private func accept(_ text: String, avoiding: [String] = [], _ language: JournalLanguage = .en) -> Bool {
        JournalTextCheck.acceptQuestion(text, language: language, avoiding: avoiding)
    }

    @Test func aFreshCleanQuestionIsAccepted() {
        #expect(accept("Which moment of this day would you like to hold onto?", avoiding: [example]))
        #expect(accept("今天哪件事你想留下来？", avoiding: ["今天有什么事，你想记住？"], .zhHans))
    }

    @Test func anExampleOrAnAlreadyAskedQuestionIsRejected() {
        #expect(accept(example, avoiding: []))
        #expect(!accept(example, avoiding: [example]))
        #expect(!accept("what from today do you want to remember", avoiding: [example]))
        #expect(!accept("今天有什么事，你想记住？", avoiding: ["今天有什么事，你想记住？"], .zhHans))
        // Recent questions are held against it the same as examples.
        #expect(!accept("Which moment of this day would you like to hold onto?",
                        avoiding: [example, "Which moment of this day would you like to hold onto?"]))
    }

    @Test func oneWordSwappedIsStillTheSameQuestion() {
        let ask = "What part of the morning walk felt easiest to you?"
        #expect(accept("What part of the morning walk felt hardest to you?", avoiding: []))
        #expect(!accept("What part of the morning walk felt hardest to you?", avoiding: [ask]))
        #expect(!accept("今天有什么事，你想记下？", avoiding: ["今天有什么事，你想记住？"], .zhHans))
    }

    @Test func theSameThemeInDifferentWordsIsAccepted() {
        let ask = "What did you notice today that you would normally walk past?"
        #expect(accept("Was there something small you almost missed this afternoon?", avoiding: [ask]))
    }

    @Test func aPlaceholderLeftInIsRejected() {
        #expect(!accept("What got in the way of {quest}?"))
        #expect(!accept("「{quest}」没做成。是什么挡了一下？", .zhHans))
        #expect(!accept("{phrase}?"))
        #expect(accept("What got in the way of the walk?"))
    }

    @Test func twoQuestionsInOneAreRejected() {
        #expect(!accept("What happened? How did it feel?"))
        #expect(!accept("今天累吗？想休息吗？", .zhHans))
        #expect(!accept("What happened", avoiding: []))
        #expect(!accept("今天累吗", .zhHans))
    }

    @Test func everyVoiceRuleStillApplies() {
        #expect(!accept("Why did you skip it?"))
        #expect(!accept("What was it like \u{2014} the walk?"))
        #expect(!accept("It's not just the walk, but the rain. What was that like?"))
        #expect(!accept(String(repeating: "word ", count: 50) + "now?"))
        #expect(!accept("**Bold** question?"))
    }

    // MARK: follow-ups

    @Test func aFollowUpThatRestatesAnExampleIsRejected() {
        let answer = "I walked home and it was quiet and nice"
        let shown = "You said \"I walked home and it was quiet and nice\". What stands out to you about that?"
        #expect(JournalTextCheck.accept(reflection: "You said I walked home and it was quiet.",
                                        question: "What stands out to you about that?",
                                        answer: answer, language: .en))
        #expect(!JournalTextCheck.accept(reflection: "You said I walked home and it was quiet.",
                                         question: "What stands out to you about that?",
                                         answer: answer, language: .en, avoiding: [shown]))
        #expect(JournalTextCheck.accept(reflection: "You said it was quiet.",
                                        question: "Where did the quiet show up in your day?",
                                        answer: answer, language: .en, avoiding: [shown]))
    }
}
