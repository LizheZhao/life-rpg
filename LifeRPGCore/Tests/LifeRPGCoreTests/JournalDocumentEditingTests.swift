import Foundation
import Testing
@testable import LifeRPGCore

/// Offsets count `Character`s, so an emoji or a Chinese ideograph is one.
struct JournalDocumentEditingTests {
    private typealias F = EntryFixtures
    private let seed = JournalPromptSeed(question: "Q?", source: .fixed, fixedKey: .gratefulFor)

    private func insert(_ doc: JournalDocument, block: Int?, offset: Int, seed: JournalPromptSeed? = nil,
                        firstNewID: Int = 100) -> JournalEdit? {
        let ids = F.Ids(from: firstNewID)
        return doc.insertingPrompt(seed ?? self.seed, atBlock: block.map(F.id), offset: offset, makeID: ids.make)
    }

    private func newPrompt(_ n: Int, key: JournalFixedKey? = .gratefulFor) -> JournalBlock {
        F.prompt(n, "Q?", answer: "", source: .fixed, key: key)
    }

    // MARK: insertingPrompt

    @Test func insertingInTheMiddleOfATextSplitsItAndPutsThePromptBetween() throws {
        let edit = try #require(insert(F.doc(F.text(1, "hello world")), block: 1, offset: 5))
        #expect(edit.document.blocks == [F.text(1, "hello"), newPrompt(100), F.text(101, " world")])
        #expect(edit.focus == BlockFocus(blockID: F.id(100), offset: 0))
    }

    @Test func insertingAtTheEndOfATextPutsThePromptAfterWithNoEmptyHalf() throws {
        let edit = try #require(insert(F.doc(F.text(1, "hello")), block: 1, offset: 5))
        #expect(edit.document.blocks == [F.text(1, "hello"), newPrompt(100)])
        #expect(edit.focus == BlockFocus(blockID: F.id(100), offset: 0))
    }

    @Test func insertingAtTheStartOfATextPutsThePromptBefore() throws {
        let edit = try #require(insert(F.doc(F.text(1, "hello")), block: 1, offset: 0))
        #expect(edit.document.blocks == [newPrompt(100), F.text(1, "hello")])
        #expect(edit.focus == BlockFocus(blockID: F.id(100), offset: 0))
    }

    @Test func anOffsetPastTheEndOrBelowZeroIsClamped() throws {
        let past = try #require(insert(F.doc(F.text(1, "hi")), block: 1, offset: 99))
        #expect(past.document.blocks == [F.text(1, "hi"), newPrompt(100)])
        let below = try #require(insert(F.doc(F.text(1, "hi")), block: 1, offset: -3))
        #expect(below.document.blocks == [newPrompt(100), F.text(1, "hi")])
    }

    @Test func insertingInAnEmptyTextPutsThePromptAfterIt() throws {
        let edit = try #require(insert(F.doc(F.text(1, "")), block: 1, offset: 0))
        #expect(edit.document.blocks == [F.text(1, ""), newPrompt(100)])
    }

    @Test func insertingInAnEmptyDocumentAppends() throws {
        let edit = try #require(insert(JournalDocument(), block: nil, offset: 0))
        #expect(edit.document.blocks == [newPrompt(100)])
        #expect(edit.focus == BlockFocus(blockID: F.id(100), offset: 0))
    }

    @Test func aNilBlockMeansTheEndOfTheDocument() throws {
        let edit = try #require(insert(F.doc(F.text(1, "a"), F.prompt(2, answer: "b")), block: nil, offset: 0))
        #expect(edit.document.blocks.last == newPrompt(100))
        #expect(edit.document.blocks.count == 3)
    }

    @Test func insertingWithTheCursorInAPromptsAnswerGoesAfterThatPrompt() throws {
        let doc = F.doc(F.prompt(1, "Q1", answer: "answer here", key: .tomorrow), F.text(2, "tail"))
        let edit = try #require(insert(doc, block: 1, offset: 3))
        #expect(edit.document.blocks == [F.prompt(1, "Q1", answer: "answer here", key: .tomorrow), newPrompt(100), F.text(2, "tail")])
    }

