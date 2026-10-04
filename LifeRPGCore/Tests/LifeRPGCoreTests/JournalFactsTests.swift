import Foundation
import Testing
@testable import LifeRPGCore

struct JournalFactsTests {
    typealias F = JournalFixtures

    @Test func aDayWithNothingRatedHasNoBucket() {
        let facts = JournalFacts(F.signals(tier: .low, quests: [F.quest("Walk")]))
        #expect(facts == JournalFacts(tier: .low, completedCount: 1, ratingBucket: nil,
                                      hasChoiceItem: false, hasPhotoItem: false, hasSkippedItem: false))
    }

    @Test func theBucketCutsAreHalfAPointEitherSide() {
        func bucket(_ ratings: [Int]) -> JournalFacts.RatingBucket? {
            let quests = ratings.indices.map { F.quest("Q\($0)") }
            return JournalFacts(F.signals(quests: quests,
                                          ratings: zip(quests, ratings).map { F.rating(of: $0.id, $1) })).ratingBucket
        }
        #expect(bucket([-1, 0]) == .negative)       // -0.5
        #expect(bucket([-1, 1]) == .mixed)          // 0
        #expect(bucket([0, 0, -1]) == .mixed)       // -0.33
        #expect(bucket([1, 0]) == .positive)        // 0.5
        #expect(bucket([2]) == .positive)
    }

    @Test func aPhotoItemIsAlsoAChoiceItemAndASkippedRoutineIsFlagged() {
        let photo = F.quest("Take a photo of the sky")
        let notice = F.quest("Notice three green things")
        let missed = F.occurrence("Trash", due: "2026-09-15", skipped: true)
        let ledger = [F.skipEntry(for: missed, on: F.day)]
        let both = JournalFacts(F.signals(quests: [photo], occurrences: [missed], ledger: ledger))
        #expect(both.hasChoiceItem && both.hasPhotoItem && both.hasSkippedItem)
        let onlyNotice = JournalFacts(F.signals(quests: [notice]))
        #expect(onlyNotice.hasChoiceItem && !onlyNotice.hasPhotoItem && !onlyNotice.hasSkippedItem)
    }
}
