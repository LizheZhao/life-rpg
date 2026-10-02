import Foundation
import SwiftData

/// The one reward pinned as what you're saving for, and how far off it is (`PLAN.md` §6
/// "Savings goal"). The pin is `Reward.isGoal`; everything else is derived from the ledger.
public enum SavingsGoal {
    /// Days the pace looks back over.
    public static let paceWindow = 28

    public struct Progress: Equatable, Sendable {
        public var name: String
        public var price: Int
        public var balance: Int
        /// 0…1; a negative balance reads as 0.
        public var fraction: Double
        /// Nil when the pace is zero or negative — no honest estimate exists. 0 once affordable.
        public var weeksLeft: Int?
        public var ready: Bool { balance >= price }

        public init(name: String, price: Int, balance: Int, fraction: Double, weeksLeft: Int?) {
            self.name = name
            self.price = price
            self.balance = balance
            self.fraction = fraction
            self.weeksLeft = weeksLeft
        }
    }

    /// The pinned reward, if it is still active.
    public static func goal(_ rewards: [Reward]) -> Reward? {
        rewards.filter { $0.isGoal && $0.isActive }.min { $0.name < $1.name }
    }

    /// Pins `reward` and unpins every other one — there is only ever one goal.
    public static func pin(_ reward: Reward, in context: ModelContext) throws {
        guard reward.isActive else { return }
        let all = try context.fetch(FetchDescriptor<Reward>())
        let before = all.map { ($0, $0.isGoal) }
        for r in all { r.isGoal = r === reward }
        do {
            try context.save()
        } catch {
            for (r, was) in before { r.isGoal = was }
            throw error
        }
    }

    public static func unpin(_ reward: Reward, in context: ModelContext) throws {
        guard reward.isGoal else { return }
        reward.isGoal = false
        do {
            try context.save()
        } catch {
            reward.isGoal = true
            throw error
        }
    }

    /// Net coins per week over the last 28 days, today included: everything but the opening grant.
    /// Net rather than earned — rerolls and penalties really do push a goal back.
    public static func pace(_ ledger: [LedgerEntry], today: String,
                            in timeZone: TimeZone = .current) -> Double {
        guard let from = DayKey.adding(-(paceWindow - 1), to: today, in: timeZone) else { return 0 }
        let net = ledger
            .filter { $0.kind != Economy.Kind.grant.rawValue && $0.dayKey >= from && $0.dayKey <= today }
            .reduce(0) { $0 + $1.points }
        return Double(net) / (Double(paceWindow) / 7)
    }

    /// `ceil((price − balance) / pace)`; 0 once affordable, nil when the pace is ≤ 0.
    public static func weeksLeft(price: Int, balance: Int, pace: Double) -> Int? {
        if balance >= price { return 0 }
        guard pace > 0 else { return nil }
        return Int((Double(price - balance) / pace).rounded(.up))
    }

    public static func progress(rewards: [Reward], ledger: [LedgerEntry], today: String,
                                in timeZone: TimeZone = .current) -> Progress? {
        guard let reward = goal(rewards) else { return nil }
        let price = RewardPricing.coins(for: reward)
        let balance = Economy.balance(ledger)
        let fraction = price > 0 ? min(1, max(0, Double(balance) / Double(price))) : 1
        return Progress(name: reward.name, price: price, balance: balance, fraction: fraction,
                        weeksLeft: weeksLeft(price: price, balance: balance,
                                             pace: pace(ledger, today: today, in: timeZone)))
    }
}
