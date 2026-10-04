import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

struct JournalPlannerTests {
    typealias F = JournalFixtures

    /// Plays a day to its end. Every question gets `answer(question)`, and the log names what was
    /// asked: the pool row, `followUp` for an offered follow-up, `safety` for the safety line.
    private func play(_ signals: JournalSignals,
                      habits: JournalHabits = .none,
                      language: JournalLanguage = .en,
                      answer: (JournalQuestion?) -> String = { _ in "fine" }) -> [String] {
        var turns: [JournalTurn] = []
        var log: [String] = []
        for index in 0..<20 {
            switch JournalPlanner.next(signals: signals, habits: habits, today: turns, language: language) {
            case .ask(let q):
                log.append(q.promptID)
                turns.append(F.turn(q.kind, answer(q), index: index, on: signals.dayKey))
            case .followUp(let request):
                log.append("followUp")
                turns.append(F.turn(.followUp, answer(request.fallback), index: index, on: signals.dayKey))
            case .safety:
                log.append("safety")
                turns.append(F.turn(.safety, "", index: index, on: signals.dayKey))
            case .done:
                return log
            }
        }
        Issue.record("the day never ended: \(log)")
        return log
    }

    private let longAnswer = "That one went better than I expected."

    // MARK: the worked days

    @Test func anOrdinaryDayIsTheOpeningAndTheClosing() {
        let quests = [F.quest("Walk"), F.quest("Read"), F.quest("Stretch")]
        let signals = F.signals(tier: .normal, quests: quests)
        #expect(play(signals) == ["open.keep", "close.carry"])
    }

    @Test func aHeavyDayAddsOneHeavyQuestionDrawnFromTheEligibleSet() {
        let quests = ["Walk", "Read", "Stretch", "Tidy"].map { F.quest($0) }
        let ratings = zip(quests, [-2, -1, -2, -1]).map { F.rating(of: $0.id, $1) }
        let signals = F.signals(tier: .low, quests: quests, ratings: ratings)
        #expect(signals.averageRating == -1.5)
        // djb2("2026-09-18") % 4 == 3 picks the last of the four rows, in pool order.
        #expect(play(signals) == ["open.keep", "heavy.body", "close.carry"])
        #expect(play(signals) == play(signals))
    }

    @Test func aPhotoQuestAndAnAutoSkippedRoutineAreAskedSkipFirst() {
        let photo = F.quest("Take a photo of the sky")
        let missed = F.occurrence("Take out the trash", due: "2026-09-15", skipped: true)
        let signals = F.signals(quests: [photo], occurrences: [missed],
                                ratings: [F.rating(of: photo.id, 2)],
                                ledger: [F.skipEntry(for: missed, on: F.day)])
        // The photo is rated +2 but is asked about as a choice, not twice, so skip then choice.
        #expect(play(signals) == ["open.keep", "skip.small", "choice.photo", "close.carry"])
    }

    // MARK: eligibility

    /// The rows each kind can draw, found by playing a month: the draw varies by day, the set it
    /// varies over is what the rules allow.
    private func drawnOverAMonth(_ build: (String) -> JournalSignals, kind: JournalPromptKind) -> Set<String> {
        var seen = Set<String>()
        for day in 1...30 {
            let key = String(format: "2026-09-%02d", day)
            for id in play(build(key)) where JournalPool.prompt(id: id)?.kind == kind { seen.insert(id) }
        }
        return seen
    }

    private func quests(_ n: Int, on day: String, rated rating: Int?) -> ([DailyQuest], [QuestRating]) {
        let rows = (0..<n).map { F.quest("Quest \($0)", on: day) }
        return (rows, rating.map { r in rows.map { F.rating(of: $0.id, r, on: day) } } ?? [])
    }