    @Test func aPromptInsertedTwiceLandsAfterTheFirst() throws {
        let first = try #require(insert(F.doc(F.text(1, "hello")), block: 1, offset: 5, seed: .fixed(.favoriteMoment, language: .en)))
        let focus = try #require(first.focus)
        let second = try #require(first.document.insertingPrompt(.fixed(.tomorrow, language: .en),
                                                                  atBlock: focus.blockID, offset: focus.offset,
                                                                  makeID: F.Ids(from: 200).make))
        #expect(second.document.blocks == [
            F.text(1, "hello"),
            F.prompt(100, "What was your favorite moment today?", key: .favoriteMoment),
            F.prompt(200, "What do you want to carry into tomorrow?", key: .tomorrow),
        ])
        #expect(second.focus == BlockFocus(blockID: F.id(200), offset: 0))
    }

    @Test func aChipAlreadyInTheDocumentInsertsNothing() {
        let doc = F.doc(F.prompt(1, key: .gratefulFor))
        #expect(insert(doc, block: 1, offset: 0) == nil)
        #expect(insert(doc, block: 1, offset: 0, seed: JournalPromptSeed(question: "Other", source: .fixed, fixedKey: .tomorrow)) != nil)
    }

    @Test func modelPromptsAreNotLimitedByTheChipRule() {
        let doc = F.doc(F.prompt(1, "Same?", source: .llm))
        let llm = JournalPromptSeed(question: "Same?", source: .llm)
        #expect(insert(doc, block: 1, offset: 0, seed: llm) != nil)
    }

    @Test func anUnknownBlockInsertsNothing() {
        #expect(insert(F.doc(F.text(1, "a")), block: 9, offset: 0) == nil)
    }

    @Test func offsetsCountCharactersSoEmojiAndChineseAreOneEach() throws {
        let emoji = try #require(insert(F.doc(F.text(1, "a😀b")), block: 1, offset: 2))
        #expect(emoji.document.blocks == [F.text(1, "a😀"), newPrompt(100), F.text(101, "b")])
        let chinese = try #require(insert(F.doc(F.text(1, "今天很开心")), block: 1, offset: 2))
        #expect(chinese.document.blocks == [F.text(1, "今天"), newPrompt(100), F.text(101, "很开心")])
        let combined = try #require(insert(F.doc(F.text(1, "e\u{301}x")), block: 1, offset: 1))
        #expect(combined.document.blocks == [F.text(1, "e\u{301}"), newPrompt(100), F.text(101, "x")])
    }

    @Test func aSplitHalfNormalizesBackIntoPlaceWhenThePromptIsRemoved() throws {
        let edit = try #require(insert(F.doc(F.text(1, "hello world")), block: 1, offset: 5))
        let gone = try #require(edit.document.backspaceAtStartOfEmptyAnswer(promptID: F.id(100)))
        // Two texts are left side by side; they join with a newline on save, as the spec says.
        #expect(gone.document.normalized().blocks == [F.text(1, "hello\n world")])
    }

    // MARK: returningAtEndOfAnswer

    @Test func returnAtTheEndOfAnAnswerOpensAnEmptyTextBelow() throws {
        let doc = F.doc(F.prompt(1, answer: "done"), F.prompt(2, answer: "next"))
        let edit = try #require(doc.returningAtEndOfAnswer(promptID: F.id(1), makeID: F.Ids(from: 50).make))
        #expect(edit.document.blocks == [F.prompt(1, answer: "done"), F.text(50, ""), F.prompt(2, answer: "next")])
        #expect(edit.focus == BlockFocus(blockID: F.id(50), offset: 0))
    }

    @Test func returnOnATextOrAnUnknownIdDoesNothing() {
        let doc = F.doc(F.text(1, "a"), F.prompt(2))
        #expect(doc.returningAtEndOfAnswer(promptID: F.id(1)) == nil)
        #expect(doc.returningAtEndOfAnswer(promptID: F.id(9)) == nil)
    }

    // MARK: backspaceAtStartOfEmptyAnswer

    @Test func backspaceOnAnEmptyAnswerDeletesThePromptAndFocusesTheEndOfThePreviousBlock() throws {
        let doc = F.doc(F.text(1, "héllo"), F.prompt(2), F.text(3, "tail"))
        let edit = try #require(doc.backspaceAtStartOfEmptyAnswer(promptID: F.id(2)))
        #expect(edit.document.blocks == [F.text(1, "héllo"), F.text(3, "tail")])
        #expect(edit.focus == BlockFocus(blockID: F.id(1), offset: 5))
    }

    @Test func backspaceOnTheFirstPromptFocusesTheStartOfTheNextBlock() throws {
        let edit = try #require(F.doc(F.prompt(1), F.text(2, "tail")).backspaceAtStartOfEmptyAnswer(promptID: F.id(1)))
        #expect(edit.document.blocks == [F.text(2, "tail")])
        #expect(edit.focus == BlockFocus(blockID: F.id(2), offset: 0))
    }

    @Test func backspaceOnTheOnlyBlockLeavesNothingToFocus() throws {
        let edit = try #require(F.doc(F.prompt(1)).backspaceAtStartOfEmptyAnswer(promptID: F.id(1)))
        #expect(edit.document.blocks == [])
        #expect(edit.focus == nil)
    }

    @Test func backspaceOnAnAnswerWithWordsDoesNothing() {
        #expect(F.doc(F.prompt(1, answer: "x")).backspaceAtStartOfEmptyAnswer(promptID: F.id(1)) == nil)
        #expect(F.doc(F.text(1, "")).backspaceAtStartOfEmptyAnswer(promptID: F.id(1)) == nil)
    }

    // MARK: removingQuestion

    @Test func removingTheQuestionTurnsThePromptIntoTextKeepingTheAnswer() throws {
        let doc = F.doc(F.text(1, "a"), F.prompt(2, "Q?", answer: "my answer", source: .llm), F.text(3, "b"))
        let edit = try #require(doc.removingQuestion(promptID: F.id(2)))
        #expect(edit.document.blocks == [F.text(1, "a"), F.text(2, "my answer"), F.text(3, "b")])
        #expect(edit.focus == BlockFocus(blockID: F.id(2), offset: 9))
        #expect(edit.document.questions == [])
        #expect(edit.document.normalized().blocks == [F.text(1, "a\nmy answer\nb")])
    }

    @Test func removingTheQuestionOfAnUnansweredPromptLeavesAnEmptyTextThatNormalizesAway() throws {
        let edit = try #require(F.doc(F.text(1, "a"), F.prompt(2)).removingQuestion(promptID: F.id(2)))
        #expect(edit.document.blocks == [F.text(1, "a"), F.text(2, "")])
        #expect(edit.document.normalized().blocks == [F.text(1, "a")])
    }

    @Test func removingTheQuestionOfATextOrUnknownBlockDoesNothing() {
        #expect(F.doc(F.text(1, "a")).removingQuestion(promptID: F.id(1)) == nil)
        #expect(F.doc(F.text(1, "a")).removingQuestion(promptID: F.id(8)) == nil)
    }

    @Test func removingAFixedQuestionFreesTheChip() throws {
        let doc = F.doc(F.prompt(1, answer: "x", key: .gratefulFor))
        let edit = try #require(doc.removingQuestion(promptID: F.id(1)))
        #expect(!edit.document.containsFixedKey(.gratefulFor))
    }

    // MARK: settingText

    @Test func aKeystrokeChangesOnlyTheTypedBlock() throws {
        let doc = F.doc(F.text(1, "a"), F.prompt(2, "Q?", answer: "x", source: .llm), F.text(3, "b"))
        let typedText = try #require(doc.settingText(of: F.id(1), to: "ab"))
        #expect(typedText.blocks == [F.text(1, "ab"), F.prompt(2, "Q?", answer: "x", source: .llm), F.text(3, "b")])
        let typedAnswer = try #require(doc.settingText(of: F.id(2), to: "xy"))
        #expect(typedAnswer.blocks == [F.text(1, "a"), F.prompt(2, "Q?", answer: "xy", source: .llm), F.text(3, "b")])
    }

    @Test func aKeystrokeInAnUnknownBlockChangesNothing() {
        #expect(F.doc(F.text(1, "a")).settingText(of: F.id(9), to: "z") == nil)
    }

    // MARK: openedForEditing

    @Test func anEmptyDocumentOpensWithOneEmptyTextToTypeIn() {
        let edit = JournalDocument().openedForEditing(makeID: F.Ids(from: 7).make)
        #expect(edit.document.blocks == [F.text(7, "")])
        #expect(edit.focus == BlockFocus(blockID: F.id(7), offset: 0))
        #expect(edit.document.normalized().blocks == [])
    }

    @Test func aWrittenDocumentOpensWithTheCursorAtTheEndOfItsLastBlock() {
        let text = F.doc(F.prompt(1, answer: "q"), F.text(2, "a😀b")).openedForEditing()
        #expect(text.focus == BlockFocus(blockID: F.id(2), offset: 3))
        let prompt = F.doc(F.text(1, "a"), F.prompt(2, answer: "Heavy")).openedForEditing()
        #expect(prompt.focus == BlockFocus(blockID: F.id(2), offset: 5))
        #expect(prompt.document.blocks.count == 2)
    }
}
