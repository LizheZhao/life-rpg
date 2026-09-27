import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// The weekly epic: drawn once a week, live through Sunday, extendable twice (`PLAN.md` §3, §6).
struct EpicTests {
    private let tz = Fixtures.tokyo
    private let monday = "2026-09-21"         // 2026-W39
    private let wednesday = "2026-09-23"
    private let sunday = "2026-09-27"
    private let nextMonday = "2026-09-28"     // 2026-W40

    private func library(_ ctx: ModelContext, epics: Int = 3) {
        Fixtures.stockLibrary(ctx)
        for i in 0..<epics { Fixtures.quest(ctx, "epic #\(i)", .epic) }
    }

    @discardableResult
    private func open(_ ctx: ModelContext, _ dayKey: String, seed: UInt64 = 1) throws -> DailyContext {
        var rng = SeededRNG(seed: seed)
        return try DayService.ensureToday(ctx, now: Fixtures.date(dayKey), in: tz, rng: &rng)
    }

    private func epics(_ ctx: ModelContext) throws -> [DailyQuest] {
        try ctx.fetch(FetchDescriptor<DailyQuest>()).filter { $0.slot == .epic }
    }

    private func fund(_ ctx: ModelContext, _ amount: Int) throws {
        Economy.record(ctx, kind: .adjust, points: amount, dayKey: monday)
        try ctx.save()
    }

    // MARK: generation

    /// Monday draws one, outside the composition table: three random slots still means three.
    @Test func mondayDrawsOneEpicBesideTheSlots() throws {
        let ctx = try Fixtures.context()
        library(ctx)
        let day = try open(ctx, monday)

        let drawn = try epics(ctx)
        #expect(drawn.count == 1)
        #expect(drawn[0].dayKey == monday)
        #expect(drawn[0].weekKey == "2026-W39")
        #expect(day.randomSlots == 3)
        #expect(try DayService.quests(on: monday, in: ctx).filter { $0.slot != .epic }.count == 3)
    }

    /// Visible all week, and the rest of the week draws no second one.
    @Test func theSameEpicIsLiveAllWeek() throws {
        let ctx = try Fixtures.context()
        library(ctx)
        try open(ctx, monday)
        let first = try #require(try epics(ctx).first)

        for (i, day) in [wednesday, sunday].enumerated() {
            try open(ctx, day, seed: UInt64(10 + i))
            #expect(try Epic.current(on: day, in: ctx, timeZone: tz)?.id == first.id)
        }
        #expect(try epics(ctx).count == 1)
        #expect(Epic.lastDayKey(of: first, in: tz) == sunday)
    }

    /// First opened on Wednesday: drawn then, and still only lives to Sunday.
    @Test func firstOpenMidweekDrawsThatDay() throws {
        let ctx = try Fixtures.context()
        library(ctx)
        try open(ctx, wednesday)
        let epic = try #require(try epics(ctx).first)
        #expect(epic.dayKey == wednesday)
        #expect(Epic.lastDayKey(of: epic, in: tz) == sunday)
    }

    /// A day already generated before epics existed still gets one on the next foreground.
    @Test func anAlreadyGeneratedDayPicksUpTheEpic() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        try open(ctx, monday)
        #expect(try epics(ctx).isEmpty)

