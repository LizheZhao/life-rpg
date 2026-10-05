import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// The old turn-based journal is the user's own writing, kept until a later release drops it, so
/// what matters is that a turn reads back as it was written, survives a backup and restore, and is
/// never touched by the debug tools that rewind a day.
struct JournalTurnTests {
    private let tz = Fixtures.tokyo
    private let friday = "2026-09-18"

    @discardableResult
    private func turn(_ ctx: ModelContext, _ dayKey: String, _ kind: JournalPromptKind, answer: String,
                      subject: JournalSubject? = nil, outcome: JournalOutcome = .answered) throws -> JournalTurn {
        try TurnRows.record(ctx, dayKey: dayKey, kind: kind, promptID: "open.keep",
                                  question: "What from today do you want to remember?", subject: subject,
                                  answer: answer, outcome: outcome, language: .en,
                                  askedAt: Fixtures.date(dayKey, hour: 21), answeredAt: Fixtures.date(dayKey, hour: 22))
    }

    @Test func turnsAreStoredInTheOrderTheyWereAskedAndPerDay() throws {
        let ctx = try Fixtures.context()
        try turn(ctx, friday, .opening, answer: "a")
        try turn(ctx, "2026-09-19", .opening, answer: "other day")
        try turn(ctx, friday, .good, answer: "b")
        try turn(ctx, friday, .closing, answer: "c")
        try ctx.save()

        let rows = try TurnRows.turns(on: friday, in: ctx)
        #expect(rows.map(\.answer) == ["a", "b", "c"])
        #expect(rows.map(\.index) == [0, 1, 2])
        #expect(rows.map(\.kind) == [.opening, .good, .closing])
        #expect(try TurnRows.turns(on: "2026-09-19", in: ctx).map(\.index) == [0])
    }

    @Test func aRowReadsBackWithEveryFieldItWasWrittenWith() throws {
        let ctx = try Fixtures.context()
        let subject = JournalSubject(kind: .routine, id: UUID(), text: "Take out the trash")
        let row = try TurnRows.record(ctx, dayKey: friday, kind: .skip, promptID: "skip.block",
                                            question: "Take out the trash didn't happen.", subject: subject,
                                            answer: "", outcome: .misfit, source: .model, language: .zhHans,
                                            askedAt: Fixtures.date(friday, hour: 21),
                                            answeredAt: Fixtures.date(friday, hour: 22))
        #expect(row.subjectKind == .routine)
        #expect(row.subjectID == subject.id)
        #expect(row.subjectText == "Take out the trash")
        #expect(row.outcomeRaw == "misfit")
        #expect(row.sourceRaw == "model")
        #expect(row.languageRaw == "zh-Hans")
        #expect(row.kindRaw == "skip")
    }

    // MARK: export and import

    private func sourceWithJournal() throws -> (ModelContext, JournalSubject) {
        let ctx = try Fixtures.context()
        let subject = JournalSubject(kind: .quest, id: UUID(), text: "Take a photo of the sky")
        try turn(ctx, friday, .opening, answer: "Quiet day, I liked the walk home.").writingSeconds = 754
        try turn(ctx, friday, .choice, answer: "The one with the crane in it.", subject: subject)
        try turn(ctx, friday, .closing, answer: "", outcome: .skipped)
        try ctx.save()
        return (ctx, subject)
    }

    @Test func theExportCarriesTheJournalAndItRoundTrips() throws {
        let (ctx, subject) = try sourceWithJournal()
        let snapshot = try JSONExport.snapshot(ctx, now: Fixtures.date(friday))
        let turns = try #require(snapshot.journal?.turns)
        #expect(turns.map(\.index) == [0, 1, 2])
        #expect(turns.map(\.writingSeconds) == [754, 0, 0])
        #expect(turns[1].kind == "choice")
        #expect(turns[1].subjectKind == "quest")
        #expect(turns[1].subjectID == subject.id)
        #expect(turns[1].subjectText == "Take a photo of the sky")
        #expect(turns[1].answer == "The one with the crane in it.")
        #expect(turns[2].outcome == "skipped")

        let decoded = try JSONExport.decode(try JSONExport.data(ctx, now: Fixtures.date(friday)))
        #expect(decoded.journal == snapshot.journal)
    }

    @Test func restoringPutsTheTurnsBackAndReplacesWhatWasThere() throws {
        let (source, subject) = try sourceWithJournal()
        let target = try Fixtures.context()
        try turn(target, "2026-09-01", .opening, answer: "written after the backup was taken")
        try target.save()

        let plan = try JSONImport.plan(try JSONExport.data(source), against: target)
        #expect(plan.summary.journalTurns == 3)
        try JSONImport.apply(plan, to: target)

        let rows = try target.fetch(FetchDescriptor<JournalTurn>()).sorted { $0.index < $1.index }
        #expect(rows.map(\.answer) == ["Quiet day, I liked the walk home.", "The one with the crane in it.", ""])
        #expect(rows[1].subjectID == subject.id)
        #expect(rows[1].subjectKind == .quest)
        #expect(rows.allSatisfy { $0.dayKey == friday })
        #expect(rows[0].answeredAt == Fixtures.date(friday, hour: 22))
        #expect(rows.map(\.writingSeconds) == [754, 0, 0])
        #expect(try StoreAudit.issues(target).isEmpty)
    }

