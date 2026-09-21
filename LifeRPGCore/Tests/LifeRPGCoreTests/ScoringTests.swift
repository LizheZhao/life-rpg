import Foundation
import Testing
@testable import LifeRPGCore

/// Point payouts: the low-tier multiplier, the unmultiplied hidden bonus, half-away-from-zero.
struct ScoringTests {
    @Test func multiplierOnlyAppliesToLowTiers() {
        #expect(Scoring.effortMultiplier(.veryLow) == 1.3)
        #expect(Scoring.effortMultiplier(.low) == 1.3)
        #expect(Scoring.effortMultiplier(.normal) == 1.0)
        #expect(Scoring.effortMultiplier(.high) == 1.0)
    }

    @Test func roundingIsHalfAwayFromZero() {
        #expect(Scoring.rounded(37.5) == 38)          // PLAN's worked penalty example
        #expect(Scoring.rounded(12.5) == 13)
        #expect(Scoring.rounded(-37.5) == -38)
    }

    @Test func rollStaysInsideTheSlotRange() {
        var rng = SeededRNG(seed: 11)
        for slot in [Difficulty.easy, .medium, .hard] {
            for _ in 0..<200 {
                let p = Scoring.questPoints(slot: slot, isTrivialGroup: false, isHidden: false,
                                            tier: .normal, rng: &rng)
                #expect(slot.range.contains(p))
            }
        }
    }

    @Test func trivialGroupScoresTwelveAsAWhole() {
        var rng = SeededRNG(seed: 5)
        #expect(Scoring.questPoints(slot: .easy, isTrivialGroup: true, isHidden: false,
                                    tier: .normal, rng: &rng) == 12)
        // 12 × 1.3 = 15.6 → 16
        #expect(Scoring.questPoints(slot: .easy, isTrivialGroup: true, isHidden: false,
                                    tier: .low, rng: &rng) == 16)
    }

    /// The hidden +10 sits outside the multiplier: at low tier a 12-point T group pays 16, and a
    /// hidden quest pays round(roll × 1.3) + 10, not round((roll + 10) × 1.3).
    @Test func hiddenBonusIsNotMultiplied() {
        var rng = SeededRNG(seed: 2)
        for _ in 0..<200 {
            var a = rng
            var b = rng
            let plain = Scoring.questPoints(slot: .medium, isTrivialGroup: false, isHidden: false,
                                            tier: .low, rng: &a)
            let hidden = Scoring.questPoints(slot: .medium, isTrivialGroup: false, isHidden: true,
                                             tier: .low, rng: &b)
            #expect(hidden - plain == Scoring.hiddenBonus)
            _ = Scoring.questPoints(slot: .easy, isTrivialGroup: false, isHidden: false,
                                    tier: .normal, rng: &rng)     // advance the shared stream
        }
    }

    @Test func routinePointsUseTheSameMultiplier() {
        #expect(Scoring.routinePoints(basePoints: 15, tier: .normal) == 15)
        #expect(Scoring.routinePoints(basePoints: 15, tier: .low) == 20)      // 19.5 → 20
        #expect(Scoring.routinePoints(basePoints: 50, tier: .veryLow) == 65)
    }
}

struct DifficultyCodeTests {
    @Test func codeRoundTripsWithTheCSVSpelling() {
        for d in Difficulty.allCases {
            #expect(Difficulty(csvCode: d.code) == d)
        }
    }

    // MARK: breakdown (what the roll animation draws)

    /// The bar has to be derived from the awarded value, never re-rolled: the roll already
    /// happened and is already in the ledger.
    @Test func breakdownPutsTheAwardedValueInsideItsOwnRange() {
        for slot in [Difficulty.easy, .medium, .hard, .epic] {
            for tier in Tier.allCases {
                var rng = SeededRNG(seed: UInt64(slot.rawValue.count))
                for _ in 0..<40 {
                    let awarded = Scoring.questPoints(slot: slot, isTrivialGroup: false,
                                                      isHidden: false, tier: tier, rng: &rng)
                    let b = Scoring.breakdown(slot: slot, isTrivialGroup: false, isHidden: false,
                                              tier: tier, awarded: awarded)
                    #expect(b.range.contains(b.rolled))
                    #expect(b.awarded == awarded)
                }
            }
        }
    }

