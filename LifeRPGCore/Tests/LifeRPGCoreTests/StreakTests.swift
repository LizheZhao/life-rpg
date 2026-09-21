import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// Consecutive days with at least one random quest completed.
struct StreakTests {
    private let tz = Fixtures.tokyo

    @Test func countsConsecutiveDaysBackFromToday() {
        let days: Set<String> = ["2026-09-16", "2026-09-17", "2026-09-18"]
        #expect(Streak.current(days: days, today: "2026-09-18", in: tz) == 3)
    }

    /// Nothing done yet today shows yesterday's run rather than 0 — the day isn't over.
    @Test func todayStillEmptyKeepsYesterdaysRun() {
        let days: Set<String> = ["2026-09-16", "2026-09-17"]
        #expect(Streak.current(days: days, today: "2026-09-18", in: tz) == 2)
    }

    @Test func aWholeMissedDayBreaksIt() {
        let days: Set<String> = ["2026-09-15", "2026-09-16"]     // 17th missed entirely
        #expect(Streak.current(days: days, today: "2026-09-18", in: tz) == 0)
    }

    @Test func emptyHistoryIsZero() {
        #expect(Streak.current(days: [], today: "2026-09-18", in: tz) == 0)
    }

    @Test func crossesMonthAndYearBoundaries() {
        let days: Set<String> = ["2025-12-30", "2025-12-31", "2026-01-01"]
        #expect(Streak.current(days: days, today: "2026-01-01", in: tz) == 3)
    }

    /// Epic and replaced slots don't count (PLAN §3); the T group and hidden do.
    @Test func onlyRandomSlotsCount() throws {
        let ctx = try Fixtures.context()
        func quest(_ dayKey: String, slot: Difficulty, hidden: Bool = false, replaced: Bool = false) {
            let q = DailyQuest()
            q.dayKey = dayKey
            q.slot = slot
            q.isHiddenSlot = hidden
            q.replaced = replaced
            q.completedAt = Fixtures.date(dayKey)
            q.points = 10
            ctx.insert(q)
        }
        quest("2026-09-18", slot: .epic)                       // epic: ignored
        quest("2026-09-17", slot: .medium, replaced: true)     // bumped by an ad-hoc routine
        quest("2026-09-16", slot: .easy, hidden: true)         // hidden counts
        try ctx.save()
        #expect(try Streak.completedDayKeys(ctx) == ["2026-09-16"])
        #expect(try Streak.current(ctx, today: "2026-09-18", in: tz) == 0)
    }

    /// The today page passes its own `@Query` array to the same function the store-backed version
    /// uses, so the HUD's streak and Core's streak are the same computation, not two copies of it.
    @Test func theArrayAndStoreReadingsAgree() throws {
        let ctx = try Fixtures.context()
        let day = "2026-09-18"
        let done = DailyQuest(); done.dayKey = day; done.completedAt = Fixtures.date(day); ctx.insert(done)
        let epic = DailyQuest(); epic.dayKey = day; epic.slot = .epic
        epic.completedAt = Fixtures.date(day); ctx.insert(epic)
        let replaced = DailyQuest(); replaced.dayKey = "2026-09-17"; replaced.replaced = true
        replaced.completedAt = Fixtures.date("2026-09-17"); ctx.insert(replaced)
        let open = DailyQuest(); open.dayKey = day; ctx.insert(open)
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<DailyQuest>())
        #expect(Streak.completedDayKeys(all) == (try Streak.completedDayKeys(ctx)))
        #expect(Streak.completedDayKeys(all) == [day])          // epic and replaced don't count
    }
}
