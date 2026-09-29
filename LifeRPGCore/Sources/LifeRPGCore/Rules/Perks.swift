import Foundation

/// What a level buys (`PLAN.md` §6 "Level") — a fixed track, one perk per rung, never lost because
/// the level never drops.
///
/// Perks change **prices and limits**, never a quest's payout: a perk that changed a roll or the
/// hidden bonus would make `Scoring.breakdown` depend on the level at the moment of the award,
/// which nothing afterwards can know. The one income perk, the late make-up, pays routines, which
/// have no breakdown.
///
/// Every rule that a perk touches asks here with the level in force at the time of the action, so
/// the track lives in exactly one place and no view checks a level itself.
public enum Perks {
    public enum Perk: String, CaseIterable, Sendable {
        case freeReroll
        case thirdExtension
        case betterMakeUp
        case monthlyFreeze
        case cheaperEpicReroll
        case secondFreeReroll
        case cheaperFreeze

        /// The level that unlocks it.
        public var level: Int {
            switch self {
            case .freeReroll: 3
            case .thirdExtension: 5
            case .betterMakeUp: 8
            case .monthlyFreeze: 10
            case .cheaperEpicReroll: 12
            case .secondFreeReroll: 15
            case .cheaperFreeze: 20
            }
        }

        public var summary: String {
            switch self {
            case .freeReroll: "The day's first reroll is free"
            case .thirdExtension: "The epic can be extended three times"
            case .betterMakeUp: "A late make-up pays 60% instead of 50%"
            case .monthlyFreeze: "One free streak freeze a month"
            case .cheaperEpicReroll: "Epic reroll 80 → 40"
            case .secondFreeReroll: "The day's first two rerolls are free"
            case .cheaperFreeze: "Streak freeze 300 → 150"
            }
        }
    }

    /// The whole track, lowest rung first.
    public static let track: [Perk] = Perk.allCases.sorted { $0.level < $1.level }

    public static func has(_ perk: Perk, at level: Int) -> Bool { level >= perk.level }

    public static func unlocked(at level: Int) -> [Perk] { track.filter { has($0, at: level) } }

    /// Perks whose rung lies in `(old, new]` — what a level-up card announces.
    public static func newlyUnlocked(from old: Int, to new: Int) -> [Perk] {
        track.filter { $0.level > old && $0.level <= new }
    }

    // MARK: the numbers each perk changes

    /// Regular-slot rerolls per day that cost 0.
    public static func freeRerollsPerDay(level: Int) -> Int {
        has(.secondFreeReroll, at: level) ? 2 : has(.freeReroll, at: level) ? 1 : 0
    }

    public static func epicMaxExtensions(level: Int) -> Int {
        has(.thirdExtension, at: level) ? 3 : 2
    }

    /// Share of base a late make-up pays, before the low-tier multiplier (`PLAN.md` §4).
    public static func lateMakeUpRate(level: Int) -> Double {
        has(.betterMakeUp, at: level) ? 0.6 : 0.5
    }

    public static func epicRerollCost(level: Int) -> Int {
        has(.cheaperEpicReroll, at: level) ? 40 : 80
    }

    /// A paid freeze. The monthly free one is decided by `Redemption.freezeCost`, which needs the
    /// ledger to know whether this month's is used.
    public static func freezeCost(level: Int) -> Int {
        has(.cheaperFreeze, at: level) ? 150 : 300
    }

    public static func monthlyFreeFreezes(level: Int) -> Int {
        has(.monthlyFreeze, at: level) ? 1 : 0
    }
}