    /// A backup of a store with an empty journal is still a statement about the journal.
    @Test func anEmptyJournalBlockReplacesTheTurnsOnTheStore() throws {
        let source = try Fixtures.context()
        let target = try Fixtures.context()
        try turn(target, friday, .opening, answer: "will be replaced")
        try target.save()

        let data = try JSONExport.data(source)
        #expect(String(decoding: data, as: UTF8.self).contains(#""journal":{"turns":[]}"#))
        try JSONImport.apply(try JSONImport.plan(data, against: target), to: target)
        #expect(try target.fetchCount(FetchDescriptor<JournalTurn>()) == 0)
    }

    /// A schema 6 file has turns but no `writingSeconds` on them; they restore reading 0.
    @Test func aVersion6ExportStillImportsWithNoWritingTime() throws {
        let (source, _) = try sourceWithJournal()
        var json = try #require(try JSONSerialization.jsonObject(with: try JSONExport.data(source)) as? [String: Any])
        json["schemaVersion"] = 6
        json.removeValue(forKey: "journalEntries")
        var journal = try #require(json["journal"] as? [String: Any])
        var turns = try #require(journal["turns"] as? [[String: Any]])
        for i in turns.indices { turns[i].removeValue(forKey: "writingSeconds") }
        journal["turns"] = turns
        json["journal"] = journal
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(!String(decoding: data, as: UTF8.self).contains("writingSeconds"))

        let target = try Fixtures.context()
        try JSONImport.apply(try JSONImport.plan(data, against: target), to: target)
        let rows = try target.fetch(FetchDescriptor<JournalTurn>()).sorted { $0.index < $1.index }
        #expect(rows.map(\.answer) == ["Quiet day, I liked the walk home.", "The one with the crane in it.", ""])
        #expect(rows.map(\.writingSeconds) == [0, 0, 0])
    }

    /// A schema 5 file has no journal block. It restores, and the turns written since stay.
    @Test func aVersion5ExportStillImportsAndLeavesTheJournalAlone() throws {
        let source = try Fixtures.context()
        var json = try #require(try JSONSerialization.jsonObject(with: try JSONExport.data(source)) as? [String: Any])
        json["schemaVersion"] = 5
        json.removeValue(forKey: "journal")
        json.removeValue(forKey: "journalEntries")
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(!String(decoding: data, as: UTF8.self).contains("journal"))

        let target = try Fixtures.context()
        try turn(target, friday, .opening, answer: "mine")
        try target.save()

        let plan = try JSONImport.plan(data, against: target)
        #expect(plan.summary.journalTurns == 0)
        try JSONImport.apply(plan, to: target)
        #expect(try target.fetch(FetchDescriptor<JournalTurn>()).map(\.answer) == ["mine"])
    }

    @Test func theAuditCountsTurnsNothingCanReadBack() throws {
        let ctx = try Fixtures.context()
        let row = try turn(ctx, friday, .opening, answer: "x")
        row.kindRaw = "essay"
        row.subjectKindRaw = "dragon"
        let bad = try turn(ctx, "2026-09-19", .closing, answer: "y")
        bad.dayKey = "yesterday"
        bad.languageRaw = "klingon"
        let issues = try StoreAudit.issues(ctx).map(\.description)
        #expect(issues == ["JournalTurn.dayKey = 'yesterday' ×1",
                           "JournalTurn.kindRaw = 'essay' ×1",
                           "JournalTurn.languageRaw = 'klingon' ×1",
                           "JournalTurn.subjectKindRaw = 'dragon' ×1"])
    }

    // MARK: the debug rewind

    @Test func resettingADayLeavesWhatTheUserWroteAboutIt() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 4)
        let now = Fixtures.date(friday)
        try DayService.ensureToday(ctx, now: now, in: tz, rng: &rng)
        let quest = try #require(try DayService.quests(on: friday, in: ctx).first)
        try turn(ctx, friday, .good, answer: "That one was the best part.",
                 subject: JournalSubject(kind: .quest, id: quest.id, text: quest.textSnapshot))
        try ctx.save()

        try DayReset.reset(ctx, dayKey: friday, now: now, in: tz, rng: &rng)

        let rows = try TurnRows.turns(on: friday, in: ctx)
        #expect(rows.map(\.answer) == ["That one was the best part."])
        #expect(rows.first?.subjectText == quest.textSnapshot)
    }
}

// MARK: a blank free-writing turn is not written and does not close the day

struct JournalBlankFreeWritingTests {
    typealias F = JournalFixtures

    @Test func aBlankFreeWritingTurnDoesNotCloseTheDay() {
        #expect(!JournalMigration.isClosed([F.freeWriting("")]))
        #expect(!JournalMigration.isClosed([F.turn(.opening, "ok then", index: 0), F.freeWriting("  \n", index: 1)]))
    }

    @Test func aWrittenFreeWritingTurnStillClosesIt() {
        #expect(JournalMigration.isClosed([F.freeWriting("hello")]))
    }

    @Test func aSkippedQuestionedClosingTurnStillCloses() {
        #expect(JournalMigration.isClosed([F.turn(.closing, "", index: 0, outcome: .skipped)]))
        let blankButQuestioned = F.turn(.closing, "", index: 0)
        #expect(JournalMigration.isClosed([blankButQuestioned]))
    }
}
