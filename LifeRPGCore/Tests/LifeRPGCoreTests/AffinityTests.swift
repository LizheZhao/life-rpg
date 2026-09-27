import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// Affinity = mean of the last three ratings, rounded (decided with the user).
struct AffinityTests {
    private func ratings(_ values: [Int]) -> [QuestRating] {
        values.enumerated().map { i, v in
            let r = QuestRating()
            r.rating = v
            r.timestamp = Fixtures.date("2026-09-01").addingTimeInterval(Double(i) * 86_400)
            return r
        }
    }

    @Test func noRatingsIsNeutral() {
        #expect(Affinity.derive([]) == 0)
    }

    /// Oldest first in each array; only the newest three count.
    @Test func theLastThreeAveragedAndRounded() {
        #expect(Affinity.derive(ratings([2])) == 2)
        #expect(Affinity.derive(ratings([2, 2, -2])) == 1)          // 0.67 → 1
        #expect(Affinity.derive(ratings([-2, 2, 2, 2])) == 2)       // the −2 has aged out
        #expect(Affinity.derive(ratings([2, -2, -2, -1])) == -2)    // −1.67 → −2
        #expect(Affinity.derive(ratings([1, -1, 0])) == 0)
    }

    /// .5 only happens with two ratings; it rounds away from zero.
    @Test func halvesRoundAwayFromZero() {
        #expect(Affinity.derive(ratings([1, 0])) == 1)
        #expect(Affinity.derive(ratings([-1, 0])) == -1)
        #expect(Affinity.derive(ratings([-2, -1])) == -2)
    }

    /// Newest by timestamp, whatever order the rows arrive in.
    @Test func orderIsByTimestampNotArrayPosition() {
        #expect(Affinity.derive(ratings([-2, 2, 2, 2]).reversed()) == 2)
    }

    @Test func syncWritesEveryQuestTemplateAndIgnoresRoutines() throws {
        let ctx = try Fixtures.context()
        let walk = Fixtures.quest(ctx, "Walk")
        let sauna = Fixtures.quest(ctx, "Sauna")
        let untouched = Fixtures.quest(ctx, "Untouched", affinity: 2)   // a stale value gets reset
        for (i, v) in [2, 1, 2].enumerated() {
            Feedback.rate(ctx, target: .quest, id: walk.id, text: walk.text, rating: v,
                          dayKey: "2026-09-1\(i)", now: Fixtures.date("2026-09-1\(i)"))
        }
        Feedback.rate(ctx, target: .quest, id: sauna.id, text: sauna.text, rating: -2, dayKey: "2026-09-10")
        Feedback.rate(ctx, target: .routine, id: UUID(), text: "Run", rating: 2, dayKey: "2026-09-10")
        try ctx.save()

        #expect(try Affinity.sync(ctx) == 3)
        #expect(walk.affinity == 2)         // 1.67 → 2
        #expect(sauna.affinity == -2)
        #expect(untouched.affinity == 0)
        #expect(try Affinity.sync(ctx) == 0)
    }

    /// Generating a day syncs first, so the morning's draw already weighs yesterday's ratings.
    @Test func generatingADaySyncsBeforeDrawing() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        let t = try #require(try ctx.fetch(FetchDescriptor<QuestTemplate>()).first)
        Feedback.rate(ctx, target: .quest, id: t.id, text: t.text, rating: -2, dayKey: "2026-09-17")
        try ctx.save()
        var rng = SeededRNG(seed: 1)
        try DayService.ensureToday(ctx, now: Fixtures.date("2026-09-18"), in: Fixtures.tokyo, rng: &rng)
        #expect(t.affinity == -2)
    }
}