        Fixtures.quest(ctx, "late epic", .epic)
        try open(ctx, monday, seed: 2)
        #expect(try epics(ctx).map(\.textSnapshot) == ["late epic"])
    }

    /// Next Monday: a new one. The old unfinished one stays in history, open, unpunished.
    @Test func aNewWeekDrawsANewEpicAndTheOldOneJustRunsOut() throws {
        let ctx = try Fixtures.context()
        library(ctx)
        try open(ctx, monday)
        let old = try #require(try epics(ctx).first)

        try open(ctx, nextMonday, seed: 2)
        let now = try #require(try Epic.current(on: nextMonday, in: ctx, timeZone: tz))
        #expect(now.id != old.id)
        #expect(now.weekKey == "2026-W40")
        #expect(old.completedAt == nil)
        #expect(!Epic.covers(old, nextMonday, in: tz))
        let penalties = try ctx.fetch(FetchDescriptor<LedgerEntry>()).filter { $0.points < 0 }
        #expect(penalties.isEmpty)
    }

    @Test func theSameEpicDoesNotComeRoundTwoWeeksRunning() throws {
        let ctx = try Fixtures.context()
        library(ctx, epics: 2)
        var day = monday
        var previous: UUID?
        for seed in 1...6 {
            try open(ctx, day, seed: UInt64(seed))
            let epic = try #require(try Epic.current(on: day, in: ctx, timeZone: tz))
            #expect(epic.templateID != previous)
            previous = epic.templateID
            day = try #require(DayKey.adding(7, to: day, in: tz))
        }
    }

    /// With only one epic in the library it repeats rather than leaving the week empty.
    @Test func aSingleEpicStillComesBackNextWeek() throws {
        let ctx = try Fixtures.context()
        library(ctx, epics: 1)
        try open(ctx, monday)
        try open(ctx, nextMonday, seed: 2)
        #expect(try epics(ctx).count == 2)
    }

    /// It never gates the full clear: every random slot done unlocks hidden with the epic open.
    @Test func theEpicDoesNotGateTheFullClear() throws {
        let ctx = try Fixtures.context()
        library(ctx)
        try open(ctx, monday)
        var rng = SeededRNG(seed: 3)
        for q in try DayService.quests(on: monday, in: ctx) where q.slot != .epic {
            q.trivialDone = q.trivialDone.map { _ in true }
            try Completion.complete(q, tier: .normal, in: ctx, now: Fixtures.date(monday), rng: &rng)
        }
        #expect(try DayService.hiddenUnlocked(on: monday, in: ctx))
    }

    // MARK: completion

    /// Paid on the day it was done, which is also where its cooldown starts.
    @Test func completingMidweekBooksToThatDay() throws {
        let ctx = try Fixtures.context()
        library(ctx)
        try open(ctx, monday)
        let epic = try #require(try epics(ctx).first)

        var rng = SeededRNG(seed: 4)
        let points = try Completion.complete(epic, tier: .normal, in: ctx,
                                             now: Fixtures.date(wednesday), timeZone: tz, rng: &rng)
        #expect((60...150).contains(points))
        let entry = try #require(try ctx.fetch(FetchDescriptor<LedgerEntry>()).first { $0.refID == epic.id })
        #expect(entry.dayKey == wednesday)
        let template = try #require(try ctx.fetch(FetchDescriptor<QuestTemplate>()).first { $0.id == epic.templateID })
        #expect(template.lastCompletedDayKey == wednesday)
        // Done, but still this week's: no second epic appears on Thursday.
        try open(ctx, "2026-09-24", seed: 5)
        #expect(try epics(ctx).count == 1)
    }

    // MARK: extension

    @Test func extendingPushesItAWeekAndCosts50() throws {
        let ctx = try Fixtures.context()
        library(ctx)
        try open(ctx, monday)
        try fund(ctx, 1000)
        let epic = try #require(try epics(ctx).first)

        try Epic.extend(epic, on: wednesday, in: ctx, timeZone: tz)
        #expect(epic.extensionCount == 1)
        #expect(Epic.lastDayKey(of: epic, in: tz) == "2026-10-04")
        #expect(try Economy.balance(ctx) == 950)
        let spend = try #require(try ctx.fetch(FetchDescriptor<LedgerEntry>()).first { $0.kind == "redeem" })
        #expect(spend.points == -50)
        #expect(spend.dayKey == wednesday)
        #expect(spend.refID == epic.id)

        // The week it spills into gets no epic of its own.
        try open(ctx, nextMonday, seed: 2)
        #expect(try epics(ctx).count == 1)
        #expect(try Epic.current(on: nextMonday, in: ctx, timeZone: tz)?.id == epic.id)
    }

    @Test func atMostTwoExtensions() throws {
        let ctx = try Fixtures.context()
        library(ctx)
        try open(ctx, monday)
        try fund(ctx, 2000)
        let epic = try #require(try epics(ctx).first)

        try Epic.extend(epic, on: monday, in: ctx, timeZone: tz)
        try Epic.extend(epic, on: monday, in: ctx, timeZone: tz)
        #expect(Epic.lastDayKey(of: epic, in: tz) == "2026-10-11")
        #expect(throws: Epic.Failure.maxExtensions) {
            try Epic.extend(epic, on: monday, in: ctx, timeZone: tz)
        }
        #expect(try Economy.balance(ctx) == 1900)
    }

    /// Same balance rule as a reroll: down to exactly zero is fine, below is not, debt blocks.
    @Test func extensionObeysTheBalanceRule() throws {
        let ctx = try Fixtures.context()
        library(ctx)
        try open(ctx, monday)
        let epic = try #require(try epics(ctx).first)

        try fund(ctx, 49)
        #expect(throws: Epic.Failure.blocked(.tooExpensive(cost: 50, balance: 49))) {
            try Epic.extend(epic, on: monday, in: ctx, timeZone: tz)
        }
        try fund(ctx, 1)
        try Epic.extend(epic, on: monday, in: ctx, timeZone: tz)
        #expect(try Economy.balance(ctx) == 0)

        try fund(ctx, -10)
        #expect(Epic.blocked(epic, on: monday, balance: -10, in: tz) == .blocked(.inDebt(balance: -10)))
    }

    @Test func aCompletedOrExpiredEpicCannotBeExtended() throws {
        let ctx = try Fixtures.context()
        library(ctx)
        try open(ctx, monday)
        let epic = try #require(try epics(ctx).first)

        #expect(Epic.blocked(epic, on: nextMonday, balance: 1000, in: tz) == .expired(lastDayKey: sunday))
        epic.completedAt = Fixtures.date(wednesday)
        #expect(Epic.blocked(epic, on: wednesday, balance: 1000, in: tz) == .alreadyCompleted)
    }

    // MARK: replacing by hand

    /// Free, keeps the deadline, and the old one stays as history.
    @Test func replacingWithALibraryEpicKeepsTheDeadline() throws {
        let ctx = try Fixtures.context()
        library(ctx)
        try open(ctx, monday)
        let old = try #require(try epics(ctx).first)
        let templates = try ctx.fetch(FetchDescriptor<QuestTemplate>())
        let candidates = Epic.replaceCandidates(templates, replacing: old)
        #expect(candidates.count == 2)
        #expect(!candidates.contains { $0.id == old.templateID })

        let fresh = try Epic.replace(old, with: .template(candidates[0]), on: wednesday, in: ctx, timeZone: tz)
        #expect(old.replaced && old.replacedReason == .swapped)
        #expect(fresh.dayKey == monday)
        #expect(Epic.lastDayKey(of: fresh, in: tz) == sunday)
        #expect(fresh.templateID == candidates[0].id)
        #expect(try Epic.current(on: wednesday, in: ctx, timeZone: tz)?.id == fresh.id)
        #expect(try ctx.fetch(FetchDescriptor<LedgerEntry>()).isEmpty)
        #expect(candidates[0].lastServedDayKey == wednesday)
    }

    /// A hand-written epic has no template and pays an ordinary epic roll.
    @Test func aCustomEpicPaysAnEpicRoll() throws {
        let ctx = try Fixtures.context()
        library(ctx)
        try open(ctx, monday)
        let old = try #require(try epics(ctx).first)
        #expect(throws: Epic.Failure.emptyText) {
            try Epic.replace(old, with: .custom(text: "  "), on: monday, in: ctx, timeZone: tz)
        }
        let fresh = try Epic.replace(old, with: .custom(text: "Run a half marathon"), on: monday,
                                     in: ctx, timeZone: tz)
        #expect(fresh.templateID == nil)
        #expect(fresh.textSnapshot == "Run a half marathon")

        var rng = SeededRNG(seed: 3)
        let points = try Completion.complete(fresh, tier: .normal, in: ctx,
                                             now: Fixtures.date(wednesday), timeZone: tz, rng: &rng)
        #expect((60...150).contains(points))
    }

    /// Same limits as a reroll: not once extended, not once done, not after it ran out.
    @Test func whatCantBeReplaced() throws {
        let ctx = try Fixtures.context()
        library(ctx)
        try open(ctx, monday)
        try fund(ctx, 1000)
        let epic = try #require(try epics(ctx).first)
        #expect(throws: Epic.Failure.sameEpic) {
            let same = try #require(try ctx.fetch(FetchDescriptor<QuestTemplate>()).first { $0.id == epic.templateID })
            try Epic.replace(epic, with: .template(same), on: monday, in: ctx, timeZone: tz)
        }
        #expect(Epic.blockedReplace(epic, on: nextMonday, in: tz) == .expired(lastDayKey: sunday))

        try Epic.extend(epic, on: monday, in: ctx, timeZone: tz)
        #expect(Epic.blockedReplace(epic, on: monday, in: tz) == .extended)
        epic.completedAt = Fixtures.date(wednesday)
        #expect(Epic.blockedReplace(epic, on: wednesday, in: tz) == .alreadyCompleted)
    }
}
