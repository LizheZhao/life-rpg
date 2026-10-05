import Foundation
import Testing
@testable import LifeRPGCore

/// When a day's journal is closed, by the same rule the planner uses to stop asking.
struct JournalProgressTests {
    typealias F = JournalFixtures

    @Test func theClosingRuleIsTheSameOneThePlannerUses() {
        let turns = [F.turn(.closing, "free writing", index: 0)]
        #expect(JournalProgress.isClosed(turns))
        #expect(JournalPlanner.next(signals: F.signals(), habits: .none, today: turns, language: .en) == .done)
    }
}
