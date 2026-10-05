import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

struct JournalEntriesTests {
    private typealias F = EntryFixtures
    private let friday = "2026-09-18"

    private func at(_ dayKey: String, hour: Int) -> Date { Fixtures.date(dayKey, hour: hour) }

    // MARK: the model

    @Test func anEntryReadsItsBlocksWordsAndStatusFromTheRow() {
        let row = JournalEntry()
        #expect(row.blocksJSON == "[]")
        #expect(row.blocks == [] && row.wordCount == 0 && !row.isDone)
        row.blocks = [F.text(1, "one two"), F.prompt(2, "Why?", answer: "three")]
        #expect(row.blocks == [F.text(1, "one two"), F.prompt(2, "Why?", answer: "three")])
        #expect(row.wordCount == 3)
        row.doneAt = Date()
        #expect(row.isDone)
    }

    // MARK: save

    @Test func theFirstSaveCreatesTheRowWithBothTimesAndNoDoneTime() throws {
        let ctx = try Fixtures.context()
        let row = try #require(try JournalEntries.save([F.text(1, "hello")], on: friday, in: ctx, now: at(friday, hour: 21)))
        #expect(row.dayKey == friday)
        #expect(row.blocks == [F.text(1, "hello")])
        #expect(row.createdAt == at(friday, hour: 21) && row.updatedAt == at(friday, hour: 21))
        #expect(row.doneAt == nil)
        #expect(try ctx.fetchCount(FetchDescriptor<JournalEntry>()) == 1)
    }

    @Test func aLaterSaveRewritesTheSameRowKeepingCreatedAtAndDoneAt() throws {
        let ctx = try Fixtures.context()
        try JournalEntries.save([F.text(1, "hello")], on: friday, in: ctx, now: at(friday, hour: 21))
        try JournalEntries.markDone(on: friday, in: ctx, now: at(friday, hour: 22))
        let row = try #require(try JournalEntries.save([F.text(1, "hello again")], on: friday, in: ctx, now: at(friday, hour: 23)))
        #expect(try ctx.fetchCount(FetchDescriptor<JournalEntry>()) == 1)
        #expect(row.blocks == [F.text(1, "hello again")])
        #expect(row.createdAt == at(friday, hour: 21))
        #expect(row.updatedAt == at(friday, hour: 23))
        #expect(row.doneAt == at(friday, hour: 22))
    }

    @Test func savingWhatIsAlreadyStoredChangesNothingNotEvenUpdatedAt() throws {
        let ctx = try Fixtures.context()
        try JournalEntries.save([F.text(1, "hello")], on: friday, in: ctx, now: at(friday, hour: 21))
        let row = try #require(try JournalEntries.save([F.text(1, "hello")], on: friday, in: ctx, now: at(friday, hour: 23)))
        #expect(row.updatedAt == at(friday, hour: 21))
    }

