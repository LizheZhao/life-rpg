import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// The day documents in a backup: written at schema 8, restored from it, and rebuilt from the turns
/// of an older file.
struct JournalEntryBackupTests {
    private typealias F = EntryFixtures
    private let friday = "2026-09-18"
    private let thursday = "2026-09-17"

    private func at(_ dayKey: String, hour: Int) -> Date { Fixtures.date(dayKey, hour: hour) }

    private func source() throws -> ModelContext {
        let ctx = try Fixtures.context()
        try JournalEntries.save([F.text(1, "Rain all day."), F.prompt(2, "What are you grateful for today?", answer: "Tea.",
                                                                     source: .fixed, key: .gratefulFor),
                                 F.prompt(3, "What was hard?", answer: "", source: .llm)],
                                on: friday, in: ctx, now: at(friday, hour: 21))
        try JournalEntries.markDone(on: friday, in: ctx, now: at(friday, hour: 22))
        try JournalEntries.save([F.text(4, "Short one.")], on: thursday, in: ctx, now: at(thursday, hour: 20))
        try ctx.save()
        return ctx
    }

    /// A schema 7 file: the export of `ctx` with the version stepped back and no `journalEntries`.
    private func version7(of ctx: ModelContext) throws -> Data {
        var json = try #require(try JSONSerialization.jsonObject(with: try JSONExport.data(ctx)) as? [String: Any])
        json["schemaVersion"] = 7
        json.removeValue(forKey: "journalEntries")
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(!String(decoding: data, as: UTF8.self).contains("journalEntries"))
        return data
    }

    private func restore(_ data: Data, into target: ModelContext) throws -> JSONImport.Plan {
        let plan = try JSONImport.plan(data, against: target)
        try JSONImport.apply(plan, to: target)
        return plan
    }

    @discardableResult
    private func turn(_ ctx: ModelContext, on dayKey: String, _ kind: JournalPromptKind, question: String = "",
                      answer: String, hour: Int = 22) throws -> JournalTurn {
        try TurnRows.record(ctx, dayKey: dayKey, kind: kind, promptID: question.isEmpty ? "" : "pool.x",
                                  question: question, answer: answer, language: .en,
                                  askedAt: at(dayKey, hour: hour - 1), answeredAt: at(dayKey, hour: hour))
    }

    // MARK: export

