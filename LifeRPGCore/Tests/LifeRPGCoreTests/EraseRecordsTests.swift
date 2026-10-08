import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// "Erase all records" is for whoever has been trying the app and wants to start for real: the
/// history and everything the use of it left behind go, the library the person built stays.
struct EraseRecordsTests {
    private let tz = Fixtures.tokyo
    private let day = "2026-10-07"

    /// A store with a bit of everything a few days of use leaves.
    private func usedStore() throws -> (ModelContext, kept: QuestTemplate, edited: RoutineTask) {
        let ctx = try Fixtures.context()
        try SeedImporter.seedIfEmpty(ctx, sideQuestsCSV: try Fixtures.csv("side_quests.csv"),
                                     routinesCSV: try Fixtures.csv("routine_quests.csv"))
        try Economy.grantStartingBalanceIfNeeded(ctx, dayKey: day)
        var rng = SeededRNG(seed: 5)
        try DayService.ensureToday(ctx, now: Fixtures.date(day, hour: 9), in: tz, rng: &rng)
        for quest in try DayService.quests(on: day, in: ctx) where quest.slot != .epic {
            quest.trivialDone = quest.trivialDone.map { _ in true }
            try Completion.complete(quest, tier: .normal, in: ctx, rng: &rng)
        }
        let rated = try #require(try DayService.quests(on: day, in: ctx).first { $0.templateID != nil })
        Feedback.rate(ctx, target: .quest, id: rated.templateID, questID: rated.id, text: rated.textSnapshot,
                      rating: 2, dayKey: day)
        Feedback.comment(ctx, target: .quest, id: rated.templateID, text: rated.textSnapshot, comment: "nice", dayKey: day)
        let reward = Reward(); reward.name = "Tea"; reward.fixedCoins = 20
        ctx.insert(reward)
        try JournalEntries.save([.text(id: UUID(), text: "wrote today")], on: day, in: ctx, now: Fixtures.date(day, hour: 21))
        let turn = JournalTurn(); turn.dayKey = day; turn.answer = "an old turn"
        ctx.insert(turn)
        try Affinity.sync(ctx)

        // The person's own library work, which has to survive.
        let mine = try LibrarySave.saveQuest(text: "My own quest", .init(difficulty: .easy), in: ctx)
        let routine = try #require(try ctx.fetch(FetchDescriptor<RoutineTask>()).first { $0.spec != "" })
        try LibraryEdit.setDifficulty(.hard, forRoutine: routine.id, in: ctx)
        try ctx.save()
        return (ctx, mine, routine)
    }

    private func count<T: PersistentModel>(_ ctx: ModelContext, _ type: T.Type) throws -> Int {
        try ctx.fetchCount(FetchDescriptor<T>())
    }

    @Test func everyHistoryTableIsEmptiedAndNothingElseIsTouchedInTheCountOfLibraryRows() throws {
        let (ctx, _, _) = try usedStore()
        let quests = try count(ctx, QuestTemplate.self), routines = try count(ctx, RoutineTask.self)
        let result = try EraseRecords.erase(in: ctx)
        for n in [try count(ctx, DailyQuest.self), try count(ctx, RoutineOccurrence.self), try count(ctx, LedgerEntry.self),
                  try count(ctx, DailyContext.self), try count(ctx, QuestRating.self), try count(ctx, QuestComment.self),
                  try count(ctx, Reward.self), try count(ctx, JournalEntry.self), try count(ctx, JournalTurn.self)] {
            #expect(n == 0)
        }
        let questsAfter = try count(ctx, QuestTemplate.self), routinesAfter = try count(ctx, RoutineTask.self)
        #expect(questsAfter == quests && routinesAfter == routines)
        #expect(result.ledgerEntries > 0 && result.dailyQuests > 0 && result.journalEntries == 1 && result.rewards == 1)
    }

