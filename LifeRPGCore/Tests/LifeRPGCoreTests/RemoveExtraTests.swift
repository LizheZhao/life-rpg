import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// An extra added with + replaces nothing, never gates the day and is never charged, so taking it
/// off again is free: there is nothing to cancel (a cancel costs coins because it ends a charge).
/// Only one that is still open can go; a done one has been paid and is history.
struct RemoveExtraTests {
    private let tz = Fixtures.tokyo
    private let fri = "2026-09-18"

    private func extra(_ ctx: ModelContext, _ text: String = "Try the thing") throws -> RoutineOccurrence {
        try AdHoc.add(.custom(text: text, difficulty: .easy), on: fri, in: ctx, timeZone: tz)
    }

    private func all(_ ctx: ModelContext) throws -> [RoutineOccurrence] {
        try ctx.fetch(FetchDescriptor<RoutineOccurrence>())
    }

    @Test func anOpenExtraCanBeTakenOffTheDayForNothing() throws {
        let ctx = try Fixtures.context()
        let o = try extra(ctx)
        let kept = try extra(ctx, "Another")
        let balance = try Economy.balance(ctx)

        #expect(AdHoc.isExtra(o, among: try all(ctx)))
        try AdHoc.removeExtra(o, in: ctx)
        #expect(try all(ctx).map(\.textSnapshot) == ["Another"])
        #expect(kept.completedDayKey == nil)
        #expect(try Economy.balance(ctx) == balance)                 // free: no ledger entry either way
        #expect(try ctx.fetch(FetchDescriptor<LedgerEntry>()).isEmpty)
    }

    @Test func anExtraPickedFromTheLibraryGoesToo() throws {
        let ctx = try Fixtures.context()
        let r = RoutineTask()
        r.text = "Piano"; r.spec = "MON"; r.basePoints = 20
        ctx.insert(r)
        let o = try AdHoc.add(.routine(r), on: fri, in: ctx, timeZone: tz)
        try AdHoc.removeExtra(o, in: ctx)
        #expect(try all(ctx).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<RoutineTask>()).count == 1)   // the library row stays
    }

    @Test func aDoneExtraIsHistoryAndStays() throws {
        let ctx = try Fixtures.context()
        let o = try extra(ctx)
        try Completion.completeRoutine(o, on: fri, tier: .normal, in: ctx, timeZone: tz)
        #expect(throws: AdHoc.Failure.notRemovable) { try AdHoc.removeExtra(o, in: ctx) }
        #expect(try all(ctx).count == 1)
    }

    @Test func nothingThatAsksSomethingOfYouCanBeRemovedThisWay() throws {
        let ctx = try Fixtures.context()
        // A scheduled routine.
        let r = RoutineTask()
        r.text = "Trash"; r.spec = "FRI"; r.basePoints = 5
        ctx.insert(r)
        let scheduled = RoutineOccurrence(routine: r, dueDayKey: fri, weekKey: "2026-W38")
        ctx.insert(scheduled)
        // A slot swapped for a routine: it gates the day and loses points when left undone.
        let slot = DailyQuest()
        slot.dayKey = fri; slot.weekKey = "2026-W38"; slot.slot = .medium; slot.textSnapshot = "slot"
        ctx.insert(slot)
        let swapped = try AdHoc.replace(slot, with: .custom(text: "Swap", difficulty: .medium), in: ctx, timeZone: tz)
        try ctx.save()

        #expect(throws: AdHoc.Failure.notRemovable) { try AdHoc.removeExtra(scheduled, in: ctx) }
        #expect(throws: AdHoc.Failure.notRemovable) { try AdHoc.removeExtra(swapped, in: ctx) }
        #expect(!AdHoc.isExtra(scheduled, among: try all(ctx)))
        #expect(!AdHoc.isExtra(swapped, among: try all(ctx)))
        #expect(try all(ctx).count == 2 + 0)
    }
}
