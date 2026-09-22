import Foundation

/// Point payouts (`PLAN.md` §5). All rounding is half away from zero, everywhere, including the
/// Stage 2 penalties — so the same helper is used throughout.
public enum Scoring {
    /// A T group scores 12 as a whole, not 4 × 3.
    public static let trivialGroupBase = 12
    /// Flat hidden bonus. Deliberately **not** multiplied by the low-tier multiplier.
    public static let hiddenBonus = 10

    public static func rounded(_ value: Double) -> Int {
        Int(value.rounded(.toNearestOrAwayFromZero))
    }

    /// 1.3x on low-energy days: moving when you are in bad shape deserves more, not less.
    public static func effortMultiplier(_ tier: Tier) -> Double {
        tier.isLow ? 1.3 : 1.0
    }

    /// `round(roll(difficulty) × m) + (hidden ? 10 : 0)`.
    ///
    /// `slot` is the pool the quest came from; for the hidden slot that is the template's own
    /// difficulty, so a hidden M pays an M roll plus the flat bonus.
    public static func questPoints(slot: Difficulty,
                                   isTrivialGroup: Bool,
                                   isHidden: Bool,
                                   tier: Tier,
                                   rng: inout some RandomNumberGenerator) -> Int {
        let base = isTrivialGroup ? trivialGroupBase : Int.random(in: slot.range, using: &rng)
        return rounded(Double(base) * effortMultiplier(tier)) + (isHidden ? hiddenBonus : 0)
    }

    /// A routine pays its fixed `basePoints`, nothing rolled: `round(base × m)` on the due day,
    /// `round(base × 0.5 × m)` as a late make-up on day 2–3 (`PLAN.md` §4). `m` is the tier of
    /// the day it is actually done.
    public static func routinePoints(basePoints: Int, tier: Tier, late: Bool) -> Int {
        rounded(Double(basePoints) * (late ? 0.5 : 1.0) * effortMultiplier(tier))
    }

    /// What an overdue routine costs at the end of round day 1 / 2 / 3: 50% / 75% / 100% of base
    /// (`PLAN.md` §4). Fixed on base, never scaled by the day's tier or readiness.
    public static func overduePenalty(basePoints: Int, roundDay: Int) -> Int {
        let rate: [Double] = [0.5, 0.75, 1.0]
        guard (1...rate.count).contains(roundDay) else { return 0 }
        return rounded(Double(basePoints) * rate[roundDay - 1])
    }

    /// A flexible routine's Sunday settlement: 50% of base per occurrence short of the target,
    /// charged once — no escalation into the next week.
    public static func flexibleShortfallPenalty(basePoints: Int) -> Int {
        rounded(Double(basePoints) * 0.5)
    }

    public static func questPoints(_ quest: DailyQuest, tier: Tier,
                                   rng: inout some RandomNumberGenerator) -> Int {
        questPoints(slot: quest.slot,
                    isTrivialGroup: quest.isTrivialGroup,
                    isHidden: quest.isHiddenSlot,
                    tier: tier,
                    rng: &rng)
    }

    /// What a payout was rolled out of — the range bar the today page animates against.
    ///
    /// Derived from an **already awarded** value rather than rolling again: the roll happens once,
    /// inside `Completion.complete`, and is written to the ledger before anything is drawn on
    /// screen. A view that re-rolled to animate would be showing a different number than the one
    /// you were paid, and `PLAN.md` §3's "completion is final" would quietly stop being true.
    public struct Breakdown: Equatable, Sendable {
        /// The span the roll landed in, **after** the tier multiplier, so `rolled` sits inside it.
        /// A single value for the T group, which has nothing to roll. The reveal animation draws
        /// its throwaway frames from here, so the numbers flashing past are ones that could
        /// actually have come up.
        public var range: ClosedRange<Int>
        /// The rolled part: `awarded` minus the flat bonus.
        public var rolled: Int
        /// The hidden slot's flat +10. Added after the multiplier and never scaled by it, so it
        /// belongs beside the bar rather than inside it.
        public var bonus: Int
        public var multiplier: Double
        /// False for the T group: 12 for the whole group is a fixed payout, not a draw.
        public var isRolled: Bool

        public var awarded: Int { rolled + bonus }

        /// The whole span this slot could have paid, flat bonus included — what the today page
        /// prints under the difficulty badge. `range` is the rolled part alone, which is what the
        /// reveal's throwaway frames are drawn from.
        public var payoutRange: ClosedRange<Int> { Scoring.shift(range, by: bonus) }
    }

    /// The span the roll itself can land in, tier applied, bonus **not** included.
    ///
    /// Rounding half away from zero is monotonic and the multiplier is ≥ 1, so the scaled bounds
    /// keep their order and a scaled roll can't fall outside them.
    public static func rolledRange(slot: Difficulty,
                                   isTrivialGroup: Bool = false,
                                   tier: Tier = .normal) -> ClosedRange<Int> {
        let m = effortMultiplier(tier)
        func scaled(_ base: Int) -> Int { rounded(Double(base) * m) }
        return isTrivialGroup
            ? scaled(trivialGroupBase)...scaled(trivialGroupBase)
            : scaled(slot.range.lowerBound)...scaled(slot.range.upperBound)
    }

    /// Everything a slot can pay, flat bonus included — the label on the today page's badge.
    /// One function so the number you read before doing the quest and the number the reveal lands
    /// on are the same arithmetic, not two copies of it.
    public static func payoutRange(slot: Difficulty,
                                   isTrivialGroup: Bool = false,
                                   isHidden: Bool = false,
                                   tier: Tier = .normal) -> ClosedRange<Int> {
        shift(rolledRange(slot: slot, isTrivialGroup: isTrivialGroup, tier: tier),
              by: isHidden ? hiddenBonus : 0)
    }

    public static func payoutRange(_ quest: DailyQuest, tier: Tier) -> ClosedRange<Int> {
        payoutRange(slot: quest.slot, isTrivialGroup: quest.isTrivialGroup,
                    isHidden: quest.isHiddenSlot, tier: tier)
    }

    static func shift(_ range: ClosedRange<Int>, by amount: Int) -> ClosedRange<Int> {
        (range.lowerBound + amount)...(range.upperBound + amount)
    }

    public static func breakdown(slot: Difficulty,
                                 isTrivialGroup: Bool,
                                 isHidden: Bool,
                                 tier: Tier,
                                 awarded: Int) -> Breakdown {
        let bonus = isHidden ? hiddenBonus : 0
        return Breakdown(range: rolledRange(slot: slot, isTrivialGroup: isTrivialGroup, tier: tier),
                         rolled: awarded - bonus,
                         bonus: bonus,
                         multiplier: effortMultiplier(tier),
                         isRolled: !isTrivialGroup)
    }

    public static func breakdown(_ quest: DailyQuest, tier: Tier, awarded: Int) -> Breakdown {
        breakdown(slot: quest.slot,
                  isTrivialGroup: quest.isTrivialGroup,
                  isHidden: quest.isHiddenSlot,
                  tier: tier,
                  awarded: awarded)
    }

    /// Routines, including degraded ones, get the same multiplier (`PLAN.md` §5).
    public static func routinePoints(basePoints: Int, tier: Tier) -> Int {
        rounded(Double(basePoints) * effortMultiplier(tier))
    }
}