    @Test func theLibraryTheUserBuiltStays() throws {
        let (ctx, mine, routine) = try usedStore()
        let id = routine.id
        try LibraryEdit.rename("Reworded", .quest, id: mine.id, in: ctx)
        try EraseRecords.erase(in: ctx)
        let kept = try #require(try ctx.fetch(FetchDescriptor<QuestTemplate>()).first { $0.id == mine.id })
        #expect(kept.text == "Reworded" && kept.origin == .user)
        let r = try #require(try ctx.fetch(FetchDescriptor<RoutineTask>()).first { $0.id == id })
        #expect(r.difficulty == .hard)
    }

    @Test func archivedAndSwitchedOffRowsStayThatWay() throws {
        let (ctx, _, _) = try usedStore()
        let quests = try ctx.fetch(FetchDescriptor<QuestTemplate>())
        let gone = quests[0], off = quests[1]
        try LibraryEdit.archive(.quest, id: gone.id, in: ctx)
        try LibraryEdit.setActive(false, .quest, id: off.id, in: ctx)
        try EraseRecords.erase(in: ctx)
        #expect(gone.isArchived && !gone.isActive && !off.isActive && !off.isArchived)
    }

    /// Cooldowns, "last drawn" days and affinity all come from the history just erased; left in
    /// place they would keep a quest out of the pool for days after a fresh start.
    @Test func whatTheHistoryLeftOnTheLibraryIsReset() throws {
        let (ctx, _, _) = try usedStore()
        let stamped = try ctx.fetch(FetchDescriptor<QuestTemplate>()).filter { $0.lastCompletedDayKey != nil || $0.lastServedDayKey != nil }
        #expect(!stamped.isEmpty)
        try ctx.fetch(FetchDescriptor<QuestTemplate>()).first?.affinity = 2
        try EraseRecords.erase(in: ctx)
        for t in try ctx.fetch(FetchDescriptor<QuestTemplate>()) {
            #expect(t.lastServedDayKey == nil && t.lastCompletedDayKey == nil && t.affinity == 0, "\(t.text)")
        }
        for r in try ctx.fetch(FetchDescriptor<RoutineTask>()) { #expect(r.lastCompletedDayKey == nil, "\(r.text)") }
    }

    @Test func theStoreIsCleanAndTheBalanceIsZeroUntilTheOpeningGrantIsGivenAgain() throws {
        let (ctx, _, _) = try usedStore()
        try EraseRecords.erase(in: ctx)
        #expect(try StoreAudit.issues(ctx).isEmpty)
        #expect(try Economy.balance(ctx) == 0)
        let granted = try Economy.grantStartingBalanceIfNeeded(ctx, dayKey: day)
        let balance = try Economy.balance(ctx)
        #expect(granted?.points == Economy.startingBalance && balance == 100)
    }

    @Test func aDayCanBeDrawnAgainRightAway() throws {
        let (ctx, _, _) = try usedStore()
        try EraseRecords.erase(in: ctx)
        var rng = SeededRNG(seed: 9)
        try DayService.ensureToday(ctx, now: Fixtures.date(day, hour: 20), in: tz, rng: &rng)
        #expect(try !DayService.quests(on: day, in: ctx).isEmpty)
        #expect(try DayService.dailyContext(for: day, in: ctx) != nil)
    }

    @Test func anEmptyStoreIsAFineThingToErase() throws {
        let ctx = try Fixtures.context()
        let result = try EraseRecords.erase(in: ctx)
        #expect(result == EraseRecords.Result())
    }

    @Test func theCountsSayWhatIsAboutToGo() throws {
        let (ctx, _, _) = try usedStore()
        let before = try EraseRecords.preview(in: ctx)
        #expect(before.ledgerEntries == (try count(ctx, LedgerEntry.self)))
        #expect(before.journalEntries == 1 && before.ratings == 1 && before.rewards == 1)
        let result = try EraseRecords.erase(in: ctx)
        #expect(result == before)
    }

    @Test func theCardNamesWhatWillBeErasedAndWhatStays() throws {
        let (ctx, _, _) = try usedStore()
        let text = try EraseRecords.preview(in: ctx).message
        #expect(text.contains("journal") && text.contains("Your library stays"))
        #expect(text.contains("can't be undone"))
    }
}
