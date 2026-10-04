import Foundation
import Testing
@testable import LifeRPGCore

struct JournalFollowUpTests {
    @Test func theFirstClauseIsQuotedAndCutOnAWordBoundary() {
        // 42 characters: the limit of 40 would split "good", so it backs off to the space.
        #expect(JournalFollowUp.phrase(in: "I walked home in the rain and it felt good, mostly.", language: .en)
                == "I walked home in the rain and it felt")
        #expect(JournalFollowUp.phrase(in: "Tired. Mostly just tired, I think, after work", language: .en) == "Tired")
        #expect(JournalFollowUp.phrase(in: "...fine, I guess", language: .en) == "fine")
        #expect(JournalFollowUp.phrase(in: "  spaced out  ", language: .en) == "spaced out")
    }

    @Test func chineseIsCutAtTwelveCharacters() {
        #expect(JournalFollowUp.phrase(in: "今天走路回家的路上看到了很美的晚霞，心情不错", language: .zhHans)
                == "今天走路回家的路上看到了")
        #expect(JournalFollowUp.phrase(in: "很累。但是还好", language: .zhHans) == "很累")
    }

    @Test func aSingleHugeWordIsCutWhereItStands() {
        let word = String(repeating: "a", count: 60)
        #expect(JournalFollowUp.phrase(in: word, language: .en) == String(repeating: "a", count: 40))
    }

    @Test func aBlankAnswerHasNoTemplateAndAllPunctuationIsQuotedAsItIs() {
        #expect(JournalFollowUp.template(answer: "  \n ", language: .en) == nil)
        #expect(JournalFollowUp.phrase(in: "!!!!!!", language: .en) == "!!!!!!")
    }

    @Test func theTemplateIsTheStandRowFilledWithThePhrase() throws {
        let en = try #require(JournalFollowUp.template(
            answer: "I walked home in the rain and it felt good, mostly.", language: .en))
        #expect(en.promptID == "follow.stand")
        #expect(en.kind == .followUp)
        #expect(en.text == "You said \"I walked home in the rain and it felt\". What stands out to you about that?")
        let zh = try #require(JournalFollowUp.template(answer: "很累。但是还好", language: .zhHans))
        #expect(zh.text == "你说到「很累」。关于这一点，你最在意的是什么？")
    }

    /// Quoting something the user didn't write would be worse than not quoting.
    @Test func thePhraseIsAlwaysAPieceOfTheAnswer() throws {
        let answers = [
            "I walked home in the rain and it felt good, mostly.", "ok", "a b c d e f g h i j k l m n o p q r s t u v w x y z",
            "Tired... so tired.", "\"quoted\" start", "{quest} braces", "line one\nline two", "😀 emoji start and then more words here to cut",
            "今天走路回家的路上看到了很美的晚霞，心情不错", "……", "，，，还好", "mixed 中文 and english words together here ok",
            "!!!!!!!!!!!!!!!!", "  leading space", String(repeating: "长", count: 50),
        ]
        for answer in answers {
            for language in JournalLanguage.allCases {
                let phrase = try #require(JournalFollowUp.phrase(in: answer, language: language), "\(answer)")
                #expect(!phrase.isEmpty)
                #expect(answer.contains(phrase), "\(phrase) / \(answer)")
                #expect(phrase.count <= JournalFollowUp.phraseLimit(language))
                #expect(JournalFollowUp.template(answer: answer, language: language) != nil)
            }
        }
    }
}
