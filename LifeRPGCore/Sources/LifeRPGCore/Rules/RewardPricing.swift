import Foundation

/// What a reward costs in coins (`PLAN.md` §6 "Reward pricing auto-converted from estimated spend").
///
/// A real-world reward stores only its `estimatedCost` in real currency; the coin price is always
/// computed here, never typed in, so two rewards of the same cost can't drift apart. Virtual items
/// (`estimatedCost == 0`) are priced directly by `fixedCoins`.
public enum RewardPricing {
    /// The one global parameter. Change it and every reward reprices; past redemptions keep the
    /// coins they were booked at, because those live in the ledger.
    public static let multiplier = 10.0
    /// Above this cost each unit of currency is worth half as many coins, so big-ticket rewards
    /// take weeks rather than months.
    public static let knee = 500.0

    /// `cost ≤ 500 ? cost × 10 : 5000 + (cost − 500) × 5`, rounded **up** so a price never comes out
    /// cheaper than the formula says. A negative cost is treated as zero.
    public static func coins(estimatedCost cost: Double, multiplier m: Double = multiplier) -> Int {
        let c = max(0, cost)
        let raw = c <= knee ? c * m : knee * m + (c - knee) * m / 2
        return Int(raw.rounded(.up))
    }

    /// A reward's price: `fixedCoins` for a virtual item, the formula for everything else.
    public static func coins(for reward: Reward, multiplier m: Double = multiplier) -> Int {
        if let fixed = reward.fixedCoins { return fixed }
        return coins(estimatedCost: reward.estimatedCost, multiplier: m)
    }
}
