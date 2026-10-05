import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

struct JournalMigrationTests {
    private typealias F = EntryFixtures
    private let friday = "2026-09-18"

    @discardableResult
    private func turn(_ ctx: ModelContext, on dayKey: String = "2026-09-18", _ kind: JournalPromptKind,
                      question: String = "", answer: String = "", outcome: JournalOutcome = .answered,
                      source: JournalSource = .template, asked: Int = 21, answered: Int = 22) throws -> JournalTurn {
        try TurnRows.record(ctx, dayKey: dayKey, kind: kind, promptID: question.isEmpty ? "" : "pool.\(kind.rawValue)",
                                  question: question, answer: answer, outcome: outcome, source: source, language: .en,
                                  askedAt: Fixtures.date(dayKey, hour: asked), answeredAt: Fixtures.date(dayKey, hour: answered))
    }

    /// The blocks without their random ids.
    private func shape(_ blocks: [JournalBlock]) -> [String] {
        blocks.map {
            switch $0 {
            case .text(_, let text): "T|\(text)"
            case .prompt(_, let q, let a, let source, let key): "P|\(q)|\(a)|\(source.rawValue)|\(key?.rawValue ?? "-")"
            }
        }
    }

    @Test func threeAnsweredPromptsAndFreeWritingBecomeFourBlocksInOrder() throws {
        let ctx = try Fixtures.context()
        try turn(ctx, .opening, question: "What stayed with you?", answer: "The walk.", source: .template)
        try turn(ctx, .good, question: "What was good about the gym?", answer: "Felt strong.", source: .model)
        try turn(ctx, .heavy, question: "What was hard?", answer: "Waking up.", source: .template)
        try TurnRows.freeWriting(ctx, "Then I slept.", on: friday, at: Fixtures.date(friday, hour: 23))
        try ctx.save()

        #expect(try JournalMigration.migrateTurns(in: ctx) == 1)
        let entry = try #require(try JournalEntries.entry(on: friday, in: ctx))
        #expect(shape(entry.blocks) == [
            "P|What stayed with you?|The walk.|fixed|-",
            "P|What was good about the gym?|Felt strong.|llm|-",
            "P|What was hard?|Waking up.|fixed|-",
            "T|Then I slept.",
        ])
        #expect(entry.wordCount == 2 + 2 + 2 + 3)
    }

    @Test func aSkippedOrMisfitQuestionStaysAsAPromptWithNoAnswer() throws {
        let ctx = try Fixtures.context()
        try turn(ctx, .opening, question: "Opening?", answer: "yes")
        try turn(ctx, .skip, question: "About the trash?", outcome: .skipped)
        try turn(ctx, .good, question: "About the run?", outcome: .misfit)
        try ctx.save()

        try JournalMigration.migrateTurns(in: ctx)
        let entry = try #require(try JournalEntries.entry(on: friday, in: ctx))
        #expect(shape(entry.blocks) == ["P|Opening?|yes|fixed|-", "P|About the trash?||fixed|-", "P|About the run?||fixed|-"])
    }

    @Test func theSafetyLineIsDropped() throws {
        let ctx = try Fixtures.context()
        try turn(ctx, .opening, question: "Opening?", answer: "heavy day")
        try turn(ctx, .safety, question: JournalSafety.line(language: .en))
        try ctx.save()

        try JournalMigration.migrateTurns(in: ctx)
        let entry = try #require(try JournalEntries.entry(on: friday, in: ctx))
        #expect(shape(entry.blocks) == ["P|Opening?|heavy day|fixed|-"])
    }

    @Test func aBlankFreeWritingTurnIsSkipped() throws {
        let ctx = try Fixtures.context()
        try turn(ctx, .opening, question: "Opening?", answer: "x")
        try TurnRows.freeWriting(ctx, "", on: friday, at: Fixtures.date(friday, hour: 23), writingSeconds: 5)
        try ctx.save()

        try JournalMigration.migrateTurns(in: ctx)
        #expect(shape(try #require(try JournalEntries.entry(on: friday, in: ctx)).blocks) == ["P|Opening?|x|fixed|-"])
    }

    @Test func aClosedDayIsDoneAtItsLastAnswerAndOpenDayIsADraft() throws {
        let ctx = try Fixtures.context()
        try turn(ctx, on: "2026-09-17", .opening, question: "Q1?", answer: "a", asked: 20, answered: 21)
        try turn(ctx, on: "2026-09-17", .closing, question: "Anything else?", answer: "b", asked: 21, answered: 23)
        try turn(ctx, on: friday, .opening, question: "Q2?", answer: "c", asked: 19, answered: 20)
        try turn(ctx, on: friday, .good, question: "Q3?", answer: "d", asked: 20, answered: 21)
        try ctx.save()

        #expect(try JournalMigration.migrateTurns(in: ctx) == 2)
        let closed = try #require(try JournalEntries.entry(on: "2026-09-17", in: ctx))
        #expect(closed.createdAt == Fixtures.date("2026-09-17", hour: 20))
        #expect(closed.updatedAt == Fixtures.date("2026-09-17", hour: 23))
        #expect(closed.doneAt == Fixtures.date("2026-09-17", hour: 23))
        let open = try #require(try JournalEntries.entry(on: friday, in: ctx))
        #expect(open.createdAt == Fixtures.date(friday, hour: 19))
        #expect(open.updatedAt == Fixtures.date(friday, hour: 21))
        #expect(open.doneAt == nil)
    }

    @Test func freeWritingAloneClosesTheDay() throws {
        let ctx = try Fixtures.context()
        try TurnRows.freeWriting(ctx, "just this", on: friday, at: Fixtures.date(friday, hour: 22))
        try ctx.save()
        try JournalMigration.migrateTurns(in: ctx)
        let entry = try #require(try JournalEntries.entry(on: friday, in: ctx))
        #expect(shape(entry.blocks) == ["T|just this"])
        #expect(entry.doneAt == Fixtures.date(friday, hour: 22))
    }

    @Test func aDayWithNothingWrittenGetsNoEntry() throws {
        let ctx = try Fixtures.context()
        try turn(ctx, .skip, question: "Q?", outcome: .skipped)
        try turn(ctx, .safety, question: "line")
        try turn(ctx, on: "2026-09-19", .opening, question: "Q?", answer: "x")
        try ctx.save()

        #expect(try JournalMigration.migrateTurns(in: ctx) == 1)
        #expect(try JournalEntries.all(in: ctx).map(\.dayKey) == ["2026-09-19"])
    }

    @Test func aDayThatAlreadyHasAnEntryIsLeftAlone() throws {
        let ctx = try Fixtures.context()
        try turn(ctx, .opening, question: "Q?", answer: "old turn")
        try JournalEntries.save([F.text(1, "new entry")], on: friday, in: ctx, now: Fixtures.date(friday, hour: 23))
        try ctx.save()

        #expect(try JournalMigration.migrateTurns(in: ctx) == 0)
        #expect(try JournalEntries.entry(on: friday, in: ctx)?.blocks == [F.text(1, "new entry")])
    }

    @Test func runningItTwiceCreatesNothingTheSecondTimeAndNoTurnIsTouched() throws {
        let ctx = try Fixtures.context()
        try turn(ctx, .opening, question: "Q?", answer: "a")
        try turn(ctx, .closing, question: "More?", answer: "b")
        try TurnRows.freeWriting(ctx, "c", on: friday, at: Fixtures.date(friday, hour: 23))
        try ctx.save()
        let before = try TurnRows.turns(on: friday, in: ctx).map { [$0.questionText, $0.answer, $0.kindRaw, "\($0.index)"] }

        #expect(try JournalMigration.migrateTurns(in: ctx) == 1)
        try ctx.save()
        #expect(try JournalMigration.migrateTurns(in: ctx) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<JournalEntry>()) == 1)
        #expect(try TurnRows.turns(on: friday, in: ctx).map { [$0.questionText, $0.answer, $0.kindRaw, "\($0.index)"] } == before)
        #expect(try ctx.fetchCount(FetchDescriptor<JournalTurn>()) == 3)
    }

    @Test func aStoreWithNoTurnsMigratesNothing() throws {
        #expect(try JournalMigration.migrateTurns(in: try Fixtures.context()) == 0)
    }
}
