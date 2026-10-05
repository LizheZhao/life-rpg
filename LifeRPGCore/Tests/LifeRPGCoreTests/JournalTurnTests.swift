import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// The journal is the user's own writing and exists nowhere else, so what matters is that a turn
/// is stored as it was answered, survives a backup and restore, and is never touched by the debug
/// tools that rewind a day.
struct JournalTurnTests {
    private let tz = Fixtures.tokyo
    private let friday = "2026-09-18"

    @discardableResult
    private func turn(_ ctx: ModelContext, _ dayKey: String, _ kind: JournalPromptKind, answer: String,
                      subject: JournalSubject? = nil, outcome: JournalOutcome = .answered) throws -> JournalTurn {
        try JournalService.record(ctx, dayKey: dayKey, kind: kind, promptID: "open.keep",
                                  question: "What from today do you want to remember?", subject: subject,
                                  answer: answer, outcome: outcome, language: .en,
                                  askedAt: Fixtures.date(dayKey, hour: 21), answeredAt: Fixtures.date(dayKey, hour: 22))
    }

    @Test func turnsAreStoredInTheOrderTheyWereAskedAndPerDay() throws {
        let ctx = try Fixtures.context()
        try turn(ctx, friday, .opening, answer: "a")
        try turn(ctx, "2026-09-19", .opening, answer: "other day")
        try turn(ctx, friday, .good, answer: "b")
        try turn(ctx, friday, .closing, answer: "c")
        try ctx.save()

        let rows = try JournalService.turns(on: friday, in: ctx)
        #expect(rows.map(\.answer) == ["a", "b", "c"])
        #expect(rows.map(\.index) == [0, 1, 2])
        #expect(rows.map(\.kind) == [.opening, .good, .closing])
        #expect(try JournalService.turns(on: "2026-09-19", in: ctx).map(\.index) == [0])
    }

    @Test func aRowReadsBackWithEveryFieldItWasWrittenWith() throws {
        let ctx = try Fixtures.context()
        let subject = JournalSubject(kind: .routine, id: UUID(), text: "Take out the trash")
        let row = try JournalService.record(ctx, dayKey: friday, kind: .skip, promptID: "skip.block",
                                            question: "Take out the trash didn't happen.", subject: subject,
                                            answer: "", outcome: .misfit, source: .model, language: .zhHans,
                                            askedAt: Fixtures.date(friday, hour: 21),
                                            answeredAt: Fixtures.date(friday, hour: 22))
        #expect(row.subjectKind == .routine)
        #expect(row.subjectID == subject.id)
        #expect(row.subjectText == "Take out the trash")
        #expect(row.outcomeRaw == "misfit")
        #expect(row.sourceRaw == "model")
        #expect(row.languageRaw == "zh-Hans")
        #expect(row.kindRaw == "skip")
    }

    // MARK: export and import

    private func sourceWithJournal() throws -> (ModelContext, JournalSubject) {
        let ctx = try Fixtures.context()
        let subject = JournalSubject(kind: .quest, id: UUID(), text: "Take a photo of the sky")
        try turn(ctx, friday, .opening, answer: "Quiet day, I liked the walk home.").writingSeconds = 754
        try turn(ctx, friday, .choice, answer: "The one with the crane in it.", subject: subject)
        try turn(ctx, friday, .closing, answer: "", outcome: .skipped)
        try ctx.save()
        return (ctx, subject)
    }

    @Test func theExportCarriesTheJournalAndItRoundTrips() throws {
        let (ctx, subject) = try sourceWithJournal()
        let snapshot = try JSONExport.snapshot(ctx, now: Fixtures.date(friday))
        let turns = try #require(snapshot.journal?.turns)
        #expect(turns.map(\.index) == [0, 1, 2])
        #expect(turns.map(\.writingSeconds) == [754, 0, 0])
        #expect(turns[1].kind == "choice")
        #expect(turns[1].subjectKind == "quest")
        #expect(turns[1].subjectID == subject.id)
        #expect(turns[1].subjectText == "Take a photo of the sky")
        #expect(turns[1].answer == "The one with the crane in it.")
        #expect(turns[2].outcome == "skipped")

        let decoded = try JSONExport.decode(try JSONExport.data(ctx, now: Fixtures.date(friday)))
        #expect(decoded.journal == snapshot.journal)
    }

