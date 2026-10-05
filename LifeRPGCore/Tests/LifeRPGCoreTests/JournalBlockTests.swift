import Foundation
import Testing
@testable import LifeRPGCore

struct JournalBlockTests {
    private typealias F = EntryFixtures

    @Test func aTextBlockHasTheDocumentedShape() throws {
        let json = JournalBlock.encodeAll([F.text(1, "Hello")])
        #expect(json == #"[{"id":"00000000-0000-0000-0000-000000000001","text":"Hello","type":"text"}]"#)
    }

    @Test func aPromptBlockHasTheDocumentedShapeAndOmitsAMissingFixedKey() {
        let withKey = JournalBlock.encodeAll([F.prompt(2, "What?", answer: "This", source: .fixed, key: .gratefulFor)])
        #expect(withKey == #"[{"answer":"This","fixedKey":"gratefulFor","id":"00000000-0000-0000-0000-000000000002","question":"What?","source":"fixed","type":"prompt"}]"#)
        let without = JournalBlock.encodeAll([F.prompt(3, "Why?", answer: "", source: .llm)])
        #expect(without == #"[{"answer":"","id":"00000000-0000-0000-0000-000000000003","question":"Why?","source":"llm","type":"prompt"}]"#)
    }

    @Test func blocksRoundTripIncludingUnicodeAndNewlines() {
        let blocks = [F.text(1, "你好\nline two 😀"), F.prompt(2, "今天？", answer: "é\n\nx", source: .llm),
                      F.prompt(3, key: .tomorrow)]
        #expect(JournalBlock.decodeAll(JournalBlock.encodeAll(blocks)) == blocks)
        #expect(JournalBlock.isValidJSON(JournalBlock.encodeAll(blocks)))
    }

    @Test func anEmptyArrayAndGarbageReadAsAnEmptyDocument() {
        #expect(JournalBlock.decodeAll("[]") == [])
        for garbage in ["", "nope", "{}", "null", "42", #"{"type":"text"}"#, "[1,2", "\u{0}"] {
            #expect(JournalBlock.decodeAll(garbage) == [], "\(garbage)")
        }
    }

    @Test func aBlockOfAnUnknownTypeIsDroppedAndTheRestSurvive() {
        let json = """
        [{"type":"text","id":"00000000-0000-0000-0000-000000000001","text":"keep"},
         {"type":"photo","id":"00000000-0000-0000-0000-000000000002","url":"x"},
         {"type":"text","id":"not-a-uuid","text":"bad id"},
         {"type":"text","id":"00000000-0000-0000-0000-000000000004"},
         {"type":"text","id":"00000000-0000-0000-0000-000000000005","text":"also keep"}]
        """
        #expect(JournalBlock.decodeAll(json) == [F.text(1, "keep"), F.text(5, "also keep")])
        #expect(!JournalBlock.isValidJSON(json))
    }

    @Test func anUnknownFixedKeyKeepsTheAnswerAsAPlainPrompt() {
        let json = #"[{"type":"prompt","id":"00000000-0000-0000-0000-000000000001","question":"Q","answer":"A","source":"fixed","fixedKey":"dreams"}]"#
        #expect(JournalBlock.decodeAll(json) == [F.prompt(1, "Q", answer: "A", source: .fixed, key: nil)])
    }

    @Test func aPromptWithoutASourceIsNotReadable() {
        let json = #"[{"type":"prompt","id":"00000000-0000-0000-0000-000000000001","question":"Q","answer":"A"}]"#
        #expect(JournalBlock.decodeAll(json) == [])
    }

    @Test func writtenTextIsTheWordsAndNeverTheQuestion() {
        #expect(F.text(1, "words").writtenText == "words")
        #expect(F.prompt(2, "question", answer: "answer").writtenText == "answer")
    }
}