    @Test func eachHeavyQuestionNeedsItsOwnCondition() {
        let heavy = JournalPromptKind.heavy
        // Low energy alone: only the body question.
        #expect(drawnOverAMonth({ F.signals(tier: .low, on: $0) }, kind: heavy) == ["heavy.body"])
        // Three done, average -0.67 on a normal day: only "you got a lot done".
        #expect(drawnOverAMonth({ day in
            let (q, _) = quests(3, on: day, rated: nil)
            let r = zip(q, [-1, -1, 0]).map { F.rating(of: $0.id, $1, on: day) }
            return F.signals(quests: q, ratings: r, on: day)
        }, kind: heavy) == ["heavy.done"])
        // Average -0.5 over two done: not enough items for "a lot done", not low enough for the rest.
        #expect(drawnOverAMonth({ day in
            let (q, _) = quests(2, on: day, rated: nil)
            let r = zip(q, [-1, 0]).map { F.rating(of: $0.id, $1, on: day) }
            return F.signals(quests: q, ratings: r, on: day)
        }, kind: heavy) == [])
        // Average -1 with two done: the weight and the friend questions, not "a lot done".
        #expect(drawnOverAMonth({ day in
            let (q, r) = quests(2, on: day, rated: -1)
            return F.signals(quests: q, ratings: r, on: day)
        }, kind: heavy) == ["heavy.weight", "heavy.friend"])
        // All four conditions at once.
        #expect(drawnOverAMonth({ day in
            let (q, r) = quests(4, on: day, rated: -2)
            return F.signals(tier: .veryLow, quests: q, ratings: r, on: day)
        }, kind: heavy) == ["heavy.done", "heavy.weight", "heavy.friend", "heavy.body"])
    }

    @Test func aGoodQuestionNeedsAnItemRatedOneOrMore() {
        let none = { (day: String) -> JournalSignals in
            let (q, r) = quests(2, on: day, rated: 0)
            return F.signals(quests: q, ratings: r, on: day)
        }
        let some = { (day: String) -> JournalSignals in
            let (q, r) = quests(2, on: day, rated: 1)
            return F.signals(quests: q, ratings: r, on: day)
        }
        #expect(drawnOverAMonth(none, kind: .good) == [])
        #expect(drawnOverAMonth(some, kind: .good) == ["good.moment", "good.repeat", "good.who"])
    }

    @Test func aGoodQuestionNamesTheBestRatedItem() {
        let a = F.quest("Walk"), b = F.quest("Read a chapter")
        let signals = F.signals(quests: [a, b], ratings: [F.rating(of: a.id, 1), F.rating(of: b.id, 2)])
        guard case .ask(let q) = JournalPlanner.next(signals: signals, habits: .none,
                                                     today: [F.turn(.opening, index: 0)], language: .en)
        else { Issue.record("expected a question"); return }
        #expect(q.kind == .good)
        #expect(q.subject?.text == "Read a chapter")
        #expect(q.subject?.id == b.id)
        // djb2("2026-09-18") % 3 == 2: "Who or what made it better?" names nothing, the subject still travels.
        #expect(q.promptID == "good.who")
    }

    @Test func aChoiceQuestionUsesTheDrawnValueOrARowThatNeedsNone() {
        func question(_ text: String, variant: String?, language: JournalLanguage = .en) -> JournalQuestion? {
            let q = F.quest(text, variant: variant)
            let signals = F.signals(quests: [q])
            guard case .ask(let asked) = JournalPlanner.next(signals: signals, habits: .none,
                                                             today: [F.turn(.opening, index: 0)], language: language)
            else { return nil }
            return asked
        }
        #expect(question("Photograph a set of things in a given color", variant: "Red")?.text
                == "You picked Red. What made it the one?")
        #expect(question("Photograph a set of things in a given color", variant: "Red", language: .zhHans)?.text
                == "你选了Red。是什么让它成为那个？")
        #expect(question("Take a photo of the sky", variant: nil)?.promptID == "choice.photo")
        #expect(question("Take a photo of the sky", variant: "")?.promptID == "choice.photo")
        #expect(question("Notice three green things", variant: nil)?.promptID == "choice.notice")
    }

    @Test func aSkipQuestionIsNeverAskedAboutSomethingStillOpenToday() {
        let dueToday = F.occurrence("Due today", due: F.day)
        let signals = F.signals(occurrences: [dueToday])
        #expect(play(signals) == ["open.keep", "close.carry"])

        let overdue = F.occurrence("Overdue", due: "2026-09-17")
        #expect(play(F.signals(occurrences: [overdue])) == ["open.keep", "skip.small", "close.carry"])
    }

    @Test func aSkipQuestionNamesTheRoutineAndNeverBlames() {
        for day in 1...30 {
            let key = String(format: "2026-09-%02d", day)
            let overdue = F.occurrence("Take out the trash", due: "2026-09-\(String(format: "%02d", day - 1))")
            guard day > 1, case .ask(let q) = JournalPlanner.next(signals: F.signals(occurrences: [overdue], on: key),
                                                                 habits: .none,
                                                                 today: [F.turn(.opening, index: 0, on: key)],
                                                                 language: .en)
            else { continue }
            #expect(q.kind == .skip)
            #expect(["skip.block", "skip.exception", "skip.small"].contains(q.promptID))
            #expect(q.subject?.text == "Take out the trash")
            if q.promptID == "skip.block" { #expect(q.text == "Take out the trash didn't happen. What got in the way?") }
        }
    }

    // MARK: ranking

    @Test func atMostTwoSupplementalQuestionsAreAskedAndTheHighestScoresWin() {
        // Heavy (4), skip (3), choice (2) are all eligible: heavy and skip are asked.
        let photo = F.quest("Take a photo of the sky")
        let missed = F.occurrence("Trash", due: "2026-09-15", skipped: true)
        let signals = F.signals(tier: .low, quests: [photo], occurrences: [missed],
                                ledger: [F.skipEntry(for: missed, on: F.day)])
        #expect(play(signals) == ["open.keep", "heavy.body", "skip.small", "close.carry"])
    }

    @Test func aGoodQuestionRatedTwoOutranksAChoiceQuestion() {
        let walk = F.quest("Walk"), photo = F.quest("Take a photo of the sky")
        let signals = F.signals(quests: [walk, photo], ratings: [F.rating(of: walk.id, 2)])
        #expect(play(signals) == ["open.keep", "good.who", "choice.photo", "close.carry"])
        // Rated 1 it scores 2, ties with the choice, and the earlier kind in the table goes first: still good.
        let one = F.signals(quests: [walk, photo], ratings: [F.rating(of: walk.id, 1)])
        #expect(play(one) == ["open.keep", "good.who", "choice.photo", "close.carry"])
    }

    @Test func habitsReorderTheRankingAndATieGoesToTheEarlierKind() {
        let walk = F.quest("Walk"), photo = F.quest("Take a photo of the sky")
        let missed = F.occurrence("Trash", due: "2026-09-15", skipped: true)
        let signals = F.signals(tier: .low, quests: [walk, photo], occurrences: [missed],
                                ratings: [F.rating(of: walk.id, 1)], ledger: [F.skipEntry(for: missed, on: F.day)])
        // No history: heavy 4, skip 3, good 2, choice 2.
        #expect(play(signals) == ["open.keep", "heavy.body", "skip.small", "close.carry"])
        // Heavy asked and then called a misfit again and again drops to the floor: 4 x 0.25 = 1.
        let wornOut = JournalHabits(medianAnswerLength: nil, typicalHour: nil, usesEmoji: false,
                                    weights: [.heavy: 0.25, .skip: 0.5])
        // skip 1.5, good 2, choice 2, heavy 1: good then choice.
        #expect(play(signals, habits: wornOut) == ["open.keep", "good.who", "choice.photo", "close.carry"])
        // heavy 2, skip 3 x 0.5 = 1.5, good 2, choice 2: three-way tie at 2 goes heavy, good.
        let tied = JournalHabits(medianAnswerLength: nil, typicalHour: nil, usesEmoji: false,
                                 weights: [.heavy: 0.5, .skip: 0.5])
        #expect(play(signals, habits: tied) == ["open.keep", "heavy.body", "good.who", "close.carry"])
    }

    // MARK: follow-ups

    @Test func aLongEnoughAnswerGetsAFollowUpAndAShortOneDoesNot() {
        let signals = F.signals()
        let answered = F.turn(.opening, longAnswer, index: 0)
        guard case .followUp(let request) = JournalPlanner.next(signals: signals, habits: .none,
                                                                today: [answered], language: .en)
        else { Issue.record("expected a follow-up"); return }
        #expect(request.answer == longAnswer)
        #expect(request.question == "question")
        #expect(request.fallback.promptID == "follow.stand")
        #expect(request.fallback.text == "You said \"That one went better than I expected\". What stands out to you about that?")

        func offersFollowUp(_ answer: String) -> Bool {
            if case .followUp = JournalPlanner.next(signals: signals, habits: .none,
                                                    today: [F.turn(.opening, answer)], language: .en) { return true }
            return false
        }
        #expect(offersFollowUp("exactly fifteen"))      // 15 characters
        #expect(!offersFollowUp("exactly fiftee"))      // 14
        #expect(!offersFollowUp("   short   "))
    }

    @Test func aFollowUpCarriesTheSubjectOfTheTurnItFollows() {
        let walk = F.quest("Walk"), photo = F.quest("Take a photo of the sky")
        let signals = F.signals(quests: [walk, photo], ratings: [F.rating(of: walk.id, 2)])
        let good = F.turn(.good, longAnswer, index: 1)
        good.subjectKind = .quest; good.subjectID = walk.id; good.subjectText = "Walk"
        guard case .followUp(let request) = JournalPlanner.next(signals: signals, habits: .none,
                                                                today: [F.turn(.opening, index: 0), good], language: .en)
        else { Issue.record("expected a follow-up"); return }
        #expect(request.subject == JournalSubject(kind: .quest, id: walk.id, text: "Walk"))
    }

    @Test func atMostOneFollowUpPerTurnAndTwoPerDay() {
        let photo = F.quest("Take a photo of the sky")
        let missed = F.occurrence("Trash", due: "2026-09-15", skipped: true)
        let signals = F.signals(quests: [photo], occurrences: [missed], ledger: [F.skipEntry(for: missed, on: F.day)])
        // Opening, its follow-up, skip, its follow-up; the third answer would qualify but the day's two are spent.
        #expect(play(signals, answer: { _ in self.longAnswer })
                == ["open.keep", "followUp", "skip.small", "followUp", "choice.photo", "close.carry"])
    }

    @Test func aSkippedOrMisfitTurnCountsAsAskedAndGetsNoFollowUp() {
        let signals = F.signals(tier: .low)
        let skippedOpening = F.turn(.opening, "", index: 0, outcome: .skipped)
        guard case .ask(let q) = JournalPlanner.next(signals: signals, habits: .none, today: [skippedOpening], language: .en)
        else { Issue.record("expected a question"); return }
        #expect(q.kind == .heavy)
        let misfitHeavy = F.turn(.heavy, longAnswer, index: 1, outcome: .misfit)
        guard case .ask(let closing) = JournalPlanner.next(signals: signals, habits: .none,
                                                           today: [skippedOpening, misfitHeavy], language: .en)
        else { Issue.record("expected a question"); return }
        #expect(closing.kind == .closing)
    }

    @Test func theClosingEndsTheDayWhateverIsLeft() {
        let signals = F.signals(tier: .low)
        let turns = [F.turn(.opening, index: 0), F.turn(.closing, longAnswer, index: 1)]
        #expect(JournalPlanner.next(signals: signals, habits: .none, today: turns, language: .en) == .done)
        // Free writing is a closing turn with no pool row.
        #expect(JournalPlanner.next(signals: signals, habits: .none, today: [F.turn(.closing, longAnswer)], language: .en) == .done)
    }

    // MARK: resuming

    @Test func askingAgainGivesTheSameStepAndAnyPrefixResumes() {
        let walk = F.quest("Walk"), photo = F.quest("Take a photo of the sky")
        let signals = F.signals(tier: .low, quests: [walk, photo], ratings: [F.rating(of: walk.id, 2)])
        var turns: [JournalTurn] = []
        var firstRun: [JournalStep] = []
        for index in 0..<10 {
            let step = JournalPlanner.next(signals: signals, habits: .none, today: turns, language: .zhHans)
            // Idempotent: nothing was recorded, so nothing may change.
            #expect(step == JournalPlanner.next(signals: signals, habits: .none, today: turns, language: .zhHans))
            // The same turns in another order are the same day.
            #expect(step == JournalPlanner.next(signals: signals, habits: .none, today: turns.reversed(), language: .zhHans))
            firstRun.append(step)
            guard case .ask(let q) = step else { break }
            turns.append(F.turn(q.kind, "短", index: index))
        }
        #expect(firstRun.last == .done)
    }

    @Test func theSameDayAlwaysDrawsTheSameQuestion() {
        #expect(JournalPlanner.stableHash("a") == 177670)
        #expect(JournalPlanner.stableHash("") == 5381)
        #expect(JournalPlanner.stableHash("2026-09-18") == 8243816804023308443)
        let signals = F.signals()
        let draws = (0..<5).map { _ in JournalPlanner.next(signals: signals, habits: .none, today: [], language: .en) }
        #expect(Set(draws.map { "\($0)" }).count == 1)
        guard case .ask(let q) = draws[0] else { Issue.record("expected a question"); return }
        #expect(q.promptID == "open.keep")   // 8243816804023308443 % 3 == 2
    }

    @Test func differentDaysDrawDifferentOpenings() {
        var ids = Set<String>()
        for day in 1...30 {
            let key = String(format: "2026-09-%02d", day)
            if case .ask(let q) = JournalPlanner.next(signals: F.signals(on: key), habits: .none, today: [], language: .en) {
                ids.insert(q.promptID)
            }
        }
        #expect(ids == ["open.scale", "open.feel", "open.keep"])
    }

    // MARK: safety

    @Test func aSafetyAnswerShowsTheLineOnceThenNoMoreFollowUpsAndStillClosesTheDay() {
        let signals = F.signals(tier: .low)
        let answers = ["I feel hopeless about all of it and it has been like this for weeks"]
        var turns = [F.turn(.opening, answers[0], index: 0)]
        #expect(JournalPlanner.next(signals: signals, habits: .none, today: turns, language: .en) == .safety)
        turns.append(F.turn(.safety, "", index: 1))
        // No follow-up although the answer is long; the day carries on.
        guard case .ask(let heavy) = JournalPlanner.next(signals: signals, habits: .none, today: turns, language: .en)
        else { Issue.record("expected a question"); return }
        #expect(heavy.kind == .heavy)
        turns.append(F.turn(.heavy, "something quite long about the body today", index: 2))
        guard case .ask(let closing) = JournalPlanner.next(signals: signals, habits: .none, today: turns, language: .en)
        else { Issue.record("expected the closing"); return }
        #expect(closing.kind == .closing)
        turns.append(F.turn(.closing, "ok", index: 3))
        #expect(JournalPlanner.next(signals: signals, habits: .none, today: turns, language: .en) == .done)
    }

    @Test func aSafetyAnswerInChineseOrInTheClosingIsCaughtToo() {
        let signals = F.signals()
        #expect(JournalPlanner.next(signals: signals, habits: .none,
                                    today: [F.turn(.opening, "真的不想活了", index: 0)], language: .zhHans) == .safety)
        let closing = [F.turn(.opening, index: 0), F.turn(.closing, "I just want to die", index: 1)]
        #expect(JournalPlanner.next(signals: signals, habits: .none, today: closing, language: .en) == .safety)
        // Once shown it is over.
        #expect(JournalPlanner.next(signals: signals, habits: .none, today: closing + [F.turn(.safety, index: 2)],
                                    language: .en) == .done)
    }

    @Test func aSkippedTurnCannotTriggerTheSafetyLine() {
        let skipped = F.turn(.opening, "I want to die", index: 0, outcome: .skipped)
        guard case .ask = JournalPlanner.next(signals: F.signals(), habits: .none, today: [skipped], language: .en)
        else { Issue.record("a skipped turn has no answer to read"); return }
    }
}
