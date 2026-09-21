import Foundation
import Testing
@testable import LifeRPGCore

/// Balance is a sum over the ledger and nothing else; the level only ever counts income.
struct EconomyTests {
    @Test func balanceSumsEveryEntryAndMayGoNegative() throws {
        let ctx = try Fixtures.context()
        Economy.record(ctx, kind: .quest, points: 30, dayKey: "2026-09-18")
        Economy.record(ctx, kind: .penalty, points: -25, dayKey: "2026-09-18")
        Economy.record(ctx, kind: .redeem, points: -100, dayKey: "2026-09-18")
        try ctx.save()
        #expect(try Economy.balance(ctx) == -95)
        #expect(try Economy.totalEarned(ctx) == 30)     // spending never lowers the level
    }

    @Test func levelFollowsTheSquareRootCurve() {
        #expect(Economy.level(totalEarned: 0) == 1)
        #expect(Economy.level(totalEarned: 59) == 1)
        #expect(Economy.level(totalEarned: 60) == 2)
        #expect(Economy.level(totalEarned: 239) == 2)
        #expect(Economy.level(totalEarned: 240) == 3)   // 60 × 2²
        #expect(Economy.level(totalEarned: 540) == 4)   // 60 × 3²
    }

    @Test func pointsToNextLevelCountsDown() {
        #expect(Economy.pointsToNextLevel(totalEarned: 0) == 60)
        #expect(Economy.pointsToNextLevel(totalEarned: 59) == 1)
        #expect(Economy.pointsToNextLevel(totalEarned: 60) == 180)
    }
}
