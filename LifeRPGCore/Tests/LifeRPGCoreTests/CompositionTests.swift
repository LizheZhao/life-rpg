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

    @Test func tableMatchesPlan() {
        #expect(Composition.table(.veryLow) == [.easy, .easy, .easy])
        #expect(Composition.table(.low) == [.easy, .easy, .medium])
        #expect(Composition.table(.normal) == [.easy, .medium, .hard])
        #expect(Composition.table(.high) == [.medium, .medium, .hard])
    }

    /// The design call on PLAN §12: fewer slots drop from the **hard** end, so no H is guaranteed
    /// on a weekend. Saturday's single slot is an E, Sunday's two are E + M.
    @Test func fewerSlotsDropTheHardEnd() {
        var rng = SeededRNG(seed: 1)
        let one = Composition.plan(tier: .normal, slots: 1, rng: &rng).map(\.difficulty)
        let two = Composition.plan(tier: .normal, slots: 2, rng: &rng).map(\.difficulty)
        let three = Composition.plan(tier: .normal, slots: 3, rng: &rng).map(\.difficulty)
        #expect(one == [.easy])
        #expect(two == [.easy, .medium])
        #expect(three == [.easy, .medium, .hard])
    }

    @Test func trivialGroupIsGuaranteedAtVeryLow() {
        for seed in UInt64(0)..<20 {
            var rng = SeededRNG(seed: seed)
            let plan = Composition.plan(tier: .veryLow, slots: 3, rng: &rng)
            #expect(plan.filter(\.isTrivialGroup).count == 1)
            #expect(plan.allSatisfy { $0.difficulty == .easy })
        }
    }

    /// A T group only ever takes an E slot — at `high` there is none, so it can't appear.
    @Test func trivialGroupNeedsAnEasySlot() {
        for seed in UInt64(0)..<20 {
            var rng = SeededRNG(seed: seed)
            #expect(Composition.plan(tier: .high, slots: 3, rng: &rng).allSatisfy { !$0.isTrivialGroup })
        }
    }

    @Test func trivialGroupShowsUpRoughlyFortyPercent() {
        var rng = SeededRNG(seed: 42)
        var hits = 0
        for _ in 0..<2000 where Composition.plan(tier: .normal, slots: 3, rng: &rng).contains(where: \.isTrivialGroup) {
            hits += 1
        }
        #expect((700...900).contains(hits))     // 40% of 2000, generous band
    }

    @Test func intensityNarrowsWithTierAndCycle() {
        #expect(Composition.allowedIntensities(tier: .normal, onCycle: false) == [.low, .medium, .high])
        #expect(Composition.allowedIntensities(tier: .low, onCycle: false) == [.low, .medium])
        #expect(Composition.allowedIntensities(tier: .veryLow, onCycle: false) == [.low])
        // On cycle the tier is untouched but high intensity is out (PLAN §5).
        #expect(Composition.allowedIntensities(tier: .high, onCycle: true) == [.low, .medium])
    }
}
