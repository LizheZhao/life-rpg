import Foundation
import Testing
@testable import LifeRPGCore

struct JournalDocumentTests {
    private typealias F = EntryFixtures

    // MARK: counts

    @Test func wordsCountTextAndAnswersNeverQuestions() {
        let doc = F.doc(F.text(1, "one two three"), F.prompt(2, "a very long question indeed", answer: "four five"))
        #expect(doc.wordCount == 5)
        #expect(doc.characterCount == "one two three".count + "four five".count)
    }

    @Test func chineseCountsOneWordPerIdeograph() {
        #expect(F.doc(F.text(1, "今天很开心")).wordCount == 5)
    }

    @Test func aDocumentIsEmptyWhenNothingButWhitespaceWasTyped() {
        #expect(JournalDocument().isEmpty)
        #expect(F.doc(F.text(1, "")).isEmpty)
        #expect(F.doc(F.prompt(1, "Q"), F.prompt(2, "Q2")).isEmpty)
        #expect(F.doc(F.text(1, " ")).isEmpty)
        #expect(F.doc(F.text(1, " \n\t "), F.prompt(2, "Q", answer: "  ")).isEmpty)
        #expect(!F.doc(F.text(1, " a ")).isEmpty)
        #expect(!F.doc(F.prompt(1, "Q", answer: "x")).isEmpty)
        #expect(!F.doc(F.text(1, "😀")).isEmpty)
    }

    @Test func promptCountsAndQuestions() {
        let doc = F.doc(F.text(1, "x"), F.prompt(2, "first?", source: .llm), F.prompt(3, "second?", key: .tomorrow),
                        F.prompt(4, "third?", source: .llm))
        #expect(doc.promptCount == 3)
        #expect(doc.llmPromptCount == 2)
        #expect(doc.questions == ["first?", "second?", "third?"])
    }

    @Test func containsFixedKeyLooksAtTheKeyOnly() {
        let doc = F.doc(F.prompt(1, key: .gratefulFor), F.prompt(2, source: .llm))
        #expect(doc.containsFixedKey(.gratefulFor))
        #expect(!doc.containsFixedKey(.tomorrow))
    }

    // MARK: normalized

    @Test func twoAdjacentTextsMergeWithANewlineKeepingTheFirstId() {
        let n = F.doc(F.text(1, "a"), F.text(2, "b"), F.text(3, "c")).normalized()
        #expect(n.blocks == [F.text(1, "a\nb\nc")])
    }

    @Test func emptyTextsAreDroppedBeforeMerging() {
        let n = F.doc(F.text(1, "a"), F.text(2, ""), F.text(3, "b")).normalized()
        #expect(n.blocks == [F.text(1, "a\nb")])
        #expect(F.doc(F.text(1, ""), F.prompt(2, answer: "x"), F.text(3, "")).normalized().blocks == [F.prompt(2, answer: "x")])
    }

    @Test func twoAdjacentPromptsNeverMerge() {
        let doc = F.doc(F.prompt(1, "Q1", answer: "a"), F.prompt(2, "Q2", answer: "b"))
        #expect(doc.normalized() == doc)
    }

    @Test func aTextBetweenPromptsStaysBetweenThem() {
        let doc = F.doc(F.prompt(1, answer: "a"), F.text(2, "mid"), F.prompt(3, answer: "b"))
        #expect(doc.normalized() == doc)
    }

    @Test func aPromptWithAnEmptyAnswerIsKeptWhenSomethingIsWritten() {
        let doc = F.doc(F.text(1, "wrote"), F.prompt(2, "skipped?"))
        #expect(doc.normalized() == doc)
    }

    @Test func aDocumentWithNothingWrittenNormalizesToNothing() {
        #expect(F.doc(F.prompt(1), F.text(2, ""), F.prompt(3)).normalized().blocks == [])
    }

