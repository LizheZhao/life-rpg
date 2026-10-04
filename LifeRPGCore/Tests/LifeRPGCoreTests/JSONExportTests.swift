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
        #expect(snapshot.schemaVersion == 7)
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

    @Test func anOccurrencesChosenDoodleTravels() throws {
        let ctx = try Fixtures.context()
        let chosen = RoutineOccurrence()
        chosen.textSnapshot = "Fix the bike"; chosen.iconKey = "dumbbell"
        let plain = RoutineOccurrence()
        plain.textSnapshot = "Walk"
        ctx.insert(chosen); ctx.insert(plain)
        try ctx.save()

        let decoded = try JSONExport.decode(try JSONExport.data(ctx))
        #expect(decoded.routineOccurrences.first { $0.text == "Fix the bike" }?.iconKey == "dumbbell")
        #expect(decoded.routineOccurrences.first { $0.text == "Walk" }?.iconKey == nil)
    }

    /// One backup a day means the library list is copied into every file, so it carries only what a
    /// reseed cannot give back: the rows history points at, and the rows with a cooldown stamp.
    /// A row nothing refers to and nothing stamped comes back from the seed CSVs on its own.
    @Test func libraryCarriesOnlyWhatHistoryNeeds() throws {
        let ctx = try Fixtures.context()
        let day = "2026-09-18"
        let drawn = Fixtures.quest(ctx, "Drawn today")
        let inGroup = Fixtures.quest(ctx, "In a micro group")
        let rated = Fixtures.quest(ctx, "Only rated")
        Fixtures.quest(ctx, "Only stamped", served: "2026-09-10")
        Fixtures.quest(ctx, "Never touched")

        let q = DailyQuest()
        q.dayKey = day; q.templateID = drawn.id; q.textSnapshot = "Drawn today"
        let group = DailyQuest()
        group.dayKey = day; group.trivialGroup = ["In a micro group"]; group.trivialTemplateIDs = [inGroup.id]
        ctx.insert(q); ctx.insert(group)
        Feedback.rate(ctx, target: .quest, id: rated.id, text: "Only rated", rating: 1, dayKey: day)

        func routine(_ text: String, completed: String? = nil) -> RoutineTask {
            let r = RoutineTask()
            r.text = text; r.lastCompletedDayKey = completed
            ctx.insert(r)
            return r
        }
        let scheduled = routine("Scheduled"), pickedFromTheLibrary = routine("Picked through +")
        let light = routine("A light version"), commented = routine("Only commented")
        routine("Only stamped", completed: "2026-09-12")
        routine("Never touched")
        let o = RoutineOccurrence()
        o.dueDayKey = day; o.routineID = scheduled.id; o.degradedRoutineID = light.id
        let extra = RoutineOccurrence()
        extra.dueDayKey = day; extra.adHocSourceRoutineID = pickedFromTheLibrary.id
        ctx.insert(o); ctx.insert(extra)
        Feedback.comment(ctx, target: .routine, id: commented.id, text: "Only commented", comment: "ok", dayKey: day)
        try ctx.save()

        let library = try #require(try JSONExport.snapshot(ctx).library)
        #expect(library.quests.map(\.text).sorted()
                == ["Drawn today", "In a micro group", "Only rated", "Only stamped"])
        #expect(library.routines.map(\.text).sorted()
                == ["A light version", "Only commented", "Only stamped", "Picked through +", "Scheduled"])
    }

    /// The same file, without the indentation: a third of what a pretty-printed one weighs.
    @Test func theFileIsOneCompactLine() throws {
        let ctx = try Fixtures.context()
        Economy.record(ctx, kind: .penalty, points: -25, dayKey: "2026-09-18", note: "trash")
        try ctx.save()
        let text = try #require(String(data: try JSONExport.data(ctx), encoding: .utf8))
        #expect(!text.contains("\n"))
        #expect(!text.contains("  "))
    }

    @Test func filenameIsDated() {
        #expect(JSONExport.filename(now: Fixtures.date("2026-09-18"), in: Fixtures.tokyo)
                == "LifeRPG-2026-09-18.json")
    }
}