    @Test func blocksAreNormalizedBeforeTheyAreStored() throws {
        let ctx = try Fixtures.context()
        let row = try #require(try JournalEntries.save(
            [F.text(1, "a"), F.text(2, ""), F.text(3, "b"), F.prompt(4, "Skipped?"), F.prompt(5, "Asked?", answer: "yes")],
            on: friday, in: ctx, now: at(friday, hour: 21)))
        #expect(row.blocks == [F.text(1, "a\nb"), F.prompt(4, "Skipped?"), F.prompt(5, "Asked?", answer: "yes")])
    }

    @Test func aDocumentOfOnlyUnansweredPromptsIsNotStored() throws {
        let ctx = try Fixtures.context()
        let row = try JournalEntries.save([F.prompt(1, "Q1"), F.text(2, ""), F.prompt(3, "Q2")], on: friday, in: ctx,
                                          now: at(friday, hour: 21))
        #expect(row == nil)
        #expect(try ctx.fetchCount(FetchDescriptor<JournalEntry>()) == 0)
    }

    @Test func savingAnEmptyDocumentDeletesTheDaysRowAndLeavesOtherDays() throws {
        let ctx = try Fixtures.context()
        try JournalEntries.save([F.text(1, "tonight")], on: friday, in: ctx, now: at(friday, hour: 21))
        try JournalEntries.save([F.text(2, "yesterday")], on: "2026-09-17", in: ctx, now: at("2026-09-17", hour: 21))
        let cleared = try JournalEntries.save([F.text(1, "")], on: friday, in: ctx, now: at(friday, hour: 22))
        #expect(cleared == nil)
        #expect(try JournalEntries.entry(on: friday, in: ctx) == nil)
        #expect(try JournalEntries.all(in: ctx).map(\.dayKey) == ["2026-09-17"])
    }

    @Test func writingAfterClearingStartsAFreshEntry() throws {
        let ctx = try Fixtures.context()
        try JournalEntries.save([F.text(1, "first")], on: friday, in: ctx, now: at(friday, hour: 20))
        try JournalEntries.markDone(on: friday, in: ctx, now: at(friday, hour: 20))
        try JournalEntries.save([], on: friday, in: ctx, now: at(friday, hour: 21))
        let row = try #require(try JournalEntries.save([F.text(2, "second")], on: friday, in: ctx, now: at(friday, hour: 22)))
        #expect(row.createdAt == at(friday, hour: 22) && row.doneAt == nil)
    }

    @Test func savingNothingWhereThereIsNoRowIsANoOp() throws {
        let ctx = try Fixtures.context()
        #expect(try JournalEntries.save([], on: friday, in: ctx, now: at(friday, hour: 21)) == nil)
        #expect(try ctx.fetchCount(FetchDescriptor<JournalEntry>()) == 0)
    }

    // MARK: done

    @Test func doneIsSetTheFirstTimeAndNeverCleared() throws {
        let ctx = try Fixtures.context()
        try JournalEntries.save([F.text(1, "hello")], on: friday, in: ctx, now: at(friday, hour: 21))
        let first = try #require(try JournalEntries.markDone(on: friday, in: ctx, now: at(friday, hour: 22)))
        #expect(first.doneAt == at(friday, hour: 22))
        let second = try #require(try JournalEntries.markDone(on: friday, in: ctx, now: at(friday, hour: 23)))
        #expect(second.doneAt == at(friday, hour: 22))
        // Reopening and editing locks nothing and does not turn it back into a draft either.
        let edited = try #require(try JournalEntries.save([F.text(1, "hello, more")], on: friday, in: ctx, now: at(friday, hour: 23)))
        #expect(edited.isDone && edited.doneAt == at(friday, hour: 22))
        #expect(edited.blocks == [F.text(1, "hello, more")])
    }

    @Test func doneOnADayWithNoRowDoesNothing() throws {
        let ctx = try Fixtures.context()
        #expect(try JournalEntries.markDone(on: friday, in: ctx, now: at(friday, hour: 22)) == nil)
        #expect(try ctx.fetchCount(FetchDescriptor<JournalEntry>()) == 0)
    }

    // MARK: lookup

    @Test func entryAndAllReadTheStore() throws {
        let ctx = try Fixtures.context()
        try JournalEntries.save([F.text(1, "b")], on: "2026-09-18", in: ctx, now: at("2026-09-18", hour: 21))
        try JournalEntries.save([F.text(2, "a")], on: "2026-09-16", in: ctx, now: at("2026-09-16", hour: 21))
        #expect(try JournalEntries.entry(on: "2026-09-16", in: ctx)?.blocks == [F.text(2, "a")])
        #expect(try JournalEntries.entry(on: "2026-09-17", in: ctx) == nil)
        #expect(try JournalEntries.all(in: ctx).map(\.dayKey) == ["2026-09-16", "2026-09-18"])
    }

    // MARK: the day an entry is written to

    @Test func theEntryDayIsTheAppDayWhichEndsAtFive() {
        func key(_ day: String, _ hour: Int, _ minute: Int = 0) -> String {
            var c = DateComponents()
            let p = day.split(separator: "-").map { Int($0)! }
            c.year = p[0]; c.month = p[1]; c.day = p[2]; c.hour = hour; c.minute = minute
            return JournalEntries.entryDayKey(now: LifeCalendar.gregorian(Fixtures.tokyo).date(from: c)!, timeZone: Fixtures.tokyo)
        }
        #expect(key("2026-10-05", 4, 59) == "2026-10-04")
        #expect(key("2026-10-05", 0, 0) == "2026-10-04")
        #expect(key("2026-10-05", 5, 0) == "2026-10-05")
        #expect(key("2026-10-04", 23, 59) == "2026-10-04")
    }

    // MARK: the audit

    @Test func theAuditReadsEntriesBackAndFlagsABadDayOrUnreadableBlocks() throws {
        let ctx = try Fixtures.context()
        try JournalEntries.save([F.text(1, "fine")], on: friday, in: ctx, now: at(friday, hour: 21))
        #expect(try StoreAudit.issues(ctx).isEmpty)

        let bad = JournalEntry()
        bad.dayKey = "last night"
        bad.blocksJSON = "{not json"
        ctx.insert(bad)
        let wrongShape = JournalEntry()
        wrongShape.dayKey = "2026-09-19"
        wrongShape.blocksJSON = #"[{"type":"photo"}]"#
        ctx.insert(wrongShape)
        #expect(try StoreAudit.issues(ctx).map(\.description) == [
            "JournalEntry.blocksJSON = 'not an array of readable blocks' ×2",
            "JournalEntry.dayKey = 'last night' ×1",
        ])
    }
}
