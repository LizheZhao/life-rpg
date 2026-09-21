import Foundation
import Testing
@testable import LifeRPGCore

/// The export is the only way history leaves the phone before Stage 6, so it has to contain the
/// whole of it — and stay decodable.
struct JSONExportTests {
    @Test func snapshotCarriesTheHistoryTables() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 1)
        try DayService.ensureToday(ctx, now: Fixtures.date("2026-09-18"), in: Fixtures.tokyo, rng: &rng)
        for quest in try DayService.quests(on: "2026-09-18", in: ctx) {
            quest.trivialDone = quest.trivialDone.map { _ in true }
            try Completion.complete(quest, tier: .normal, in: ctx, rng: &rng)
        }

        let snapshot = try JSONExport.snapshot(ctx)
        #expect(snapshot.schemaVersion == 2)
        #expect(snapshot.dailyContexts.count == 1)
        #expect(snapshot.dailyQuests.count == 3)
        #expect(snapshot.ledger.count == 3)
        #expect(snapshot.ledger.reduce(0) { $0 + $1.points } == (try Economy.balance(ctx)))
        #expect(snapshot.dailyQuests.allSatisfy { $0.completedAt != nil })
    }

    @Test func dataRoundTrips() throws {
        let ctx = try Fixtures.context()
        Economy.record(ctx, kind: .penalty, points: -25, dayKey: "2026-09-18", note: "trash")
        try ctx.save()

        let data = try JSONExport.data(ctx)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(JSONExport.Snapshot.self, from: data)
        #expect(decoded.ledger.map(\.points) == [-25])
        #expect(decoded.ledger[0].note == "trash")
    }

    @Test func filenameIsDated() {
        #expect(JSONExport.filename(now: Fixtures.date("2026-09-18"), in: Fixtures.tokyo)
                == "LifeRPG-2026-09-18.json")
    }
}
