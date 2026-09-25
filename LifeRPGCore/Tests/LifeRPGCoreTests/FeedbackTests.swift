import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// Ratings and comments are an append-only log, not a field on the template. The point of the dates
/// is that "how do I feel about this now" and "what has been landing well lately" are different
/// questions, and a single overwritten field can only answer the first.
struct FeedbackTests {
    @Test func aChangedOpinionIsANewRowNotAnOverwrite() throws {
        let ctx = try Fixtures.context()
        let walk = Fixtures.quest(ctx, "Go for a walk")

        Feedback.rate(ctx, target: .quest, id: walk.id, text: walk.text, rating: -1,
                      dayKey: "2026-03-01", now: Fixtures.date("2026-03-01"))
        Feedback.rate(ctx, target: .quest, id: walk.id, text: walk.text, rating: 2,
                      dayKey: "2026-09-01", now: Fixtures.date("2026-09-01"))
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<QuestRating>()).count == 2)
        let latest = try #require(try Feedback.latestRatings(ctx)[walk.id])
        #expect(latest.rating == 2)
        #expect(latest.dayKey == "2026-09-01")
    }

    @Test func ratingsAreClampedToTheSamplingScale() throws {
        let ctx = try Fixtures.context()
        let row = Feedback.rate(ctx, target: .quest, id: UUID(), text: "x", rating: 7, dayKey: "2026-09-18")
        #expect(row.rating == 2)
        #expect(Feedback.rate(ctx, target: .quest, id: UUID(), text: "y", rating: -9,
                              dayKey: "2026-09-18").rating == -2)
    }

    /// The window is what makes "lately" mean anything: an old bad score drops out of it.
    @Test func topRatedHonoursTheWindow() throws {
        let ctx = try Fixtures.context()
        Feedback.rate(ctx, target: .quest, id: UUID(), text: "sauna", rating: -2, dayKey: "2026-01-10")
        Feedback.rate(ctx, target: .quest, id: UUID(), text: "sauna", rating: 2, dayKey: "2026-09-10")
        Feedback.rate(ctx, target: .quest, id: UUID(), text: "cold plunge", rating: 1, dayKey: "2026-09-11")
        try ctx.save()

        let allTime = try Feedback.topRated(ctx)
        #expect(allTime.first?.text == "cold plunge")          // sauna averages 0 over all of history
        let recent = try Feedback.topRated(ctx, since: "2026-09-01")
        #expect(recent.first?.text == "sauna")                 // …but 2.0 since September
        #expect(recent.first?.count == 1)
    }

    @Test func routineFeedbackIsFilteredSeparately() throws {
        let ctx = try Fixtures.context()
        Feedback.rate(ctx, target: .quest, id: UUID(), text: "sauna", rating: 2, dayKey: "2026-09-10")
        Feedback.rate(ctx, target: .routine, id: UUID(), text: "take out the trash", rating: -2,
                      dayKey: "2026-09-10")
        try ctx.save()

        #expect(try Feedback.topRated(ctx, target: .quest).map(\.text) == ["sauna"])
        #expect(try Feedback.topRated(ctx, target: .routine).map(\.text) == ["take out the trash"])
    }

    @Test func commentsReadNewestFirst() throws {
        let ctx = try Fixtures.context()
        let id = UUID()
        Feedback.comment(ctx, target: .quest, id: id, text: "sauna", comment: "too hot",
                         dayKey: "2026-09-10", now: Fixtures.date("2026-09-10"))
        Feedback.comment(ctx, target: .quest, id: id, text: "sauna", comment: "better at 80°",
                         dayKey: "2026-09-17", now: Fixtures.date("2026-09-17"))
        Feedback.comment(ctx, target: .quest, id: UUID(), text: "other", comment: "unrelated",
                         dayKey: "2026-09-17")
        try ctx.save()

        #expect(try Feedback.comments(ctx, for: id).map(\.comment) == ["better at 80°", "too hot"])
    }

    /// The library page rates from outside a completion: no `questID`, and every rating stays as
    /// history, newest first. The page and the store read the same rows the same way.
    @Test func ratingHistoryReadsNewestFirstAndAgreesWithTheStore() throws {
        let ctx = try Fixtures.context()
        let walk = Fixtures.quest(ctx, "Go for a walk")
        for (day, value) in [("2026-09-01", -1), ("2026-09-10", 1), ("2026-09-05", 0)] {
            Feedback.rate(ctx, target: .quest, id: walk.id, text: walk.text, rating: value,
                          dayKey: day, now: Fixtures.date(day))
        }
        Feedback.rate(ctx, target: .quest, id: UUID(), text: "other", rating: 2, dayKey: "2026-09-11")
        try ctx.save()

        let rows = try ctx.fetch(FetchDescriptor<QuestRating>())
        #expect(Feedback.ratings(rows, for: walk.id).map(\.rating) == [1, 0, -1])
        #expect(Feedback.ratings(rows, for: walk.id).allSatisfy { $0.questID == nil })
        #expect(Feedback.latestRatings(rows)[walk.id]?.rating == 1)
        #expect(Feedback.latestRatings(rows).mapValues(\.id) == (try Feedback.latestRatings(ctx)).mapValues(\.id))
    }

    /// The feedback tables are the one thing the seed CSVs cannot rebuild, so they have to ride
    /// along in the export.
    @Test func feedbackIsCarriedInTheJSONExport() throws {
        let ctx = try Fixtures.context()
        // Whole-second timestamps: ISO 8601 has no sub-second field, so a `Date()` default would
        // fail the round trip on precision alone and say nothing about the export.
        let when = Fixtures.date("2026-09-10")
        let questID = UUID()
        Feedback.rate(ctx, target: .quest, id: UUID(), questID: questID, text: "sauna", rating: 2,
                      dayKey: "2026-09-10", now: when)
        Feedback.comment(ctx, target: .routine, id: UUID(), text: "trash", comment: "bins were full",
                         dayKey: "2026-09-10", now: when)
        try ctx.save()

        let snapshot = try JSONExport.snapshot(ctx, now: when)
        #expect(snapshot.ratings.count == 1)
        #expect(snapshot.ratings.first?.targetKind == "quest")
        // Without this the link to the completion that prompted the rating dies in the export,
        // and a restore could only say "this quest, some time in September".
        #expect(snapshot.ratings.first?.questID == questID)
        #expect(snapshot.comments.count == 1)
        #expect(snapshot.comments.first?.targetKind == "routine")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(JSONExport.Snapshot.self,
                                         from: try JSONExport.data(ctx, now: when))
        #expect(decoded.ratings == snapshot.ratings)
        #expect(decoded.comments == snapshot.comments)
    }
}