    @Test func restoringPutsTheTurnsBackAndReplacesWhatWasThere() throws {
        let (source, subject) = try sourceWithJournal()
        let target = try Fixtures.context()
        try turn(target, "2026-09-01", .opening, answer: "written after the backup was taken")
        try target.save()

        let plan = try JSONImport.plan(try JSONExport.data(source), against: target)
        #expect(plan.summary.journalTurns == 3)
        try JSONImport.apply(plan, to: target)

        let rows = try target.fetch(FetchDescriptor<JournalTurn>()).sorted { $0.index < $1.index }
        #expect(rows.map(\.answer) == ["Quiet day, I liked the walk home.", "The one with the crane in it.", ""])
        #expect(rows[1].subjectID == subject.id)
        #expect(rows[1].subjectKind == .quest)
        #expect(rows.allSatisfy { $0.dayKey == friday })
        #expect(rows[0].answeredAt == Fixtures.date(friday, hour: 22))
        #expect(rows.map(\.writingSeconds) == [754, 0, 0])
        #expect(try StoreAudit.issues(target).isEmpty)
    }

    /// A backup of a store with an empty journal is still a statement about the journal.
    @Test func anEmptyJournalBlockReplacesTheTurnsOnTheStore() throws {
        let source = try Fixtures.context()
        let target = try Fixtures.context()
        try turn(target, friday, .opening, answer: "will be replaced")
        try target.save()

        let data = try JSONExport.data(source)
        #expect(String(decoding: data, as: UTF8.self).contains(#""journal":{"turns":[]}"#))
        try JSONImport.apply(try JSONImport.plan(data, against: target), to: target)
        #expect(try target.fetchCount(FetchDescriptor<JournalTurn>()) == 0)
    }

    /// A schema 6 file has turns but no `writingSeconds` on them; they restore reading 0.
    @Test func aVersion6ExportStillImportsWithNoWritingTime() throws {
        let (source, _) = try sourceWithJournal()
        var json = try #require(try JSONSerialization.jsonObject(with: try JSONExport.data(source)) as? [String: Any])
        json["schemaVersion"] = 6
        json.removeValue(forKey: "journalEntries")
        var journal = try #require(json["journal"] as? [String: Any])
        var turns = try #require(journal["turns"] as? [[String: Any]])
        for i in turns.indices { turns[i].removeValue(forKey: "writingSeconds") }
        journal["turns"] = turns
        json["journal"] = journal
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(!String(decoding: data, as: UTF8.self).contains("writingSeconds"))

        let target = try Fixtures.context()
        try JSONImport.apply(try JSONImport.plan(data, against: target), to: target)
        let rows = try target.fetch(FetchDescriptor<JournalTurn>()).sorted { $0.index < $1.index }
        #expect(rows.map(\.answer) == ["Quiet day, I liked the walk home.", "The one with the crane in it.", ""])
        #expect(rows.map(\.writingSeconds) == [0, 0, 0])
    }

    /// A schema 5 file has no journal block. It restores, and the turns written since stay.
    @Test func aVersion5ExportStillImportsAndLeavesTheJournalAlone() throws {
        let source = try Fixtures.context()
        var json = try #require(try JSONSerialization.jsonObject(with: try JSONExport.data(source)) as? [String: Any])
        json["schemaVersion"] = 5
        json.removeValue(forKey: "journal")
        json.removeValue(forKey: "journalEntries")
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(!String(decoding: data, as: UTF8.self).contains("journal"))

        let target = try Fixtures.context()
        try turn(target, friday, .opening, answer: "mine")
        try target.save()

        let plan = try JSONImport.plan(data, against: target)
        #expect(plan.summary.journalTurns == 0)
        try JSONImport.apply(plan, to: target)
        #expect(try target.fetch(FetchDescriptor<JournalTurn>()).map(\.answer) == ["mine"])
    }

