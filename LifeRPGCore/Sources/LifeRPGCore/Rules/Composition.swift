import Foundation

/// What today's random slots look like, before anything is drawn into them: how many there are,
/// which difficulty pool each one samples from, and whether one of them is a T group.
public enum Composition {
    /// `randomSlots = clamp(4 - ceil(dueRoutineCount / 2), 1, 3)` (`PLAN.md` §3).
    /// `routineLoad` counts every **active** routine due that day, including `countsForClear = false`.
    public static func slots(routineLoad: Int) -> Int {
        let load = max(0, routineLoad)
        return max(1, min(3, 4 - Int(ceil(Double(load) / 2.0))))
    }

    /// The composition table from `PLAN.md` §5, **ordered easy → hard**. The order is load-bearing:
    /// `plan` truncates it, so it defines what gets dropped when there are fewer than 3 slots.
    public static func table(_ tier: Tier) -> [Difficulty] {
        switch tier {
        case .veryLow: [.easy, .easy, .easy]
        case .low:     [.easy, .easy, .medium]
        case .normal:  [.easy, .medium, .hard]
        case .high:    [.medium, .medium, .hard]
        }
    }

    /// Chance that a T group takes one E slot on a non-`veryLow` day (`PLAN.md` §12, to be tuned
    /// once there is real usage). At `veryLow` the group is guaranteed instead.
    public static let trivialGroupChance = 0.4

    /// One random slot: the pool to draw from, and whether it holds a T group rather than a single
    /// quest. A T group always sits in an E slot and scores 12 as a whole (`PLAN.md` §2).
    public struct Slot: Equatable, Sendable {
        public var difficulty: Difficulty
        public var isTrivialGroup: Bool

        public init(_ difficulty: Difficulty, isTrivialGroup: Bool = false) {
            self.difficulty = difficulty
            self.isTrivialGroup = isTrivialGroup
        }
    }

    /// Today's slots, easy first.
    ///
    /// Fewer than 3 slots **drops from the hard end** — 1 slot at `normal` is an E, 2 slots are
    /// E + M. That is the decision on `PLAN.md` §12's weekend-H question: no H is guaranteed on
    /// weekends, so `weekend_only` H quests stay rare until there is enough real data to retune.
    public static func plan(tier: Tier, slots: Int,
                            rng: inout some RandomNumberGenerator) -> [Slot] {
        var out = table(tier).prefix(max(0, slots)).map { Slot($0) }
        guard let easySlot = out.firstIndex(where: { $0.difficulty == .easy }) else { return out }
        let trivial = tier == .veryLow || Double.random(in: 0..<1, using: &rng) < trivialGroupChance
        if trivial { out[easySlot].isTrivialGroup = true }
        return out
    }
}
