import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// The planner and the signals are pure; these tests are that the service wires them to the real
/// tables and that a day's journal can be played from the store alone, including across a restart.
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
        Feedback.comment(ctx, target: .quest, id: rated.templateID, questID: rated.id,
                         text: rated.textSnapshot, comment: "loved it", dayKey: friday)
        try ctx.save()

        let signals = try JournalService.signals(on: friday, in: ctx, timeZone: tz)
        #expect(signals.tier == .low)
        #expect(signals.completedCount == done)
        #expect(signals.completed.first { $0.subject.id == rated.id }?.rating == 2)
        #expect(signals.skipped.map(\.text) == ["Take out the trash"])
        #expect(signals.comments == ["loved it"])
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

    /// Plays the journal against the store: answer, record, ask the store again.
    private func play(_ ctx: ModelContext, day: String = "2026-09-18", answer: String = "short") throws -> [String] {
        var log: [String] = []
        for _ in 0..<20 {
            let now = Fixtures.date(day, hour: 22)
            switch try JournalService.next(on: day, in: ctx, language: .en, timeZone: tz) {
            case .ask(let q):
                log.append(q.promptID)
                try JournalService.record(ctx, dayKey: day, kind: q.kind, promptID: q.promptID, question: q.text,
                                          subject: q.subject, answer: answer, language: .en, askedAt: now, answeredAt: now)
            case .followUp(let request):
                log.append("followUp")
                try JournalService.record(ctx, dayKey: day, kind: .followUp, promptID: request.fallback.promptID,
                                          question: request.fallback.text, answer: answer, language: .en,
                                          askedAt: now, answeredAt: now)
            case .safety:
                log.append("safety")
                try JournalService.record(ctx, dayKey: day, kind: .safety, promptID: "safety",
                                          question: JournalSafety.line(language: .en), language: .en,
                                          askedAt: now, answeredAt: now)
            case .done:
                try ctx.save()
                return log
            }
            try ctx.save()
        }
        Issue.record("the day never ended")
        return log
    }

    @Test func aDayIsPlayedFromTheStoreAndEndsOnce() throws {
        let (ctx, _) = try playedDay()
        let log = try play(ctx)
        // Low tier: the heavy question; the rated quest: the good question; opening and closing around them.
        #expect(log.first == "open.keep")
        #expect(log.last == "close.carry")
        #expect(log.count == 4)
        #expect(Set(log.dropFirst().dropLast().map { JournalPool.prompt(id: $0)?.kind }) == [.heavy, .good])

        let turns = try JournalService.turns(on: friday, in: ctx)
        #expect(turns.map(\.index) == [0, 1, 2, 3])
        #expect(turns.map(\.promptID) == log)
        // Asking again changes nothing.
        #expect(try JournalService.next(on: friday, in: ctx, language: .en, timeZone: tz) == .done)
        #expect(try ctx.fetchCount(FetchDescriptor<JournalTurn>()) == 4)
    }

    /// An app kill between two answers: a store holding the first turns is all the planner needs.
    @Test func aDayInterruptedHalfwayResumesWhereItStopped() throws {
        let (ctx, _) = try playedDay()
        let whole = try play(ctx)
        // Rewind the store to the first two turns, as if the app had been killed there.
        for turn in try JournalService.turns(on: friday, in: ctx) where turn.index >= 2 { ctx.delete(turn) }
        try ctx.save()
        guard case .ask(let next) = try JournalService.next(on: friday, in: ctx, language: .en, timeZone: tz)
        else { Issue.record("expected the third question"); return }
        #expect(next.promptID == whole[2])
        #expect(try play(ctx) == Array(whole.dropFirst(2)))
    }

    @Test func habitsFromEarlierDaysChangeTheRanking() throws {
        let (ctx, _) = try playedDay()
        let at = Fixtures.date(friday, hour: 21)
        try JournalService.record(ctx, dayKey: friday, kind: .opening, question: "q", answer: "x",
                                  language: .en, askedAt: at, answeredAt: at)
        try ctx.save()
        func nextKind() throws -> JournalPromptKind? {
            guard case .ask(let q) = try JournalService.next(on: friday, in: ctx, language: .en, timeZone: tz) else { return nil }
            return q.kind
        }
        // No history: heavy (4) comes before good (2.5).
        #expect(try nextKind() == .heavy)

        // Three earlier evenings where the heavy question was called a misfit: 4 x 0.25 = 1.
        for day in ["2026-09-10", "2026-09-11", "2026-09-12"] {
            let earlier = Fixtures.date(day, hour: 22)
            try JournalService.record(ctx, dayKey: day, kind: .heavy, promptID: "heavy.body", question: "q",
                                      answer: "", outcome: .misfit, language: .en, askedAt: earlier, answeredAt: earlier)
        }
        try ctx.save()
        #expect(try JournalService.habits(asOf: friday, in: ctx, timeZone: tz).weight(for: .heavy) == 0.25)
        #expect(try nextKind() == .good)
    }

    @Test func theComposedJournalIsTheUsersAnswersInOrder() throws {
        let (ctx, _) = try playedDay()
        _ = try play(ctx, answer: "mine")
        let text = JournalComposer.text(turns: try JournalService.turns(on: friday, in: ctx), language: .en)
        #expect(text.hasPrefix("Journal 2026-09-18\n\nWhat from today do you want to remember?\nmine\n\n"))
        #expect(text.hasSuffix("Is there one thing you want to carry into tomorrow?\nmine"))
        #expect(text.components(separatedBy: "\nmine").count - 1 == 4)
    }
}

