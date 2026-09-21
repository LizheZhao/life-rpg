import Foundation
import Testing
@testable import LifeRPGCore

/// The CSV side of the feedback export. Its one hard requirement is that a comment containing
/// commas, quotes or newlines survives — that is exactly the kind of text people actually write.
struct CSVExportTests {
    @Test func commentsWithCommasAndQuotesRoundTripThroughTheParser() throws {
        let ctx = try Fixtures.context()
        let awkward = "too hot, and \"way\" too long\nsecond line"
        Feedback.comment(ctx, target: .quest, id: UUID(), text: "sauna, 80°",
                         comment: awkward, dayKey: "2026-09-18")
        try ctx.save()

        let (header, rows) = CSV.records(try CSVExport.comments(ctx))
        #expect(header.contains("comment"))
        #expect(rows.count == 1)
        #expect(rows[0]["comment"] == awkward)
        #expect(rows[0]["text"] == "sauna, 80°")
        #expect(rows[0]["day_key"] == "2026-09-18")
    }

    @Test func ratingsExportEveryRowNotJustTheNewest() throws {
        let ctx = try Fixtures.context()
        let id = UUID()
        Feedback.rate(ctx, target: .quest, id: id, text: "sauna", rating: -2, dayKey: "2026-01-10")
        Feedback.rate(ctx, target: .quest, id: id, text: "sauna", rating: 2, dayKey: "2026-09-10")
        try ctx.save()

        let (_, rows) = CSV.records(try CSVExport.ratings(ctx))
        #expect(rows.count == 2)
        #expect(rows.map { $0["rating"] } == ["-2", "2"])      // oldest first
        #expect(rows.allSatisfy { $0["target_kind"] == "quest" })
    }

    @Test func anEmptyLogStillExportsItsHeader() throws {
        let ctx = try Fixtures.context()
        let (header, rows) = CSV.records(try CSVExport.ratings(ctx))
        #expect(header == ["day_key", "target_kind", "text", "rating", "timestamp", "target_id"])
        #expect(rows.isEmpty)
    }

    @Test func filesAreDated() throws {
        let ctx = try Fixtures.context()
        let files = try CSVExport.files(ctx, now: Fixtures.date("2026-09-18"), in: Fixtures.tokyo)
        #expect(files.map(\.name) == ["ratings-2026-09-18.csv", "comments-2026-09-18.csv"])
        #expect(CSVExport.folderName(now: Fixtures.date("2026-09-18"), in: Fixtures.tokyo)
                == "LifeRPG-feedback-2026-09-18")
    }
}
