import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// The signals are pure; these tests are that the service reads them from the real tables.
struct JournalServiceTests {
    private let tz = Fixtures.tokyo
    private let friday = "2026-09-18"

    /// A played day: everything completed, one quest rated +2, an old routine still open.
    private func playedDay(tier: Tier = .low) throws -> (ModelContext, rated: DailyQuest) {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 4)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz, inputs: DayInputs(tier: tier), rng: &rng)
        let quests = try DayService.quests(on: friday, in: ctx).filter { !$0.replaced }
        for quest in quests {
            quest.trivialDone = quest.trivialDone.map { _ in true }
            try Completion.complete(quest, tier: tier, in: ctx, rng: &rng)
        }
        let rated = try #require(quests.first { $0.templateID != nil && !$0.isTrivialGroup })
        Feedback.rate(ctx, target: .quest, id: rated.templateID, questID: rated.id, text: rated.textSnapshot,
                      rating: 2, dayKey: friday, now: Fixtures.date(friday, hour: 12))
        try ctx.save()
        return (ctx, rated)
    }

    @Test func theSignalsAreReadFromTheDaysRows() throws {
        let (ctx, rated) = try playedDay()
        let done = try DayService.quests(on: friday, in: ctx).filter { !$0.replaced }.count
        Fixtures.occurrence(ctx, "Take out the trash", due: "2026-09-17")
        Fixtures.occurrence(ctx, "Due tonight", due: friday)
        let flexible = RoutineTask()
        flexible.text = "Gym"; flexible.flexibleWithinWeek = true
        ctx.insert(flexible)
        let gym = Fixtures.occurrence(ctx, "Gym session", due: "2026-09-16")
        gym.routineID = flexible.id
        try ctx.save()

        let signals = try JournalService.signals(on: friday, in: ctx, timeZone: tz)
        #expect(signals.tier == .low)
        #expect(signals.completedCount == done)
        #expect(signals.completed.first { $0.subject.id == rated.id }?.rating == 2)
        #expect(signals.skipped.map(\.text) == ["Take out the trash"])
    }

    @Test func aSettledRoutineIsFoundThroughTheLedger() throws {
        let ctx = try Fixtures.context()
        var rng = SeededRNG(seed: 1)
        try DayService.ensureToday(ctx, now: Fixtures.date(friday), in: tz, rng: &rng)
        let missed = Fixtures.occurrence(ctx, "Auto skipped", due: "2026-09-15")
        missed.skipped = true
        Economy.record(ctx, kind: .skip, points: 0, dayKey: friday, refID: missed.id, note: "Auto skipped")
        try ctx.save()
        #expect(try JournalService.signals(on: friday, in: ctx, timeZone: tz).skipped.map(\.text) == ["Auto skipped"])
        #expect(try JournalService.signals(on: "2026-09-19", in: ctx, timeZone: tz).skipped.isEmpty)
    }
}
