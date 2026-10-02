import Testing
@testable import LifeRPGCore

/// The level card's bar and dot grid read these; the view never does the division itself.
struct LevelProgressTests {
    @Test func progressRunsFromZeroToJustBelowOneWithinALevel() {
        #expect(Economy.levelProgress(totalEarned: 0) == 0)
        #expect(abs(Economy.levelProgress(totalEarned: 30) - 0.5) < 1e-12)     // level 1 spans 0..<60
        #expect(abs(Economy.levelProgress(totalEarned: 59) - 59.0 / 60.0) < 1e-12)
        #expect(Economy.levelProgress(totalEarned: 59) > 0.983)
        #expect(Economy.levelProgress(totalEarned: 59) < 0.984)
    }

    @Test func progressResetsExactlyAtTheLevelBoundary() {
        #expect(Economy.levelProgress(totalEarned: 60) == 0)                   // level 2 starts at 60
        #expect(abs(Economy.levelProgress(totalEarned: 150) - 0.5) < 1e-12)    // level 2 spans 60..<240
        #expect(Economy.levelProgress(totalEarned: 240) == 0)                  // level 3 starts at 240
        #expect(abs(Economy.levelProgress(totalEarned: 390) - 0.5) < 1e-12)    // level 3 spans 240..<540
    }

    @Test func negativeTotalsClampToZero() {
        #expect(Economy.levelProgress(totalEarned: -10) == 0)
        #expect(Economy.levelDots(totalEarned: -10) == 0)
    }

    @Test func dotsAreTheFlooredFractionOfTwenty() {
        #expect(Economy.levelDots(totalEarned: 0) == 0)
        #expect(Economy.levelDots(totalEarned: 2) == 0)       // 2/60 of 20 dots is 0.67
        #expect(Economy.levelDots(totalEarned: 3) == 1)       // each dot is 3 points at level 1
        #expect(Economy.levelDots(totalEarned: 30) == 10)
        #expect(Economy.levelDots(totalEarned: 59) == 19)
        #expect(Economy.levelDots(totalEarned: 60) == 0)      // the grid empties on level up
        #expect(Economy.levelDots(totalEarned: 69) == 1)      // level 2: 180 points, 9 per dot
        #expect(Economy.levelDots(totalEarned: 68) == 0)
        #expect(Economy.levelDots(totalEarned: 150) == 10)
        #expect(Economy.levelDots(totalEarned: 239) == 19)
    }

    @Test func dotCountIsConfigurable() {
        #expect(Economy.levelDots(totalEarned: 30, count: 10) == 5)
        #expect(Economy.levelDots(totalEarned: 59, count: 10) == 9)
    }
}
