import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// The day detail sheet's contents (PLAN §9).
struct DayRecordTests {
    private let day = "2026-09-17"

    private func quest(_ ctx: ModelContext, _ text: String, _ slot: Difficulty, dayKey: String? = nil,
                       hidden: Bool = false, points: Int? = nil) -> DailyQuest {
        let q = DailyQuest()
        q.dayKey = dayKey ?? day
        q.slot = slot
        q.isHiddenSlot = hidden
        q.textSnapshot = text
        q.points = points
        q.completedAt = points.map { _ in Fixtures.date(dayKey ?? day) }
        ctx.insert(q)
        return q
    }

    @Test func questsAreOrderedEpicSlotsHidden() throws {
        let ctx = try Fixtures.context()
        _ = quest(ctx, "hidden", .easy, hidden: true)
        _ = quest(ctx, "hard", .hard)
        _ = quest(ctx, "epic", .epic)
        _ = quest(ctx, "easy", .easy)
        _ = quest(ctx, "other day", .easy, dayKey: "2026-09-16")
        try ctx.save()
        let record = try DayRecord.load(day, in: ctx)
        #expect(record.quests.map(\.quest.textSnapshot) == ["epic", "easy", "hard", "hidden"])
    }

    @Test func routineStatuses() throws {
        let ctx = try Fixtures.context()
        Fixtures.occurrence(ctx, "a on time", due: day, completed: day)
        Fixtures.occurrence(ctx, "b late", due: day, completed: "2026-09-18")
        Fixtures.occurrence(ctx, "c ahead", due: day, completed: "2026-09-15")
        Fixtures.occurrence(ctx, "d skipped", due: day).skipped = true
        Fixtures.occurrence(ctx, "e open", due: day)
        try ctx.save()
        let record = try DayRecord.load(day, in: ctx)
        #expect(record.routines.map(\.status) == [
            .done, .late(on: "2026-09-18"), .doneAhead(on: "2026-09-15"), .skipped, .notDone,
        ])
        #expect(record.completedForOtherDays.isEmpty)
    }

    /// A make-up and a do-ahead appear on the day the work happened too, not only on the due day.
    @Test func completionsForOtherDaysShowOnTheDayTheyHappened() throws {
        let ctx = try Fixtures.context()
        Fixtures.occurrence(ctx, "made up", due: "2026-09-16", completed: day)
        Fixtures.occurrence(ctx, "ahead", due: "2026-09-19", completed: day)
        Fixtures.occurrence(ctx, "unrelated", due: "2026-09-16", completed: "2026-09-16")
        try ctx.save()
        let record = try DayRecord.load(day, in: ctx)
        #expect(record.routines.isEmpty)
        #expect(record.completedForOtherDays.map(\.occurrence.textSnapshot) == ["made up", "ahead"])
        #expect(record.completedForOtherDays.map(\.status) == [.late(on: day), .doneAhead(on: day)])
    }

    /// Payouts are already on the quest / routine lines; everything else gets its own list. The
    /// net is every entry booked to the day, spending included.
    @Test func ledgerSplitsPayoutsFromEverythingElse() throws {
        let ctx = try Fixtures.context()
        let q = quest(ctx, "easy", .easy, points: 12)
        Economy.record(ctx, kind: .quest, points: 12, dayKey: day, refID: q.id, now: Fixtures.date(day, hour: 9))
        Economy.record(ctx, kind: .routine, points: 20, dayKey: day, now: Fixtures.date(day, hour: 10))
        Economy.record(ctx, kind: .reroll, points: -10, dayKey: day, now: Fixtures.date(day, hour: 8))
        Economy.record(ctx, kind: .penalty, points: -25, dayKey: day, now: Fixtures.date(day, hour: 23))
        Economy.record(ctx, kind: .redeem, points: -100, dayKey: "2026-09-18")
        try ctx.save()
        let record = try DayRecord.load(day, in: ctx)
        #expect(record.otherLedger.map(\.kind) == ["reroll", "penalty"])
        #expect(record.netPoints == 12 + 20 - 10 - 25)
    }

    /// A rating hangs off the completion that prompted it, even if it is dated the next day;
    /// a rating given this day for something not on the page is listed on its own.
    @Test func ratingsAttachByQuestID() throws {
        let ctx = try Fixtures.context()
        let q = quest(ctx, "easy", .easy, points: 12)
        Feedback.rate(ctx, target: .quest, id: nil, questID: q.id, text: "easy", rating: 2,
                      dayKey: "2026-09-18", now: Fixtures.date("2026-09-18", hour: 0))
        Feedback.rate(ctx, target: .quest, id: nil, questID: nil, text: "loose", rating: -1, dayKey: day)
        Feedback.rate(ctx, target: .quest, id: nil, questID: nil, text: "elsewhere", rating: 1, dayKey: "2026-09-10")
        try ctx.save()
        let record = try DayRecord.load(day, in: ctx)
        #expect(record.quests.first?.ratings.map(\.rating) == [2])
        #expect(record.otherRatings.map(\.textSnapshot) == ["loose"])
    }

    @Test func carriesTheDaysContext() throws {
        let ctx = try Fixtures.context()
        let c = DailyContext()
        c.dayKey = day
        c.tier = .low
        c.hrv = 42
        ctx.insert(c)
        try ctx.save()
        let record = try DayRecord.load(day, in: ctx)
        #expect(record.context?.tier == .low)
        #expect(try DayRecord.load("2026-09-18", in: ctx).context == nil)
    }
}
