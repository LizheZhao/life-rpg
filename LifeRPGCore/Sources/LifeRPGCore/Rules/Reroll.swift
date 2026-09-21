import Foundation
import SwiftData

/// Paying to swap a random slot for a different draw (`PLAN.md` §6).
///
/// Only the pricing and the affordability rule live here for now — the swap itself lands with the
/// reroll UI. The price is the part that had to be settled early: it is the first thing coins are
/// ever spent on, so it decides whether the balance means anything.
public enum Reroll {
    /// `base × 1.5^n`, rounded **up**, where `n` is how many times this slot has already been
    /// rerolled today. Bases are T 5, E 10, M 20, H 30, EPIC 80.
    ///
    /// So E goes 10 / 15 / 23 / 34 and H goes 30 / 45 / 68 / 102 — the escalation is what stops a
    /// reroll from being a free "give me something easier" button. It resets daily because the
    /// count lives on the day's row, not on the template.
    public static func cost(base: Int, rerollCount: Int) -> Int {
        Int((Double(base) * pow(1.5, Double(max(0, rerollCount)))).rounded(.up))
    }

    public static func cost(for quest: DailyQuest) -> Int {
        cost(base: quest.slot.rerollBase, rerollCount: quest.rerollCount)
    }

    /// Why a reroll isn't available, or nil when it is.
    public enum Blocked: Equatable, Sendable, CustomStringConvertible {
        case inDebt(balance: Int)
        case tooExpensive(cost: Int, balance: Int)
        case alreadyCompleted

        public var description: String {
            switch self {
            case .inDebt(let balance):
                "Balance is \(balance) — clear the debt by completing quests first"
            case .tooExpensive(let cost, let balance):
                "Costs \(cost), balance is \(balance)"
            case .alreadyCompleted:
                "Already completed"
            }
        }
    }

    /// The balance rule: a reroll can never take you below zero, and you can't reroll while already
    /// there (`PLAN.md` §6). Spending down to exactly zero is allowed — that is not debt.
    ///
    /// Penalties are the only thing that may push the balance negative, because they are something
    /// that happens *to* you; a purchase you chose to make should not.
    public static func blocked(cost: Int, balance: Int, completed: Bool) -> Blocked? {
        if completed { return .alreadyCompleted }
        if balance < 0 { return .inDebt(balance: balance) }
        if balance < cost { return .tooExpensive(cost: cost, balance: balance) }
        return nil
    }

    public static func blocked(for quest: DailyQuest, balance: Int) -> Blocked? {
        blocked(cost: cost(for: quest), balance: balance, completed: quest.completedAt != nil)
    }
}
