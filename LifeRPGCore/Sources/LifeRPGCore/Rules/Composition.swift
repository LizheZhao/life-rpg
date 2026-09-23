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
    /// `plan` truncates it, so it defines what gets dropped when there are fewer than 3 slots —
    /// and what is kept on the heaviest days is the bottom of the ladder.
    ///
    /// T is simply the rung below E, not an overlay on an E slot: micro-actions are what a day
    /// you can barely function on is for. A `.trivial` slot holds a group of three (`PLAN.md` §2).
    public static func table(_ tier: Tier) -> [Difficulty] {
        switch tier {
        case .veryLow: [.trivial, .easy, .easy]
        case .low:     [.trivial, .easy, .medium]
        case .normal:  [.easy, .medium, .hard]
        case .high:    [.medium, .medium, .hard]
        }
    }

    /// Today's slots, easiest first. A `.trivial` one is the T group.
    ///
    /// Fewer than 3 slots **drops from the hard end** — 1 slot at `normal` is an E, 2 slots are
    /// E + M. That is the decision on `PLAN.md` §12's weekend-H question: no H is guaranteed on
    /// weekends, so `weekend_only` H quests stay rare until there is enough real data to retune.
    /// Nothing here is random any more: the tier alone decides the day's shape.
    public static func plan(tier: Tier, slots: Int) -> [Difficulty] {
        Array(table(tier).prefix(max(0, slots)))
    }
}
