import Testing
@testable import LifeRPGCore

/// The payout reel's pure values: throwaway frames and the decorative neighbours around the landed
/// number. Neither is ever a payout, so both are checked against the one thing that is.
struct PayoutReelTests {
    @Test(arguments: [UInt64(1), 7, 42, 2026, 90_001])
    func framesStayInsideTheRangeAndNeverEndOnTheAwardedValue(seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        for awarded in [12, 18, 30] {
            let frames = PayoutReel.frames(range: 12...30, awarded: awarded, count: 16, using: &rng)
            #expect(frames.count == 16)
            #expect(frames.allSatisfy { (12...30).contains($0) })
            #expect(frames.last != awarded)
        }
    }

    @Test func noFrameRepeatsTheOneBeforeIt() {
        var rng = SeededRNG(seed: 5)
        for _ in 0..<200 {
            let frames = PayoutReel.frames(range: 5...6, awarded: 5, count: 12, using: &rng)
            #expect(zip(frames, frames.dropFirst()).allSatisfy { $0 != $1 })
        }
    }

    @Test func aTwoValueRangeAlternatesAndEndsOnTheOtherOne() {
        var rng = SeededRNG(seed: 11)
        let frames = PayoutReel.frames(range: 5...6, awarded: 5, count: 4, using: &rng)
        #expect(frames == [5, 6, 5, 6])
    }

    @Test func aSingleValueRangeHasNothingToRoll() {
        var rng = SeededRNG(seed: 3)
        #expect(PayoutReel.frames(range: 12...12, awarded: 12, count: 16, using: &rng).isEmpty)
    }

    @Test func zeroFramesAreAskedForZeroAreReturned() {
        var rng = SeededRNG(seed: 3)
        #expect(PayoutReel.frames(range: 12...30, awarded: 18, count: 0, using: &rng).isEmpty)
    }

    @Test func theSameSeedGivesTheSameFrames() {
        var a = SeededRNG(seed: 99), b = SeededRNG(seed: 99)
        #expect(PayoutReel.frames(range: 1...40, awarded: 9, count: 10, using: &a)
                == PayoutReel.frames(range: 1...40, awarded: 9, count: 10, using: &b))
    }

    // MARK: neighbours

    @Test func theNeighboursOfAnInteriorValueAreOneEitherSide() {
        let n = PayoutReel.neighbours(of: 18, in: 12...30)
        #expect(n.before == 17)
        #expect(n.after == 19)
    }

    @Test func theEdgesOfTheRangeHaveNoNeighbourPastThem() {
        let low = PayoutReel.neighbours(of: 12, in: 12...30)
        #expect(low.before == nil)
        #expect(low.after == 13)
        let high = PayoutReel.neighbours(of: 30, in: 12...30)
        #expect(high.before == 29)
        #expect(high.after == nil)
    }

    @Test func aFixedPayoutHasNoNeighboursAtAll() {
        let n = PayoutReel.neighbours(of: 12, in: 12...12)
        #expect(n.before == nil)
        #expect(n.after == nil)
    }

    @Test func aNeighbourIsNeverTheAwardedValueAndIsAlwaysInTheRange() {
        for awarded in 5...15 {
            let n = PayoutReel.neighbours(of: awarded, in: 5...15)
            for value in [n.before, n.after].compactMap({ $0 }) {
                #expect(value != awarded)
                #expect((5...15).contains(value))
            }
        }
    }
}