    @Test func theAuditCountsTurnsNothingCanReadBack() throws {
        let ctx = try Fixtures.context()
        let row = try turn(ctx, friday, .opening, answer: "x")
        row.kindRaw = "essay"
        row.subjectKindRaw = "dragon"
        let bad = try turn(ctx, "2026-09-19", .closing, answer: "y")
        bad.dayKey = "yesterday"
        bad.languageRaw = "klingon"
        let issues = try StoreAudit.issues(ctx).map(\.description)
        #expect(issues == ["JournalTurn.dayKey = 'yesterday' ×1",
                           "JournalTurn.kindRaw = 'essay' ×1",
                           "JournalTurn.languageRaw = 'klingon' ×1",
                           "JournalTurn.subjectKindRaw = 'dragon' ×1"])
    }

    // MARK: the debug rewind

    @Test func resettingADayLeavesWhatTheUserWroteAboutIt() throws {
        let ctx = try Fixtures.context()
        Fixtures.stockLibrary(ctx)
        var rng = SeededRNG(seed: 4)
        let now = Fixtures.date(friday)
        try DayService.ensureToday(ctx, now: now, in: tz, rng: &rng)
        let quest = try #require(try DayService.quests(on: friday, in: ctx).first)
        try turn(ctx, friday, .good, answer: "That one was the best part.",
                 subject: JournalSubject(kind: .quest, id: quest.id, text: quest.textSnapshot))
        try ctx.save()

        try DayReset.reset(ctx, dayKey: friday, now: now, in: tz, rng: &rng)

        let rows = try JournalService.turns(on: friday, in: ctx)
        #expect(rows.map(\.answer) == ["That one was the best part."])
        #expect(rows.first?.subjectText == quest.textSnapshot)
    }
}

// MARK: editing an answer

struct JournalEditTests {
    private let friday = "2026-09-18"

    private func answered(_ ctx: ModelContext, kind: JournalPromptKind = .opening, answer: String = "first words",
                          outcome: JournalOutcome = .answered) throws -> JournalTurn {
        try JournalService.record(ctx, dayKey: friday, kind: kind, promptID: "open.keep", question: "What stayed with you?",
                                  subject: JournalSubject(kind: .quest, id: UUID(), text: "A walk"),
                                  answer: answer, outcome: outcome, source: .model, language: .zhHans,
                                  askedAt: Fixtures.date(friday, hour: 21), answeredAt: Fixtures.date(friday, hour: 22))
    }

    @Test func anEditReplacesTheWordsAndTrimsThem() throws {
        let ctx = try Fixtures.context()
        let turn = try answered(ctx)
        try JournalService.edit(turn, answer: "  second words\n\n")
        #expect(turn.answer == "second words")
    }

    @Test func anEditChangesNothingButTheAnswer() throws {
        let ctx = try Fixtures.context()
        _ = try answered(ctx, kind: .opening)
        let turn = try answered(ctx, kind: .good)
        let id = turn.id, subjectID = turn.subjectID
        try JournalService.edit(turn, answer: "changed")
        #expect(turn.id == id)
        #expect(turn.index == 1)
        #expect(turn.dayKey == friday)
        #expect(turn.kind == .good)
        #expect(turn.promptID == "open.keep")
        #expect(turn.questionText == "What stayed with you?")
        #expect(turn.subjectID == subjectID)
        #expect(turn.subjectText == "A walk")
        #expect(turn.outcome == .answered)
        #expect(turn.source == .model)
        #expect(turn.language == .zhHans)
        #expect(turn.askedAt == Fixtures.date(friday, hour: 21))
        #expect(turn.answeredAt == Fixtures.date(friday, hour: 22))
    }

    @Test func aBlankResultIsRefusedAndTheAnswerStays() throws {
        let ctx = try Fixtures.context()
        let turn = try answered(ctx)
        #expect(throws: JournalEditError.empty) { try JournalService.edit(turn, answer: "") }
        #expect(throws: JournalEditError.empty) { try JournalService.edit(turn, answer: " \n\t ") }
        #expect(turn.answer == "first words")
    }

    @Test func skippedMisfitAndSafetyTurnsAreNotEditable() throws {
        let ctx = try Fixtures.context()
        let skipped = try answered(ctx, answer: "", outcome: .skipped)
        let misfit = try answered(ctx, answer: "left over", outcome: .misfit)
        let safety = try answered(ctx, kind: .safety, answer: "ok")
        for turn in [skipped, misfit, safety] {
            #expect(throws: JournalEditError.notEditable) { try JournalService.edit(turn, answer: "new") }
        }
        #expect([skipped.answer, misfit.answer, safety.answer] == ["", "left over", "ok"])
    }