// MARK: what the pages open with

struct JournalPagesServiceTests {
    private let friday = "2026-09-18"
    private let now = Fixtures.date("2026-09-18", hour: 22)

    @Test func theDraftOpensEmptyOnADayWithNoFreeWriting() throws {
        let ctx = try Fixtures.context()
        try JournalService.record(ctx, dayKey: friday, kind: .opening, promptID: "open.keep", question: "Q",
                                  answer: "A", language: .en, askedAt: now, answeredAt: now)
        #expect(try JournalService.freeWritingDraft(on: friday, in: ctx) == FreeWritingDraft())
    }

    @Test func theDraftOpensWithTheStoredTextAndTime() throws {
        let ctx = try Fixtures.context()
        try JournalService.saveFreeWriting("Rain, then tea.", writingSeconds: 75, on: friday, language: .en,
                                           in: ctx, now: now)
        try ctx.save()
        let draft = try JournalService.freeWritingDraft(on: friday, in: ctx)
        #expect(draft.text == "Rain, then tea.")
        #expect(draft.writingSeconds == 75)
        #expect(!draft.hasUnsavedChanges)
    }

    @Test func theHistoryListsEveryDayWithWritingNewestFirst() throws {
        let ctx = try Fixtures.context()
        try JournalService.saveFreeWriting("one", writingSeconds: 0, on: "2026-09-16", language: .en, in: ctx, now: now)
        try JournalService.saveFreeWriting("two words", writingSeconds: 0, on: friday, language: .en, in: ctx, now: now)
        try JournalService.record(ctx, dayKey: "2026-09-17", kind: .opening, question: "Q", answer: "",
                                  outcome: .skipped, language: .en, askedAt: now, answeredAt: now)
        try ctx.save()
        let days = try JournalService.history(language: .en, in: ctx)
        #expect(days.map(\.dayKey) == [friday, "2026-09-16"])
        #expect(days.map(\.wordCount) == [2, 1])
    }

    @Test func theStartersOpenWithGratefulFor() throws {
        let ctx = try Fixtures.context()
        let starters = try JournalService.starters(on: friday, language: .en, in: ctx, timeZone: Fixtures.tokyo)
        #expect(starters.first?.text == "Grateful for")
        #expect(starters.count <= 4)
    }
}
