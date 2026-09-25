import Foundation
import Testing
@testable import LifeRPGCore

/// `PLAN.md` §6 writes the prices out in a table, so they are asserted literally.
struct RewardPricingTests {
    @Test func theTableInThePlan() {
        #expect(RewardPricing.coins(estimatedCost: 100) == 1000)      // a nice meal, drinks
        #expect(RewardPricing.coins(estimatedCost: 750) == 6250)      // a Michelin meal
        #expect(RewardPricing.coins(estimatedCost: 600) == 5500)      // wishlist headphones
        #expect(RewardPricing.coins(estimatedCost: 500) == 5000)      // a short trip, low end
        #expect(RewardPricing.coins(estimatedCost: 1000) == 7500)     // a short trip, high end
        #expect(RewardPricing.coins(estimatedCost: 2000) == 12500)    // new furniture
    }

    /// The knee is continuous: nothing jumps at 500.
    @Test func noJumpAtTheKnee() {
        #expect(RewardPricing.coins(estimatedCost: 499) == 4990)
        #expect(RewardPricing.coins(estimatedCost: 501) == 5005)
    }

    @Test func fractionsRoundUp() {
        #expect(RewardPricing.coins(estimatedCost: 12.34) == 124)     // 123.4 → 124
        #expect(RewardPricing.coins(estimatedCost: 500.1) == 5001)    // 5000.5 → 5001
    }

    @Test func zeroAndNegativeCostNothing() {
        #expect(RewardPricing.coins(estimatedCost: 0) == 0)
        #expect(RewardPricing.coins(estimatedCost: -20) == 0)
    }

    /// One number moves every price.
    @Test func theMultiplierRepricesEverything() {
        #expect(RewardPricing.coins(estimatedCost: 100, multiplier: 8) == 800)
        #expect(RewardPricing.coins(estimatedCost: 750, multiplier: 8) == 5000)   // 4000 + 250 × 4
    }

    @Test func virtualItemsUseTheirFixedPrice() {
        let freeze = Reward()
        freeze.virtualKind = "streak_freeze"
        freeze.fixedCoins = 300
        #expect(RewardPricing.coins(for: freeze) == 300)

        let meal = Reward()
        meal.estimatedCost = 100
        #expect(RewardPricing.coins(for: meal) == 1000)
    }
}
