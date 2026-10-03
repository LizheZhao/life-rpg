import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// The one table that joins what happened to what it was: a row per quest and routine, with the
/// library row it came from on the same line. The app keeps the two apart (the records point at the
/// library by id); this is where they are put together, for reading outside the app.
struct HistoryTableTests {
    private let day = "2026-09-18"

    private func table(_ ctx: ModelContext) throws -> [[String: String]] {
        CSV.records(try CSVExport.history(ctx)).rows
    }

    private func row(_ rows: [[String: String]], _ text: String) throws -> [String: String] {
        try #require(rows.first { $0["text"] == text })
    }

    @Test func aQuestCarriesItsLibraryRowAndItsRating() throws {
        let ctx = try Fixtures.context()
        let t = Fixtures.quest(ctx, "Call grandma", .hard, active: false)
        t.origin = .user
        let q = DailyQuest()
        q.dayKey = day; q.weekKey = "2026-W38"; q.slot = .hard; q.templateID = t.id
        q.textSnapshot = "Call grandma"; q.points = 31; q.completedAt = Fixtures.date(day)
        ctx.insert(q)
        Feedback.rate(ctx, target: .quest, id: t.id, questID: q.id, text: "Call grandma", rating: 2, dayKey: day)
        try ctx.save()

        let r = try row(try table(ctx), "Call grandma")
        #expect(r["day_key"] == day && r["kind"] == "quest" && r["status"] == "done" && r["points"] == "31")
        #expect(r["library_difficulty"] == "H" && r["library_origin"] == "user" && r["library_active"] == "FALSE")
        #expect(r["rating"] == "2")
    }

    @Test func aRoutineSaysWhatBecameOfIt() throws {
        let ctx = try Fixtures.context()
        let routine = RoutineTask()
        routine.text = "Trash"; routine.difficulty = .easy; routine.basePoints = 5
        ctx.insert(routine)
        func occurrence(_ text: String, due: String) -> RoutineOccurrence {
            let o = RoutineOccurrence()
            o.textSnapshot = text; o.dueDayKey = due; o.weekKey = "2026-W38"; o.basePoints = 20
            o.routineID = routine.id
            ctx.insert(o)
            return o
        }
        let late = occurrence("late", due: "2026-09-16")
        late.completedDayKey = day; late.awardedPoints = 10; late.penaltyApplied = 10
        let gaveUp = occurrence("gave up", due: "2026-09-15")
        gaveUp.skipped = true; gaveUp.penaltyApplied = 45
        Economy.record(ctx, kind: .skip, points: 0, dayKey: "2026-09-18", refID: gaveUp.id)
        let cancelled = occurrence("cancelled", due: "2026-09-17")
        cancelled.skipped = true
        let open = occurrence("open", due: day)
        try ctx.save()

        let rows = try table(ctx)
        #expect(try row(rows, "late")["status"] == "done late")
        #expect(try row(rows, "late")["points"] == "10" && row(rows, "late")["penalty"] == "10")
        #expect(try row(rows, "gave up")["status"] == "missed" && row(rows, "gave up")["penalty"] == "45")
        #expect(try row(rows, "cancelled")["status"] == "cancelled")
        #expect(try row(rows, "open")["status"] == "open" && row(rows, "open")["base_points"] == "20")
        #expect(try row(rows, "open")["library_origin"] == "seed" && row(rows, "open")["kind"] == "routine")
        _ = open
    }

    @Test func extrasSwapsAndCustomTasksAreToldApart() throws {
        let ctx = try Fixtures.context()
        let slot = DailyQuest()
        slot.dayKey = day; slot.weekKey = "2026-W38"; slot.slot = .medium; slot.textSnapshot = "slot"
        ctx.insert(slot)
        try AdHoc.add(.custom(text: "An extra", difficulty: .easy), on: day, in: ctx, timeZone: Fixtures.tokyo)
        try AdHoc.replace(slot, with: .custom(text: "A swap", difficulty: .medium), in: ctx, timeZone: Fixtures.tokyo)

        let rows = try table(ctx)
        #expect(try row(rows, "An extra")["kind"] == "extra")
        #expect(try row(rows, "A swap")["kind"] == "swap")
        // A custom task has no library row to join.
        #expect(try row(rows, "An extra")["library_origin"] == "" && row(rows, "An extra")["library_difficulty"] == "")
        #expect(try row(rows, "slot")["status"] == "replaced")
    }

    @Test func aGroupOfMicroActionsIsOneRow() throws {
        let ctx = try Fixtures.context()
        let g = DailyQuest()
        g.dayKey = day; g.weekKey = "2026-W38"; g.slot = .trivial
        g.trivialGroup = ["a", "b", "c"]; g.trivialDone = [true, false, false]
        ctx.insert(g)
        try ctx.save()
        let r = try row(try table(ctx), "a | b | c")
        #expect(r["kind"] == "micro-actions" && r["status"] == "open")
    }

    /// The table is the whole library too: a row nothing ever drew still has a line, so a quest
    /// the user saved but never met is not lost from it.
    @Test func libraryRowsNeverUsedStillHaveALine() throws {
        let ctx = try Fixtures.context()
        let t = Fixtures.quest(ctx, "Never drawn", .easy)
        t.origin = .user
        let r = RoutineTask()
        r.text = "Never scheduled"; r.difficulty = .medium
        ctx.insert(r)
        let used = Fixtures.quest(ctx, "Drawn once")
        let q = DailyQuest()
        q.dayKey = day; q.weekKey = "2026-W38"; q.slot = .easy; q.templateID = used.id; q.textSnapshot = "Drawn once"
        ctx.insert(q)
        try ctx.save()

        let rows = try table(ctx)
        let never = try row(rows, "Never drawn")
        #expect(never["kind"] == "library" && never["day_key"] == "" && never["library_origin"] == "user")
        #expect(never["library_difficulty"] == "E" && never["library_active"] == "TRUE")
        #expect(try row(rows, "Never scheduled")["library_difficulty"] == "M")
        #expect(rows.filter { $0["text"] == "Drawn once" }.count == 1)    // drawn: one record line, no library line
    }

    @Test func recordsComeOldestFirstAndTheUnusedLibraryLast() throws {
        let ctx = try Fixtures.context()
        Fixtures.quest(ctx, "Unused")
        for (d, text) in [("2026-09-18", "b"), ("2026-09-17", "a")] {
            let q = DailyQuest()
            q.dayKey = d; q.weekKey = "2026-W38"; q.slot = .easy; q.textSnapshot = text
            ctx.insert(q)
        }
        try ctx.save()
        #expect(try table(ctx).map { $0["text"] ?? "" } == ["a", "b", "Unused"])
    }

    @Test func theCSVFolderCarriesTheTableToo() throws {
        let ctx = try Fixtures.context()
        let files = try CSVExport.files(ctx, now: Fixtures.date("2026-09-18"), in: Fixtures.tokyo)
        #expect(files.map(\.name) == ["history-2026-09-18.csv", "ratings-2026-09-18.csv", "comments-2026-09-18.csv"])
        #expect(CSVExport.folderName(now: Fixtures.date("2026-09-18"), in: Fixtures.tokyo)
                == "LifeRPG-tables-2026-09-18")
    }
}
