import Foundation
import Testing
@testable import LifeRPGCore

/// Reroll pricing and the balance rule. The exact ladders are written out in `PLAN.md` §6, so they
/// are asserted literally rather than recomputed with the same formula the code uses.
struct RerollTests {
    @Test func theEscalationLaddersMatchThePlan() {
        #expect((0..<4).map { Reroll.cost(base: 10, rerollCount: $0) } == [10, 15, 23, 34])
        #expect((0..<4).map { Reroll.cost(base: 30, rerollCount: $0) } == [30, 45, 68, 102])
    }

    @Test func costComesFromTheSlotsOwnBase() {
        let quest = DailyQuest()
        quest.slot = .medium
        #expect(Reroll.cost(for: quest) == 20)
        quest.rerollCount = 2
        #expect(Reroll.cost(for: quest) == 45)      // ceil(20 × 2.25)
    }

    /// Rounding is up, not to nearest: a reroll should never come out cheaper than the ladder says.
    @Test func pricesRoundUp() {
        #expect(Reroll.cost(base: 10, rerollCount: 1) == 15)
        #expect(Reroll.cost(base: 5, rerollCount: 1) == 8)     // 7.5 → 8, not 7
        #expect(Reroll.cost(base: 30, rerollCount: 2) == 68)   // 67.5 → 68
    }

    // MARK: the balance rule

    @Test func aRerollCannotTakeYouBelowZero() {
        #expect(Reroll.blocked(cost: 30, balance: 29, completed: false)
                == .tooExpensive(cost: 30, balance: 29))
        #expect(Reroll.blocked(cost: 30, balance: 30, completed: false) == nil)   // exactly zero is fine
        #expect(Reroll.blocked(cost: 30, balance: 31, completed: false) == nil)
    }

    /// Penalties may push the balance negative — a purchase must not, and while it is negative
    /// there is nothing to spend.
    @Test func debtBlocksRerollingEvenWhenTheCostIsSmall() {
        #expect(Reroll.blocked(cost: 5, balance: -1, completed: false) == .inDebt(balance: -1))
    }

    @Test func aFinishedQuestCannotBeRerolled() {
        #expect(Reroll.blocked(cost: 10, balance: 9999, completed: true) == .alreadyCompleted)
    }

    @Test func theQuestOverloadReadsTheCompletionState() {
        let quest = DailyQuest()
        quest.slot = .easy
        #expect(Reroll.blocked(for: quest, balance: 100) == nil)
        quest.completedAt = Date()
        #expect(Reroll.blocked(for: quest, balance: 100) == .alreadyCompleted)
    }
}