    @Test func normalizingTwiceChangesNothing() {
        let doc = F.doc(F.text(1, "a"), F.text(2, ""), F.text(3, "b"), F.prompt(4), F.text(5, "c"), F.text(6, "d"))
        #expect(doc.normalized().normalized() == doc.normalized())
    }

    // MARK: plain text

    @Test func plainTextIsTextsAndPromptsInOrderSeparatedByABlankLine() {
        let doc = F.doc(F.text(1, "Rainy day."),
                        F.prompt(2, "What are you grateful for today?", answer: "Tea."),
                        F.text(3, "Bed early."))
        #expect(doc.plainText() == "Rainy day.\n\nWhat are you grateful for today?\nTea.\n\nBed early.")
    }

    @Test func aPromptWithoutAnAnswerAndABlankTextAreOmitted() {
        let doc = F.doc(F.text(1, "  \n"), F.prompt(2, "Skipped?"), F.prompt(3, "Asked?", answer: " yes "), F.text(4, "end\n"))
        #expect(doc.plainText() == "Asked?\nyes\n\nend")
    }

    @Test func plainTextOfNothingIsEmpty() {
        #expect(JournalDocument().plainText() == "")
        #expect(F.doc(F.prompt(1)).plainText() == "")
    }

    @Test func plainTextHasNoMarkdownBold() {
        #expect(!F.doc(F.prompt(1, "Q", answer: "A")).plainText().contains("*"))
    }

    // MARK: preview and excerpt

    @Test func previewIsTheFirstNonEmptyTextOrAnswerWithWhitespaceCollapsed() {
        let doc = F.doc(F.text(1, ""), F.prompt(2, "Q", answer: ""), F.prompt(3, "Q", answer: "  first\n\n second  "),
                        F.text(4, "later"))
        #expect(doc.preview() == "first second")
    }

    @Test func previewIsCutAtTheLimitWithAnEllipsisOnlyWhenCut() {
        #expect(F.doc(F.text(1, String(repeating: "a", count: 80))).preview() == String(repeating: "a", count: 80))
        #expect(F.doc(F.text(1, String(repeating: "a", count: 81))).preview() == String(repeating: "a", count: 80) + "\u{2026}")
        #expect(F.doc(F.text(1, String(repeating: "字", count: 5))).preview(limit: 3) == "字字字\u{2026}")
        #expect(JournalDocument().preview() == "")
        #expect(F.doc(F.prompt(1, "Q")).preview() == "")
    }

    @Test func excerptTakesTextAndAnswersOnlyInOrder() {
        let doc = F.doc(F.text(1, "alpha"), F.prompt(2, "never shown", answer: "beta"), F.text(3, "gamma"))
        #expect(doc.excerpt(limit: 100) == "alpha beta gamma")
    }

    @Test func excerptCutsAtAWordBoundaryPastHalfTheLimit() {
        let doc = F.doc(F.text(1, "alpha beta gamma delta epsilon"))
        #expect(doc.excerpt(limit: 13) == "alpha beta\u{2026}")
        #expect(doc.excerpt(limit: 29) == "alpha beta gamma delta\u{2026}")
        #expect(doc.excerpt(limit: 30) == "alpha beta gamma delta epsilon")
    }

    @Test func excerptCutsByCharacterWhenThereIsNoSpaceAndDropsTrailingPunctuation() {
        #expect(F.doc(F.text(1, "今天天气很好我们去公园散步")).excerpt(limit: 6) == "今天天气很好\u{2026}")
        #expect(F.doc(F.text(1, "one, two, three")).excerpt(limit: 9) == "one, two\u{2026}")
    }

    @Test func theTurnBasedDayAndTheDocumentCutTheSameWay() {
        let text = "alpha beta gamma delta epsilon"
        let day = JournalHistory.days(from: [JournalFixtures.freeWriting(text)], language: .en)[0]
        #expect(day.excerpt(limit: 13) == F.doc(F.text(1, text)).excerpt(limit: 13))
    }
}
