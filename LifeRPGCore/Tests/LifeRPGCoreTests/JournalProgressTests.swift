import Foundation
import Testing
@testable import LifeRPGCore

/// The one line the Today card shows: where the day's journal stands.
struct JournalProgressTests {
    typealias F = JournalFixtures

    @Test func noTurnsIsNotStarted() {
        #expect(JournalProgress.of([]) == .notStarted)
    }

    @Test func answersCountAndSkipsMisfitsSafetyAndBlanksDoNot() {
        let turns = [
            F.turn(.opening, "A walk home.", index: 0),
            F.turn(.heavy, "", index: 1, outcome: .skipped),
            F.turn(.skip, "left over", index: 2, outcome: .misfit),
            F.turn(.safety, "", index: 3),
            F.turn(.good, "   ", index: 4),
        ]
        #expect(JournalProgress.of(turns) == .inProgress(answered: 1))
    }

    @Test func aDayOfOnlySkipsHasStartedWithNothingAnswered() {
        #expect(JournalProgress.of([F.turn(.opening, "", index: 0, outcome: .skipped)]) == .inProgress(answered: 0))
    }

    @Test func aClosingTurnEndsTheDayWhetherAnsweredOrSkipped() {
        let answered = [F.turn(.opening, "ok then", index: 0), F.turn(.closing, "nothing more", index: 1)]
        #expect(JournalProgress.of(answered) == .done(answered: 2))
        let skipped = [F.turn(.opening, "ok then", index: 0), F.turn(.closing, "", index: 1, outcome: .skipped)]
        #expect(JournalProgress.of(skipped) == .done(answered: 1))
    }

    @Test func theClosingRuleIsTheSameOneThePlannerUses() {
        let turns = [F.turn(.closing, "free writing", index: 0)]
        #expect(JournalProgress.isClosed(turns))
        #expect(JournalPlanner.next(signals: F.signals(), habits: .none, today: turns, language: .en) == .done)
    }
}
