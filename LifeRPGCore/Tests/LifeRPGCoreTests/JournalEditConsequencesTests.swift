import Foundation
import Testing
@testable import LifeRPGCore

/// What editing an answer does, and does not do, to the rules that read answers. Each rule is a
/// pure function of the turns it is given, so an edit is read the next time it is asked.
struct JournalEditConsequencesTests {
    typealias F = JournalFixtures
    private let today = "2026-09-18"
    private let longAnswer = "That one went better than I expected"

    private func next(_ turns: [JournalTurn], signals: JournalSignals = F.signals()) -> JournalStep {
        JournalPlanner.next(signals: signals, habits: .none, today: turns, language: .en)
    }

    // MARK: the planner

    @Test func editingAClosedDayLeavesItDone() throws {
        let turns = [F.turn(.opening, longAnswer, index: 0), F.turn(.closing, "bye", index: 1)]
        #expect(next(turns) == .done)
        try JournalService.edit(turns[0], answer: "something else entirely, said differently")
        try JournalService.edit(turns[1], answer: "see you")
        #expect(next(turns) == .done)
    }

    @Test func editingAnEarlierAnswerDoesNotChangeWhatIsAskedNext() throws {
        let walk = F.quest("Walk")
        let signals = F.signals(quests: [walk], ratings: [F.rating(of: walk.id, 2)])
        let turns = [F.turn(.opening, longAnswer, index: 0), F.turn(.followUp, "ok then", index: 1)]
        let before = next(turns, signals: signals)
        guard case .ask(let question) = before else { Issue.record("expected a question"); return }
        #expect(question.kind == .good)

        try JournalService.edit(turns[0], answer: "A quite different and much longer account of the whole day")
        #expect(next(turns, signals: signals) == before)
    }

    /// The one place an edit reaches the planner on an open day: the follow-up is worded from the
    /// latest answer, so the latest answer's edit is what it reads.
    @Test func editingTheLatestAnswerOfAnOpenDayChangesWhatItsFollowUpQuotes() throws {
        let opening = F.turn(.opening, "short", index: 0)
        guard case .ask(let question) = next([opening]) else { Issue.record("a short answer has no follow-up"); return }
        #expect(question.kind != .followUp)

        try JournalService.edit(opening, answer: longAnswer)
        guard case .followUp(let request) = next([opening]) else { Issue.record("expected a follow-up"); return }
        #expect(request.answer == longAnswer)
    }

    // MARK: safety

    /// The planner derives the safety trigger from answered turns and nothing else, so an edit
    /// that introduces a keyword is treated exactly like an answer that had it: the line is asked
    /// for once, even on a day that was already done, and recording it closes the case.
    @Test func anEditThatIntroducesAKeywordAsksForTheSafetyLineOnce() throws {
        let turns = [F.turn(.opening, longAnswer, index: 0), F.turn(.closing, "bye", index: 1)]
        #expect(next(turns) == .done)

        try JournalService.edit(turns[1], answer: "I just want to die")
        #expect(next(turns) == .safety)

        let line = F.turn(.safety, "", index: 2)
        #expect(next(turns + [line]) == .done)
    }

    @Test func aSafetyLineAlreadyShownIsNotAskedAgainByALaterEdit() throws {
        let turns = [F.turn(.opening, "I feel hopeless about all of it", index: 0), F.turn(.safety, "", index: 1),
                     F.turn(.closing, "bye", index: 2)]
        #expect(next(turns) == .done)
        try JournalService.edit(turns[2], answer: "I want to die")
        #expect(next(turns) == .done)
    }

    @Test func editingTheKeywordAwayBeforeTheLineIsShownCancelsIt() throws {
        let turns = [F.turn(.opening, longAnswer, index: 0), F.turn(.closing, "bye", index: 1)]
        try JournalService.edit(turns[1], answer: "I just want to die")
        #expect(next(turns) == .safety)
        try JournalService.edit(turns[1], answer: "bye for today")
        #expect(next(turns) == .done)
    }

    // MARK: habits

    @Test func theMedianAnswerLengthIsReadFromTheEditedText() throws {
        func answer(_ count: Int) -> String { String(repeating: "x", count: count) }
        let turns = [F.turn(.opening, answer(10), index: 0, on: "2026-09-10"),
                     F.turn(.opening, answer(20), index: 0, on: "2026-09-11"),
                     F.turn(.opening, answer(30), index: 0, on: "2026-09-12")]
        func median() -> Int? { JournalHabits.derive(from: turns, asOf: today, timeZone: Fixtures.tokyo).medianAnswerLength }
        #expect(median() == 20)

        try JournalService.edit(turns[1], answer: "  " + answer(45) + "\n")
        #expect(median() == 30)         // 10, 30, 45
        try JournalService.edit(turns[0], answer: answer(60))
        #expect(median() == 45)         // 30, 45, 60
    }

    // MARK: the composed text

    @Test func theComposedTextShowsTheEditedWordsInTheSamePlace() throws {
        let turns = [F.turn(.opening, "old words", index: 0), F.turn(.closing, "bye", index: 1)]
        try JournalService.edit(turns[0], answer: "new words")
        #expect(JournalComposer.text(turns: turns, language: .en)
                == "Journal 2026-09-18\n\nquestion\nnew words\n\nquestion\nbye")
        #expect(JournalHistory.days(from: turns, language: .en).first?.preview == "new words")
    }
}