    @Test func theSameTextIsANoOpThatDoesNotThrow() throws {
        let ctx = try Fixtures.context()
        let turn = try answered(ctx)
        try JournalService.edit(turn, answer: "first words")
        try JournalService.edit(turn, answer: " first words ")
        #expect(turn.answer == "first words")
    }

    @Test func anEditedAnswerSurvivesAnExportAndARestore() throws {
        let source = try Fixtures.context()
        let first = try answered(source, answer: "before")
        let second = try answered(source, kind: .closing, answer: "also before")
        try JournalService.edit(first, answer: "after the edit")
        try source.save()

        let target = try Fixtures.context()
        try JSONImport.apply(try JSONImport.plan(try JSONExport.data(source), against: target), to: target)

        let rows = try JournalService.turns(on: friday, in: target)
        #expect(rows.map(\.answer) == ["after the edit", "also before"])
        #expect(rows[0].id == first.id && rows[1].id == second.id)
        #expect(rows[0].answeredAt == Fixtures.date(friday, hour: 22))
        #expect(try StoreAudit.issues(target).isEmpty)
    }
}

// MARK: free writing added later

struct JournalFreeWritingTests {
    typealias F = JournalFixtures
    private let friday = "2026-09-18"
    private let now = Fixtures.date("2026-09-18", hour: 23)

    private func closedDay(_ ctx: ModelContext) throws {
        let at = Fixtures.date(friday, hour: 21)
        try JournalService.record(ctx, dayKey: friday, kind: .opening, promptID: "open.keep", question: "Q0",
                                  answer: "A0", language: .en, askedAt: at, answeredAt: at)
        try JournalService.record(ctx, dayKey: friday, kind: .closing, promptID: "close.carry", question: "Q1",
                                  answer: "A1", language: .en, askedAt: at, answeredAt: at)
    }

    @Test func itIsAClosingTurnWithNoQuestionAtTheNextIndex() throws {
        let ctx = try Fixtures.context()
        try closedDay(ctx)
        let turn = try JournalService.appendFreeWriting("  one more thing\n", on: friday, language: .zhHans,
                                                        in: ctx, now: now)
        try ctx.save()
        #expect(turn.index == 2)
        #expect(turn.kind == .closing)
        #expect(turn.questionText == "")
        #expect(turn.promptID == "")
        #expect(turn.source == .template)
        #expect(turn.outcome == .answered)
        #expect(turn.language == .zhHans)
        #expect(turn.answer == "one more thing")
        #expect(turn.askedAt == now && turn.answeredAt == now)
        #expect(try JournalService.turns(on: friday, in: ctx).map(\.index) == [0, 1, 2])
    }

    @Test func aDayWithNoTurnsGetsIndexZero() throws {
        let ctx = try Fixtures.context()
        let turn = try JournalService.appendFreeWriting("just this", on: friday, language: .en, in: ctx, now: now)
        #expect(turn.index == 0)
    }

    @Test func blankTextIsRefusedAndNothingIsStored() throws {
        let ctx = try Fixtures.context()
        #expect(throws: JournalEditError.empty) {
            try JournalService.appendFreeWriting(" \n ", on: friday, language: .en, in: ctx, now: now)
        }
        #expect(try ctx.fetchCount(FetchDescriptor<JournalTurn>()) == 0)
    }

    @Test func twoClosingTurnsStillMeanTheDayIsDoneAndBothAreComposedInOrder() throws {
        let ctx = try Fixtures.context()
        try closedDay(ctx)
        try JournalService.appendFreeWriting("more", on: friday, language: .en, in: ctx, now: now)
        try ctx.save()
        let turns = try JournalService.turns(on: friday, in: ctx)
        #expect(turns.filter { $0.kind == .closing }.count == 2)
        #expect(JournalPlanner.next(signals: F.signals(), habits: .none, today: turns, language: .en) == .done)
        #expect(JournalComposer.text(turns: turns, language: .en)
                == "Journal 2026-09-18\n\nQ0\nA0\n\nQ1\nA1\n\nmore")
    }
}