    @Test func theExportCarriesTheEntriesWithTheirBlocksAndTimes() throws {
        let snapshot = try JSONExport.snapshot(try source())
        #expect(snapshot.schemaVersion == 12)
        let rows = try #require(snapshot.journalEntries)
        #expect(rows.map(\.dayKey) == [thursday, friday])
        #expect(rows[1].blocks == [F.text(1, "Rain all day."),
                                   F.prompt(2, "What are you grateful for today?", answer: "Tea.", source: .fixed, key: .gratefulFor),
                                   F.prompt(3, "What was hard?", answer: "", source: .llm)])
        #expect(rows[1].createdAt == at(friday, hour: 21) && rows[1].updatedAt == at(friday, hour: 21))
        #expect(rows[1].doneAt == at(friday, hour: 22))
        #expect(rows[0].doneAt == nil)
    }

    @Test func theBlocksAreWrittenAsTheDocumentedObjects() throws {
        let data = try JSONExport.data(try source())
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try #require(json["journalEntries"] as? [[String: Any]])
        let blocks = try #require(rows[0]["blocks"] as? [[String: Any]])
        #expect(blocks.count == 1)
        #expect(blocks[0]["type"] as? String == "text")
        #expect(blocks[0]["text"] as? String == "Short one.")
        #expect(blocks[0]["id"] as? String == F.id(4).uuidString)
        #expect(rows[0]["doneAt"] == nil)
    }

    @Test func aStoreWithNoEntriesStillWritesTheEmptyArray() throws {
        let data = try JSONExport.data(try Fixtures.context())
        #expect(String(decoding: data, as: UTF8.self).contains(#""journalEntries":[]"#))
    }

    // MARK: restoring a schema 8 file

    @Test func anEditedEntrySurvivesExportThenImport() throws {
        let ctx = try source()
        try JournalEntries.save([F.text(1, "Rain all day, then sun."),
                                 F.prompt(2, "What are you grateful for today?", answer: "Tea and toast.", source: .fixed, key: .gratefulFor)],
                                on: friday, in: ctx, now: at(friday, hour: 23))
        try ctx.save()

        let target = try Fixtures.context()
        let plan = try restore(try JSONExport.data(ctx), into: target)
        #expect(plan.summary.journalEntries == 2)
        let row = try #require(try JournalEntries.entry(on: friday, in: target))
        #expect(row.blocks == [F.text(1, "Rain all day, then sun."),
                               F.prompt(2, "What are you grateful for today?", answer: "Tea and toast.", source: .fixed, key: .gratefulFor)])
        #expect(row.createdAt == at(friday, hour: 21))
        #expect(row.updatedAt == at(friday, hour: 23))
        #expect(row.doneAt == at(friday, hour: 22))
        #expect(try JournalEntries.entry(on: thursday, in: target)?.doneAt == nil)
        #expect(try StoreAudit.issues(target).isEmpty)
    }

    @Test func aRestoreReplacesTheEntriesOnTheStore() throws {
        let target = try Fixtures.context()
        try JournalEntries.save([F.text(9, "written after the backup")], on: "2026-09-25", in: target, now: at("2026-09-25", hour: 21))
        try JournalEntries.save([F.text(8, "this day gets replaced")], on: friday, in: target, now: at(friday, hour: 21))
        try target.save()

        try restore(try JSONExport.data(try source()), into: target)
        #expect(try JournalEntries.all(in: target).map(\.dayKey) == [thursday, friday])
        #expect(try JournalEntries.entry(on: friday, in: target)?.wordCount == 4)
    }

    @Test func anEntryTheUserClearedStaysGoneThroughABackup() throws {
        let ctx = try Fixtures.context()
        try turn(ctx, on: friday, .opening, question: "Q?", answer: "from the old build")
        try JournalMigration.migrateTurns(in: ctx)
        try JournalEntries.save([], on: friday, in: ctx, now: at(friday, hour: 23))
        try ctx.save()
        #expect(try ctx.fetchCount(FetchDescriptor<JournalEntry>()) == 0)

        let target = try Fixtures.context()
        try restore(try JSONExport.data(ctx), into: target)
        #expect(try target.fetchCount(FetchDescriptor<JournalTurn>()) == 1)
        #expect(try target.fetchCount(FetchDescriptor<JournalEntry>()) == 0)
    }

    @Test func aFileWithAnUnreadableBlockIsRefusedWholeAndChangesNothing() throws {
        var json = try #require(try JSONSerialization.jsonObject(with: try JSONExport.data(try source())) as? [String: Any])
        var rows = try #require(json["journalEntries"] as? [[String: Any]])
        rows[0]["blocks"] = [["type": "photo"]]
        json["journalEntries"] = rows
        let data = try JSONSerialization.data(withJSONObject: json)

        let target = try Fixtures.context()
        try JournalEntries.save([F.text(1, "mine")], on: friday, in: target, now: at(friday, hour: 21))
        try target.save()
        #expect(throws: JSONImport.Failure.unreadable) { try JSONImport.plan(data, against: target) }
        #expect(try JournalEntries.entry(on: friday, in: target)?.blocks == [F.text(1, "mine")])
    }

    @Test func anEntryWithABadDayRollsTheWholeImportBack() throws {
        var json = try #require(try JSONSerialization.jsonObject(with: try JSONExport.data(try source())) as? [String: Any])
        var rows = try #require(json["journalEntries"] as? [[String: Any]])
        rows[0]["dayKey"] = "last night"
        json["journalEntries"] = rows
        let data = try JSONSerialization.data(withJSONObject: json)

        let target = try Fixtures.context()
        try JournalEntries.save([F.text(1, "mine")], on: friday, in: target, now: at(friday, hour: 21))
        try target.save()
        let plan = try JSONImport.plan(data, against: target)
        #expect(throws: JSONImport.Failure.audit([.init(model: "JournalEntry", field: "dayKey", value: "last night", count: 1)])) {
            try JSONImport.apply(plan, to: target)
        }
        #expect(try JournalEntries.all(in: target).map(\.dayKey) == [friday])
    }

    // MARK: restoring an older file

    @Test func aVersion7FileWithOnlyTurnsComesBackAsEntries() throws {
        let ctx = try Fixtures.context()
        try turn(ctx, on: friday, .opening, question: "What stayed with you?", answer: "The walk.", hour: 21)
        try TurnRows.freeWriting(ctx, "Then I slept.", on: friday, at: at(friday, hour: 23))
        try turn(ctx, on: thursday, .opening, question: "Opening?", answer: "ok", hour: 20)
        try ctx.save()

        let target = try Fixtures.context()
        let plan = try restore(try version7(of: ctx), into: target)
        #expect(plan.summary.journalTurns == 3 && plan.summary.journalEntries == 0)
        #expect(try JournalEntries.all(in: target).map(\.dayKey) == [thursday, friday])
        let row = try #require(try JournalEntries.entry(on: friday, in: target))
        #expect(row.blocks.map { $0.writtenText } == ["The walk.", "Then I slept."])
        #expect(row.document.questions == ["What stayed with you?"])
        #expect(row.createdAt == at(friday, hour: 20))
        #expect(row.updatedAt == at(friday, hour: 23))
        #expect(row.doneAt == at(friday, hour: 23))
        #expect(try JournalEntries.entry(on: thursday, in: target)?.doneAt == nil)
        #expect(try target.fetchCount(FetchDescriptor<JournalTurn>()) == 3)
        #expect(try StoreAudit.issues(target).isEmpty)
    }

    @Test func aFileBeforeSchema8LeavesTheLocalEntriesAlone() throws {
        let ctx = try Fixtures.context()
        try turn(ctx, on: thursday, .opening, question: "Opening?", answer: "from the backup")
        try ctx.save()

        let target = try Fixtures.context()
        try JournalEntries.save([F.text(1, "written since")], on: friday, in: target, now: at(friday, hour: 21))
        try target.save()
        try restore(try version7(of: ctx), into: target)
        #expect(try JournalEntries.all(in: target).map(\.dayKey) == [thursday, friday])
        #expect(try JournalEntries.entry(on: friday, in: target)?.blocks == [F.text(1, "written since")])
    }

    @Test func aTurnOnlyBackupDoesNotDuplicateAnEntryTheStoreAlreadyHas() throws {
        let ctx = try Fixtures.context()
        try turn(ctx, on: friday, .opening, question: "Opening?", answer: "from the backup")
        try ctx.save()

        let target = try Fixtures.context()
        try JournalEntries.save([F.text(1, "already here")], on: friday, in: target, now: at(friday, hour: 21))
        try target.save()
        try restore(try version7(of: ctx), into: target)
        #expect(try JournalEntries.all(in: target).count == 1)
        #expect(try JournalEntries.entry(on: friday, in: target)?.blocks == [F.text(1, "already here")])
    }
}
