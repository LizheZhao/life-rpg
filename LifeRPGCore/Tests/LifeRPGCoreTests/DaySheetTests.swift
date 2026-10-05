import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// The calendar's day sheet: its header, the done / total of each section, and when it opens.
struct DaySheetTests {
    private let day = "2026-10-01"
    private let tz = Fixtures.tokyo

    private func quest(_ ctx: ModelContext, _ slot: Difficulty, done: Bool, replaced: Bool = false,
                       hidden: Bool = false, on dayKey: String? = nil) {
        let q = DailyQuest()
        q.dayKey = dayKey ?? day
        q.slot = slot
        q.isHiddenSlot = hidden
        q.textSnapshot = "\(slot.rawValue) quest"
        q.completedAt = done ? Fixtures.date(dayKey ?? day) : nil
        q.replaced = replaced
        ctx.insert(q)
    }

    private func record(_ ctx: ModelContext, _ dayKey: String? = nil) throws -> DayRecord {
        try ctx.save()
        return try DayRecord.load(dayKey ?? day, in: ctx)
    }

    // MARK: done / total

    @Test func routinesCountTheOnesDoneOverTheOnesAsked() throws {
        let ctx = try Fixtures.context()
        Fixtures.occurrence(ctx, "on time", due: day, completed: day)
        Fixtures.occurrence(ctx, "late", due: day, completed: "2026-10-02")
        Fixtures.occurrence(ctx, "ahead", due: day, completed: "2026-09-29")
        Fixtures.occurrence(ctx, "skipped", due: day).skipped = true
        Fixtures.occurrence(ctx, "open", due: day)
        let progress = DaySheet.routineProgress(try record(ctx).routines)
        #expect(progress == DaySheet.Progress(done: 3, total: 5))
        #expect(progress.text == "3 / 5 done")
    }

    @Test func aReplacedRoutineIsNotWhatTheDayAsked() throws {
        let ctx = try Fixtures.context()
        Fixtures.occurrence(ctx, "kept", due: day, completed: day)
        let swapped = Fixtures.occurrence(ctx, "swapped", due: day)
        swapped.replacedByID = UUID()
        #expect(DaySheet.routineProgress(try record(ctx).routines) == DaySheet.Progress(done: 1, total: 1))
    }

    @Test func questsCountCompletedOverTheDrawnSlotsAndLeaveReplacedOnesOut() throws {
        let ctx = try Fixtures.context()
        quest(ctx, .easy, done: true)
        quest(ctx, .hard, done: true)
        quest(ctx, .medium, done: false)
        quest(ctx, .medium, done: false, replaced: true)
        quest(ctx, .easy, done: true, hidden: true)
        let progress = DaySheet.questProgress(try record(ctx).quests)
        #expect(progress == DaySheet.Progress(done: 3, total: 4))
        #expect(progress.text == "3 / 4 done")
    }

    @Test func aSectionWithNothingInItIsZeroOverZero() {
        #expect(DaySheet.routineProgress([]) == DaySheet.Progress(done: 0, total: 0))
        #expect(DaySheet.questProgress([]).text == "0 / 0 done")
    }

    // MARK: the header

    @Test func theHeaderIsTheWeekdayTheDateTheCoinsAndTheDayType() {
        let header = DaySheet.header(dayKey: "2026-10-01", net: 120, tier: .normal, language: .en, timeZone: tz)
        #expect(header.weekday == "Thursday")
        #expect(header.date == "October 1")
        #expect(header.coins == "+120 coins")
        #expect(header.dayType == "normal day")
    }

    @Test func coinsAreSignedAndOneIsSingular() {
        #expect(DaySheet.coinsText(1) == "+1 coin")
        #expect(DaySheet.coinsText(0) == "0 coins")
        #expect(DaySheet.coinsText(-35) == "-35 coins")
    }

    @Test func aDayWithoutContextHasNoDayTypeTag() {
        #expect(DaySheet.header(dayKey: day, net: 0, tier: nil, language: .en, timeZone: tz).dayType == nil)
        #expect(DaySheet.header(dayKey: day, net: 0, tier: .veryLow, language: .en, timeZone: tz).dayType == "very low day")
    }

    // MARK: when it opens

    @Test func aDayWithNothingAtAllOpensNothing() throws {
        let ctx = try Fixtures.context()
        quest(ctx, .easy, done: true, on: "2026-10-02")
        #expect(!DaySheet.opens(try record(ctx), hasEntry: false))
    }

    @Test func aQuestOnlyDayOpens() throws {
        let ctx = try Fixtures.context()
        quest(ctx, .easy, done: false)
        #expect(DaySheet.opens(try record(ctx), hasEntry: false))
    }

    @Test func aRoutineOnlyDayOpens() throws {
        let ctx = try Fixtures.context()
        Fixtures.occurrence(ctx, "r", due: day)
        #expect(DaySheet.opens(try record(ctx), hasEntry: false))
    }

    @Test func aDayWithOnlyAnEntryOpens() throws {
        let ctx = try Fixtures.context()
        #expect(DaySheet.opens(try record(ctx), hasEntry: true))
    }

    @Test func aDayWithOnlyMoneyMovingOpens() throws {
        let ctx = try Fixtures.context()
        Economy.record(ctx, kind: .penalty, points: -25, dayKey: day, now: Fixtures.date(day, hour: 23))
        #expect(DaySheet.opens(try record(ctx), hasEntry: false))
    }

    // MARK: writing about a day

    @Test func aPastDayAndTodayCanBeWrittenAboutButNotAFutureDay() {
        #expect(DaySheet.canWrite(dayKey: "2026-10-03", today: "2026-10-04"))
        #expect(DaySheet.canWrite(dayKey: "2026-10-04", today: "2026-10-04"))
        #expect(!DaySheet.canWrite(dayKey: "2026-10-05", today: "2026-10-04"))
    }

    // MARK: the sections' open state

    @Test func routinesStartOpenAndQuestsClosed() {
        let sections = DaySheet.Sections()
        #expect(sections.routinesOpen)
        #expect(!sections.questsOpen)
    }

    @Test func eachSectionToggleFlipsOnlyItself() {
        var sections = DaySheet.Sections()
        sections.toggle(.quests)
        #expect(sections.routinesOpen && sections.questsOpen)
        sections.toggle(.routines)
        #expect(!sections.routinesOpen && sections.questsOpen)
        sections.toggle(.quests)
        #expect(!sections.routinesOpen && !sections.questsOpen)
    }
}