// MARK: the autosaved free-writing page

struct JournalSaveFreeWritingTests {
    private let friday = "2026-09-18"
    private let t1 = Fixtures.date("2026-09-18", hour: 21)
    private let t2 = Fixtures.date("2026-09-18", hour: 22)

    private func save(_ ctx: ModelContext, _ text: String, seconds: Int = 0, at now: Date? = nil,
                      language: JournalLanguage = .en) throws -> JournalTurn? {
        try JournalService.saveFreeWriting(text, writingSeconds: seconds, on: friday, language: language,
                                           in: ctx, now: now ?? t1)
    }

    @Test func theFirstSaveCreatesTheClosingTurnWithNoQuestionAtTheNextIndex() throws {
        let ctx = try Fixtures.context()
        try JournalService.record(ctx, dayKey: friday, kind: .opening, promptID: "open.keep", question: "Q0",
                                  answer: "A0", language: .en, askedAt: t1, answeredAt: t1)
        let turn = try #require(try save(ctx, "  Grateful for rain.\n\nAnd tea.  \n", seconds: 42, language: .zhHans))
        #expect(turn.index == 1)
        #expect(turn.kind == .closing)
        #expect(turn.questionText == "" && turn.promptID == "")
        #expect(turn.outcome == .answered)
        #expect(turn.language == .zhHans)
        #expect(turn.answer == "Grateful for rain.\n\nAnd tea.")
        #expect(turn.writingSeconds == 42)
        #expect(turn.askedAt == t1 && turn.answeredAt == t1)
    }

    @Test func aLaterSaveRewritesTheSameRowKeepingInternalWhitespace() throws {
        let ctx = try Fixtures.context()
        let first = try #require(try save(ctx, "one", seconds: 5, at: t1))
        let second = try #require(try save(ctx, "one\n\n  two  three \n", seconds: 90, at: t2))
        #expect(first === second)
        #expect(second.answer == "one\n\n  two  three")
        #expect(second.writingSeconds == 90)
        #expect(second.askedAt == t1)
        #expect(second.answeredAt == t2)
        #expect(try JournalService.turns(on: friday, in: ctx).count == 1)
    }

    @Test func blankTextOnADayWithoutOneStoresNothing() throws {
        let ctx = try Fixtures.context()
        #expect(try save(ctx, " \n\t ") == nil)
        #expect(try ctx.fetchCount(FetchDescriptor<JournalTurn>()) == 0)
    }

    @Test func clearingThePageKeepsTheRowWithAnEmptyAnswerAndTheTimeOfTheSave() throws {
        let ctx = try Fixtures.context()
        _ = try save(ctx, "something", seconds: 30, at: t1)
        let turn = try #require(try save(ctx, "  \n", seconds: 31, at: t2))
        #expect(turn.answer == "")
        #expect(turn.writingSeconds == 31)
        #expect(turn.answeredAt == t2)
        #expect(JournalComposer.text(turns: try JournalService.turns(on: friday, in: ctx), language: .en) == "")
    }

    @Test func aClearedPageCanBeWrittenAgainInTheSameRow() throws {
        let ctx = try Fixtures.context()
        let cleared = try #require(try save(ctx, "x", at: t1))
        _ = try save(ctx, "", at: t2)
        let again = try #require(try save(ctx, "back again", seconds: 8, at: t2))
        #expect(again === cleared)
        #expect(again.answer == "back again")
    }

    @Test func itFindsTheFreeWritingTurnAmongQuestionedOnesAndLeavesThemAlone() throws {
        let ctx = try Fixtures.context()
        let q = try JournalService.record(ctx, dayKey: friday, kind: .closing, promptID: "close.carry", question: "Q1",
                                          answer: "A1", language: .en, askedAt: t1, answeredAt: t1)
        let free = try #require(try save(ctx, "mine", at: t1))
        #expect(free !== q)
        _ = try save(ctx, "mine, longer", at: t2)
        #expect(q.answer == "A1" && q.writingSeconds == 0)
        #expect(try JournalService.turns(on: friday, in: ctx).map(\.answer) == ["A1", "mine, longer"])
    }

