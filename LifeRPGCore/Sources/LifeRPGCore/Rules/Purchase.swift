import Foundation

/// Anything bought with coins: a reroll, an epic extension, a cancellation, a streak freeze, a
/// reward (`PLAN.md` §6).
public enum Purchase {
    /// Why a purchase can't go through, or — as `nil` from the `blocked` functions — that it can.
    public enum Blocked: Error, Equatable, Sendable, CustomStringConvertible {
        case inDebt(balance: Int)
        case tooExpensive(cost: Int, balance: Int)
        case alreadyCompleted
        /// Not something this purchase applies to: hidden, already replaced, not on today's page…
        case notAvailable
        /// Decided with the user: the epic can be rerolled any number of times until it is
        /// extended. Paying to keep it and then swapping it away would waste the extension.
        case epicExtended
        /// Nothing else in the pool right now (small library, everything on cooldown). Nothing
        /// is charged.
        case noCandidates
        /// No single missed day right behind the current streak for a freeze to cover.
        case nothingToRepair

        public var description: String {
            switch self {
            case .inDebt(let balance):
                "Balance is \(balance) — clear the debt by completing quests first"
            case .tooExpensive(let cost, let balance):
                "Costs \(cost), balance is \(balance)"
            case .alreadyCompleted:
                "Already completed"
            case .notAvailable:
                "Not available here"
            case .epicExtended:
                "An extended epic can't be rerolled"
            case .noCandidates:
                "Nothing else to draw right now"
            case .nothingToRepair:
                "No missed day to cover"
            }
        }
    }

    /// The balance rule every purchase shares: it may spend down to exactly zero, never below, and
    /// nothing can be bought while already in debt. Penalties are the only thing allowed to push the
    /// balance negative — they happen to you; a purchase is something you chose.
    public static func blocked(cost: Int, balance: Int) -> Blocked? {
        if balance < 0 { return .inDebt(balance: balance) }
        if balance < cost { return .tooExpensive(cost: cost, balance: balance) }
        return nil
    }
}
