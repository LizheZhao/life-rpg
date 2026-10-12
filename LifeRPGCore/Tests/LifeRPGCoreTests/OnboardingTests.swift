import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// The intro is for someone new to the app: a phone that has no record of it being used.
struct OnboardingTests {
    private let day = "2026-10-08"

    @Test func aFreshStoreShowsTheIntro() throws {
        let ctx = try Fixtures.context()
        #expect(try Onboarding.hasHistory(in: ctx) == false)
        #expect(try Onboarding.shouldShow(introDone: false, in: ctx))
    }

    /// The first launch draws today and gives the opening balance before the intro is up; neither
    /// is the person's own doing, so neither counts as having used the app.
    @Test func aDrawnDayAndTheOpeningBalanceAreNotHistory() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        try Economy.grantStartingBalanceIfNeeded(ctx, dayKey: day)
        var rng = SeededRNG(seed: 1)
        try DayService.ensureToday(ctx, now: Fixtures.date(day), in: Fixtures.tokyo, rng: &rng)
        Fixtures.occurrence(ctx, "Plan the week", due: day)
        #expect(try Onboarding.hasHistory(in: ctx) == false)
    }

    @Test func aFinishedQuestIsHistory() throws {
        let ctx = try Fixtures.context()
        let quest = DailyQuest(); quest.dayKey = day; quest.points = 12; quest.completedAt = Fixtures.date(day)
        ctx.insert(quest)
        #expect(try Onboarding.hasHistory(in: ctx))
        #expect(try Onboarding.shouldShow(introDone: false, in: ctx) == false)
    }

    @Test func aFinishedRoutineIsHistory() throws {
        let ctx = try Fixtures.context()
        Fixtures.occurrence(ctx, "Plan the week", due: day, completed: day)
        #expect(try Onboarding.hasHistory(in: ctx))
    }

    @Test func aWrittenDayIsHistoryAndAnEmptyOneIsNot() throws {
        let ctx = try Fixtures.context()
        let empty = JournalEntry(); empty.dayKey = day
        ctx.insert(empty)
        #expect(try Onboarding.hasHistory(in: ctx) == false)
        try JournalEntries.save([.text(id: UUID(), text: "wrote today")], on: day, in: ctx, now: Fixtures.date(day, hour: 21))
        #expect(try Onboarding.hasHistory(in: ctx))
    }

    /// Once the intro has been through, it is not shown again on its own, whatever the store holds.
    @Test func aFinishedIntroIsNotShownAgain() throws {
        let ctx = try Fixtures.context()
        #expect(try Onboarding.shouldShow(introDone: true, in: ctx) == false)
    }

    /// Erasing every record is a new person starting: with the flag cleared the intro comes back.
    @Test func erasingRecordsBringsTheIntroBack() throws {
        let ctx = try Fixtures.context()
        Fixtures.occurrence(ctx, "Plan the week", due: day, completed: day)
        try ctx.save()
        #expect(try Onboarding.shouldShow(introDone: false, in: ctx) == false)
        try EraseRecords.erase(in: ctx)
        #expect(try Onboarding.shouldShow(introDone: false, in: ctx))
    }
}
