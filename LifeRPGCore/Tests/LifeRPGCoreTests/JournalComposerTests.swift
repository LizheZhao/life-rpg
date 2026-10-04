import Foundation
import Testing
@testable import LifeRPGCore

struct JournalComposerTests {
    private func turn(_ index: Int, _ kind: JournalPromptKind, q: String, a: String,
                      outcome: JournalOutcome = .answered, day: String = "2026-09-18") -> JournalTurn {
        let t = JournalTurn()
        t.dayKey = day; t.index = index; t.kind = kind; t.questionText = q; t.answer = a; t.outcome = outcome
        return t
    }

    @Test func eachAnsweredTurnIsItsQuestionAndTheUsersWordsUnchanged() {
        let turns = [
            turn(0, .opening, q: "What from today do you want to remember?", a: "the  walk home,\nthe rain  "),
            turn(1, .closing, q: "Anything else?", a: "nope"),
        ]
        #expect(JournalComposer.text(turns: turns, language: .en) == [
            "Journal 2026-09-18",
            "What from today do you want to remember?\nthe  walk home,\nthe rain  ",
            "Anything else?\nnope",
        ].joined(separator: "\n\n"))
    }

    @Test func skippedMisfitSafetyAndBlankTurnsAreLeftOutAndOrderFollowsIndex() {
        let turns = [
            turn(4, .closing, q: "", a: "free writing, no question above it"),
            turn(0, .opening, q: "Q0", a: "A0"),
            turn(1, .heavy, q: "Q1", a: "", outcome: .skipped),
            turn(2, .skip, q: "Q2", a: "left over text", outcome: .misfit),
            turn(3, .safety, q: "That sounds heavy.", a: "ok"),
            turn(5, .good, q: "Q5", a: "   "),
        ]
        #expect(JournalComposer.text(turns: turns, language: .zhHans) == [
            "日记 2026-09-18",
            "Q0\nA0",
            "free writing, no question above it",
        ].joined(separator: "\n\n"))
    }

    @Test func aDayWithNothingWrittenComposesNothing() {
        #expect(JournalComposer.text(turns: [], language: .en) == "")
        #expect(JournalComposer.text(turns: [turn(0, .opening, q: "Q", a: "", outcome: .skipped)], language: .en) == "")
    }
}
