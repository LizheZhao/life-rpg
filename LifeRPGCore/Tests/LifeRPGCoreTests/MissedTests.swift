import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// "Did not finish": a routine the settlement gave up on (day-4 auto-skip, Sunday's shortfall),
/// told apart from one you paid to cancel and from one you swapped. The occurrence row can't say
/// which — all three are `skipped` — so the ledger does: only the settlement writes a `skip` entry.
struct MissedTests {
    private let tz = Fixtures.tokyo
    private let fri = "2026-09-18", sat = "2026-09-19", sun = "2026-09-20"

    /// A skipped occurrence due on `due`, with the `skip` entry `Overdue` books the day after.
    @discardableResult
    private func settledSkip(_ ctx: ModelContext, _ text: String, due: String) throws -> RoutineOccurrence {
        let o = Fixtures.occurrence(ctx, text, due: due)
        o.skipped = true
        Economy.record(ctx, kind: .skip, points: 0, dayKey: try #require(DayKey.adding(1, to: due, in: tz)),
                       refID: o.id, note: text)
        return o
    }

    private func rows(_ ctx: ModelContext) throws -> (occurrences: [RoutineOccurrence], ledger: [LedgerEntry]) {
        (try ctx.fetch(FetchDescriptor<RoutineOccurrence>()), try ctx.fetch(FetchDescriptor<LedgerEntry>()))
    }

    // MARK: status

    @Test func theSettlementsSkipIsMissedAndACancelIsSkipped() throws {
        let ctx = try Fixtures.context()
        let gaveUp = try settledSkip(ctx, "gave up", due: fri)
        let cancelled = Fixtures.occurrence(ctx, "cancelled", due: fri)
        cancelled.skipped = true
        Economy.record(ctx, kind: .redeem, points: -200, dayKey: sat, refID: cancelled.id)
        let swapped = try settledSkip(ctx, "swapped", due: fri)
        swapped.replacedByID = UUID()
        try ctx.save()

        let record = try DayRecord.load(fri, in: ctx)
        let status = Dictionary(uniqueKeysWithValues: record.routines.map { ($0.occurrence.textSnapshot, $0.status) })
        #expect(status["gave up"] == .missed)
        #expect(status["cancelled"] == .skipped)
        #expect(status["swapped"] == .replaced)
        #expect(DayRecord.status(of: gaveUp) == .skipped)         // no ledger handed over: nothing to tell
    }

    /// The `skip` entry is dated the day after the due day, which the due day's own ledger never
    /// holds — `load` has to go and find it.
    @Test func loadFindsTheSkipEntryDatedTheNextDay() throws {
        let ctx = try Fixtures.context()
        try settledSkip(ctx, "gave up", due: fri)
        try ctx.save()
        let record = try DayRecord.load(fri, in: ctx)
        #expect(record.routines.map(\.status) == [.missed])
        #expect(record.otherLedger.isEmpty)                       // the entry belongs to Saturday
        #expect(try DayRecord.load(sat, in: ctx).otherLedger.map(\.kind) == ["skip"])
    }

    // MARK: the list

    @Test func missedListsOnlyWhatTheSettlementGaveUpOn() throws {
        let ctx = try Fixtures.context()
        try settledSkip(ctx, "gave up", due: fri)
        let cancelled = Fixtures.occurrence(ctx, "cancelled", due: fri)
        cancelled.skipped = true
        Economy.record(ctx, kind: .redeem, points: -200, dayKey: sat, refID: cancelled.id)
        let swapped = try settledSkip(ctx, "swapped", due: fri)
        swapped.replacedByID = UUID()
        Fixtures.occurrence(ctx, "open", due: fri)
        Fixtures.occurrence(ctx, "done", due: fri, completed: fri)
        try ctx.save()

        let (occurrences, ledger) = try rows(ctx)
        #expect(Schedule.missed(occurrences, ledger: ledger).map(\.textSnapshot) == ["gave up"])
    }

    @Test func missedIsNewestDueDayFirstAndCanBeCutToAMonth() throws {
        let ctx = try Fixtures.context()
        try settledSkip(ctx, "b sep", due: "2026-09-26")
        try settledSkip(ctx, "a sep", due: "2026-09-26")
        try settledSkip(ctx, "oct", due: "2026-10-02")
        try settledSkip(ctx, "aug", due: "2026-08-31")
        try ctx.save()

        let (occurrences, ledger) = try rows(ctx)
        #expect(Schedule.missed(occurrences, ledger: ledger).map(\.textSnapshot)
                == ["oct", "a sep", "b sep", "aug"])
        let september = try #require(MonthKey(year: 2026, month: 9))
        #expect(Schedule.missed(occurrences, ledger: ledger, in: september).map(\.textSnapshot)
                == ["a sep", "b sep"])
    }

    /// End to end through the real settlement: a day-4 auto-skip and Sunday's shortfall are both
    /// missed; a cancel bought before the ladder ends is not.
    @Test func theRealSettlementProducesMissedRows() throws {
        let ctx = try Fixtures.context()
        let trash = RoutineTask()
        trash.text = "Trash"; trash.spec = "SAT"; trash.basePoints = 20
        ctx.insert(trash)
        let fixed = RoutineOccurrence(routine: trash, dueDayKey: sat, weekKey: DayKey.weekKey(of: sat, in: tz)!)
        ctx.insert(fixed)
        let paid = RoutineOccurrence(routine: trash, dueDayKey: sat, weekKey: DayKey.weekKey(of: sat, in: tz)!)
        paid.textSnapshot = "Paid"
        ctx.insert(paid)
        Economy.record(ctx, kind: .adjust, points: 1000, dayKey: sat)
        try Redemption.cancel(paid, flexible: false, on: sat, in: ctx)
        for d in [sat, sun, "2026-09-21"] { try Overdue.settle(d, in: ctx, timeZone: tz) }
        try ctx.save()

        #expect(fixed.skipped && paid.skipped)
        let (occurrences, ledger) = try rows(ctx)
        #expect(Schedule.missed(occurrences, ledger: ledger).map(\.id) == [fixed.id])
        let status = Dictionary(uniqueKeysWithValues: try DayRecord.load(sat, in: ctx).routines.map { ($0.occurrence.id, $0.status) })
        #expect(status[fixed.id] == .missed && status[paid.id] == .skipped)
    }
}