    /// The hidden +10 sits outside the bar, because it is never multiplied — drawing it inside
    /// would put the marker past the end on a low-tier day.
    @Test func theHiddenBonusIsSeparatedFromTheRolledPart() {
        let b = Scoring.breakdown(slot: .medium, isTrivialGroup: false, isHidden: true,
                                  tier: .normal, awarded: 31)
        #expect(b.bonus == 10)
        #expect(b.rolled == 21)
        #expect(b.range == 12...30)
        #expect(b.range.contains(b.rolled))
    }

    @Test func aLowTierBarIsScaledSoTheMarkerStaysInside() {
        let b = Scoring.breakdown(slot: .easy, isTrivialGroup: false, isHidden: false,
                                  tier: .low, awarded: 20)          // round(15 × 1.3)
        #expect(b.range == 7...20)                                   // round(5 × 1.3)…round(15 × 1.3)
        #expect(b.multiplier == 1.3)
        #expect(b.rolled == 20)
    }

    /// The T group is 12 for the whole group, not a draw — the view labels it as fixed rather
    /// than animating a roll that never happened.
    @Test func theTrivialGroupReportsItselfAsNotRolled() {
        let normal = Scoring.breakdown(slot: .easy, isTrivialGroup: true, isHidden: false,
                                       tier: .normal, awarded: 12)
        #expect(!normal.isRolled)
        #expect(normal.range == 12...12)

        let low = Scoring.breakdown(slot: .easy, isTrivialGroup: true, isHidden: false,
                                    tier: .low, awarded: 16)
        #expect(low.range == 16...16)
        #expect(low.rolled == 16)
    }

    // MARK: payoutRange (the label on the badge)

    /// The badge promises a span before you do the quest; the roll has to honour it afterwards.
    /// These are the same arithmetic on purpose — one drifting from the other is how the app
    /// starts lying about what something is worth.
    @Test func everyRollLandsInsideTheRangeTheBadgeAdvertised() {
        for slot in [Difficulty.easy, .medium, .hard, .epic] {
            for tier in Tier.allCases {
                for isHidden in [false, true] {
                    let advertised = Scoring.payoutRange(slot: slot, isHidden: isHidden, tier: tier)
                    var rng = SeededRNG(seed: 11)
                    for _ in 0..<60 {
                        let awarded = Scoring.questPoints(slot: slot, isTrivialGroup: false,
                                                          isHidden: isHidden, tier: tier, rng: &rng)
                        #expect(advertised.contains(awarded))
                    }
                }
            }
        }
    }

    @Test func theBadgeRangeMatchesTheRevealsOwnRange() {
        for tier in Tier.allCases {
            var rng = SeededRNG(seed: 2)
            let awarded = Scoring.questPoints(slot: .medium, isTrivialGroup: false,
                                              isHidden: true, tier: tier, rng: &rng)
            let b = Scoring.breakdown(slot: .medium, isTrivialGroup: false, isHidden: true,
                                      tier: tier, awarded: awarded)
            #expect(b.payoutRange == Scoring.payoutRange(slot: .medium, isHidden: true, tier: tier))
        }
    }

    @Test func theHiddenBonusWidensTheBadgeByTen() {
        #expect(Scoring.payoutRange(slot: .medium, tier: .normal) == 12...30)
        #expect(Scoring.payoutRange(slot: .medium, isHidden: true, tier: .normal) == 22...40)
    }

    /// The T group has one value, so the badge prints a number rather than a span.
    @Test func theTrivialGroupRangeIsASinglePoint() {
        #expect(Scoring.payoutRange(slot: .easy, isTrivialGroup: true, tier: .normal) == 12...12)
        #expect(Scoring.payoutRange(slot: .easy, isTrivialGroup: true, tier: .low) == 16...16)
    }

    /// A low-energy day pays more, and the badge has to say so before the fact, not after.
    @Test func aLowTierBadgeIsScaledUp() {
        #expect(Scoring.payoutRange(slot: .hard, tier: .normal) == 25...50)
        #expect(Scoring.payoutRange(slot: .hard, tier: .low) == 33...65)
    }
}
