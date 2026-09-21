import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// The opening float. Its only hard requirement is that it is granted once and never again —
/// the balance is a sum over the ledger, so a second grant is indistinguishable from earning 100.
struct StartingBalanceTests {
    @Test func aNewStoreGetsItOnce() throws {
        let ctx = try Fixtures.context()
        #expect(try Economy.balance(ctx) == 0)

        #expect(try Economy.grantStartingBalanceIfNeeded(ctx, dayKey: "2026-09-20") != nil)
        #expect(try Economy.balance(ctx) == 100)

        for _ in 0..<5 {
            #expect(try Economy.grantStartingBalanceIfNeeded(ctx, dayKey: "2026-09-21") == nil)
        }
        #expect(try Economy.balance(ctx) == 100)
    }

    /// A restored backup already contains its grant, so the app must not mint a second one on the
    /// first launch after an import.
    @Test func anImportedGrantSuppressesANewOne() throws {
        let ctx = try Fixtures.context()
        Economy.record(ctx, kind: .grant, points: 100, dayKey: "2026-01-01", note: "Starting balance")
        Economy.record(ctx, kind: .quest, points: 37, dayKey: "2026-01-02")
        try ctx.save()

        #expect(try Economy.grantStartingBalanceIfNeeded(ctx, dayKey: "2026-09-20") == nil)
        #expect(try Economy.balance(ctx) == 137)
    }

    /// The grant is spendable but not earned. A level is a record of what you have done, so a
    /// gift must not buy one — a new store opens at 100 coins and still reads level 1.
    @Test func theGrantIsSpendableButDoesNotCountTowardTheLevel() throws {
        let ctx = try Fixtures.context()
        try Economy.grantStartingBalanceIfNeeded(ctx, dayKey: "2026-09-20")
        #expect(try Economy.balance(ctx) == 100)
        #expect(try Economy.totalEarned(ctx) == 0)
        #expect(Economy.level(totalEarned: try Economy.totalEarned(ctx)) == 1)
    }

    /// Only the grant is excluded. Everything else positive still counts, including a positive
    /// `adjust` — that is a correction to something earned, not a gift.
    @Test func onlyTheGrantIsExcludedFromEarnings() throws {
        let ctx = try Fixtures.context()
        try Economy.grantStartingBalanceIfNeeded(ctx, dayKey: "2026-09-20")
        Economy.record(ctx, kind: .quest, points: 37, dayKey: "2026-09-20")
        Economy.record(ctx, kind: .adjust, points: 5, dayKey: "2026-09-20", note: "mis-tapped")
        Economy.record(ctx, kind: .reroll, points: -30, dayKey: "2026-09-20")
        try ctx.save()

        #expect(try Economy.balance(ctx) == 112)        // 100 + 37 + 5 − 30
        #expect(try Economy.totalEarned(ctx) == 42)     // 37 + 5, no grant, no spending
    }

    /// The HUD sums the rows its own query holds; it has to agree with the store-backed version.
    @Test func theArrayAndStoreReadingsAgree() throws {
        let ctx = try Fixtures.context()
        try Economy.grantStartingBalanceIfNeeded(ctx, dayKey: "2026-09-20")
        Economy.record(ctx, kind: .quest, points: 37, dayKey: "2026-09-20")
        Economy.record(ctx, kind: .penalty, points: -25, dayKey: "2026-09-20")
        try ctx.save()

        let rows = try ctx.fetch(FetchDescriptor<LedgerEntry>())
        #expect(Economy.balance(rows) == (try Economy.balance(ctx)))
        #expect(Economy.totalEarned(rows) == (try Economy.totalEarned(ctx)))
    }
}