    @Test func withTwoFreeWritingTurnsTheLastOneIsTheOneRewritten() throws {
        let ctx = try Fixtures.context()
        let a = try JournalService.appendFreeWriting("early", on: friday, language: .en, in: ctx, now: t1)
        let b = try JournalService.appendFreeWriting("late", on: friday, language: .en, in: ctx, now: t1)
        _ = try save(ctx, "rewritten", at: t2)
        #expect(a.answer == "early")
        #expect(b.answer == "rewritten")
    }

    @Test func aNegativeTotalIsStoredAsZero() throws {
        let ctx = try Fixtures.context()
        #expect(try #require(try save(ctx, "x", seconds: -5)).writingSeconds == 0)
    }

    @Test func appendFreeWritingStillAppendsAClosingTurnWithNoWritingTime() throws {
        let ctx = try Fixtures.context()
        let turn = try JournalService.appendFreeWriting("more", on: friday, language: .en, in: ctx, now: t1)
        #expect(turn.isFreeWriting)
        #expect(turn.writingSeconds == 0)
    }
}

// MARK: a blank free-writing turn is not written and does not close the day

struct JournalBlankFreeWritingTests {
    typealias F = JournalFixtures

    @Test func aBlankFreeWritingTurnDoesNotCloseTheDay() {
        #expect(!JournalProgress.isClosed([F.freeWriting("")]))
        #expect(!JournalProgress.isClosed([F.turn(.opening, "ok then", index: 0), F.freeWriting("  \n", index: 1)]))
    }

    @Test func aWrittenFreeWritingTurnStillClosesIt() {
        #expect(JournalProgress.isClosed([F.freeWriting("hello")]))
    }

    @Test func aSkippedQuestionedClosingTurnStillCloses() {
        #expect(JournalProgress.isClosed([F.turn(.closing, "", index: 0, outcome: .skipped)]))
        let blankButQuestioned = F.turn(.closing, "", index: 0)
        #expect(JournalProgress.isClosed([blankButQuestioned]))
    }

    @Test func historyAddsNothingFromAClearedPageToTheDaysTextOrWords() throws {
        let turns = [F.turn(.opening, "ok then", index: 0), F.freeWriting("", index: 1)]
        let day = try #require(JournalHistory.days(from: turns, language: .en).first)
        #expect(day.text == "Journal 2026-09-18\n\nquestion\nok then")
        #expect(day.wordCount == 2)
    }

    @Test func historyLeavesOutADayWhosePageWasCleared() {
        #expect(JournalHistory.days(from: [F.freeWriting("")], language: .en).isEmpty)
    }

    @Test func theNextQuestionIsAskedAsIfTheBlankTurnWerenotThere() {
        let blank = F.freeWriting("", index: 0)
        let step = JournalPlanner.next(signals: F.signals(), habits: .none, today: [blank], language: .en)
        guard case .ask(let q) = step else { Issue.record("expected the opening, got \(step)"); return }
        #expect(q.kind == .opening)
    }

    @Test func aFollowUpIsStillOfferedWhenTheBlankTurnIsTheLastRow() {
        let opening = F.turn(.opening, "That one went better than I expected.", index: 0)
        let blank = F.freeWriting("", index: 1)
        let step = JournalPlanner.next(signals: F.signals(), habits: .none, today: [opening, blank], language: .en)
        guard case .followUp = step else { Issue.record("expected a follow-up, got \(step)"); return }
    }

    @Test func aWrittenFreeWritingTurnStillEndsTheDayForThePlanner() {
        let step = JournalPlanner.next(signals: F.signals(), habits: .none, today: [F.freeWriting("text")], language: .en)
        #expect(step == .done)
    }

    @Test func aClearedPageIsNotAnAnsweredClosingQuestionInTheHabits() {
        let turns = [F.turn(.closing, "", index: 0, on: "2026-09-17", outcome: .skipped),
                     F.freeWriting("", index: 1, on: "2026-09-17")]
        let habits = JournalHabits.derive(from: turns, asOf: "2026-09-18", timeZone: Fixtures.tokyo)
        // One skip and no answers: (0 + 1) / (0 + 1 + 1) = 0.5. A counted blank would read 2/3.
        #expect(habits.weight(for: .closing) == 0.5)
    }
}
