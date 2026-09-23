import Foundation
import Testing
@testable import LifeRPGCore

/// The slot count formula and the tier table, including what gets dropped when the routine load
/// squeezes the day down to one or two slots.
struct CompositionTests {
    @Test func slotCountFollowsRoutineLoad() {
        // PLAN §3: Friday with 1 routine → 3, Wednesday with 3 → 2, Saturday with 5 → 1.
        #expect(Composition.slots(routineLoad: 0) == 3)
        #expect(Composition.slots(routineLoad: 1) == 3)
        #expect(Composition.slots(routineLoad: 2) == 3)
        #expect(Composition.slots(routineLoad: 3) == 2)
        #expect(Composition.slots(routineLoad: 4) == 2)
        #expect(Composition.slots(routineLoad: 5) == 1)
        #expect(Composition.slots(routineLoad: 12) == 1)   // never below 1
    }

    /// T is the rung below E, in the table rather than an overlay on an E slot: micro-actions
    /// are what a day you can barely function on is for.
    @Test func tableMatchesPlan() {
        #expect(Composition.table(.veryLow) == [.trivial, .easy, .easy])
        #expect(Composition.table(.low) == [.trivial, .easy, .medium])
        #expect(Composition.table(.normal) == [.easy, .medium, .hard])
        #expect(Composition.table(.high) == [.medium, .medium, .hard])
    }

    /// The design call on PLAN §12: fewer slots drop from the **hard** end, so no H is guaranteed
    /// on a weekend. Saturday's single slot is an E, Sunday's two are E + M.
    @Test func fewerSlotsDropTheHardEnd() {
        #expect(Composition.plan(tier: .normal, slots: 1) == [.easy])
        #expect(Composition.plan(tier: .normal, slots: 2) == [.easy, .medium])
        #expect(Composition.plan(tier: .normal, slots: 3) == [.easy, .medium, .hard])
    }

    /// A heavy routine day at low energy keeps the bottom of the ladder: the one slot left is
    /// the T group.
    @Test func aSqueezedLowDayKeepsTheTrivialSlot() {
        #expect(Composition.plan(tier: .low, slots: 1) == [.trivial])
        #expect(Composition.plan(tier: .veryLow, slots: 2) == [.trivial, .easy])
    }

    /// Low and very low always have their T slot; normal and high never do — nothing random
    /// decides it any more.
    @Test func trivialBelongsToTheLowTiers() {
        #expect(Composition.plan(tier: .veryLow, slots: 3).filter { $0 == .trivial }.count == 1)
        #expect(Composition.plan(tier: .low, slots: 3).filter { $0 == .trivial }.count == 1)
        #expect(!Composition.plan(tier: .normal, slots: 3).contains(.trivial))
        #expect(!Composition.plan(tier: .high, slots: 3).contains(.trivial))
    }
}
