import Foundation
import Testing
@testable import LifeRPGCore

/// The fallback row of a kind is the least recently used one, and the brief carries the examples
/// and avoid-list the model words a fresh question from. 2026-09-18 hashes (djb2) to 2 mod 3,
/// 1 mod 2 and 3 mod 4, which is where the literal picks below come from.
struct JournalRecencyTests {
    typealias F = JournalFixtures

    private func habits(_ used: [String: String] = [:], texts: [String] = []) -> JournalHabits {
        JournalHabits(medianAnswerLength: nil, typicalHour: nil, usesEmoji: false, weights: [:],
                      lastUsedDay: used, recentQuestionTexts: texts)
    }

    private func ask(_ signals: JournalSignals, _ habits: JournalHabits = .none, today: [JournalTurn] = [],
                     language: JournalLanguage = .en) -> JournalQuestion? {
        guard case .ask(let q) = JournalPlanner.next(signals: signals, habits: habits, today: today, language: language)
        else { return nil }
        return q
    }

    private func afterOpening(_ signals: JournalSignals, _ habits: JournalHabits = .none,
                              language: JournalLanguage = .en) -> JournalQuestion? {
        ask(signals, habits, today: [F.turn(.opening, "ok", index: 0)], language: language)
    }

    // MARK: the fallback draw

    @Test func withNoHistoryTheDrawIsTheDaysHashAsBefore() {
        #expect(ask(F.signals())?.promptID == "open.keep")      // 2 mod 3
    }

    @Test func theLeastRecentlyUsedRowIsDrawn() {
        let used = ["open.keep": "2026-09-17", "open.scale": "2026-09-10", "open.feel": "2026-09-05"]
        #expect(ask(F.signals(), habits(used))?.promptID == "open.feel")
    }

    @Test func aRowNeverUsedIsTheOldest() {
        // The hash alone would pick open.keep; it is the most recent here and open.feel was never asked.
        let used = ["open.keep": "2026-09-01", "open.scale": "2026-09-10"]
        #expect(ask(F.signals(), habits(used))?.promptID == "open.feel")
    }

    @Test func rowsThatTieBreakByTheHashOfTheDay() {
        // Only open.keep was asked yesterday; scale and feel tie as never used and 1 mod 2 takes the second.
        #expect(ask(F.signals(), habits(["open.keep": "2026-09-17"]))?.promptID == "open.feel")
        // All three asked the same day: the hash among all of them, 2 mod 3.
        let same = ["open.keep": "2026-09-01", "open.scale": "2026-09-01", "open.feel": "2026-09-01"]
        #expect(ask(F.signals(), habits(same))?.promptID == "open.keep")
    }

    @Test func theClosingAndEverySupplementalKindDrawTheLeastRecentlyUsed() {
        let yesterday = "2026-09-17"
        #expect(afterOpening(F.signals(), habits(["close.carry": yesterday]))?.promptID == "close.more")

        // Heavy: the body row is the only one eligible and is asked again, there is nothing else.
        #expect(afterOpening(F.signals(tier: .low), habits(["heavy.body": yesterday]))?.promptID == "heavy.body")

        // Weight and friend are eligible on an average of -1: the one used yesterday gives way.
        let quests = ["Walk", "Read"].map { F.quest($0) }
        let ratings = quests.map { F.rating(of: $0.id, -1) }
        let heavy = F.signals(quests: quests, ratings: ratings)
        #expect(afterOpening(heavy, habits(["heavy.weight": yesterday]))?.promptID == "heavy.friend")
        #expect(afterOpening(heavy, habits(["heavy.friend": yesterday]))?.promptID == "heavy.weight")

        // Skip: block and exception tie as never used, 1 mod 2 takes the exception.
        let missed = F.occurrence("Trash", due: "2026-09-15", skipped: true)
        let skip = F.signals(occurrences: [missed], ledger: [F.skipEntry(for: missed, on: F.day)])
        #expect(afterOpening(skip, habits(["skip.small": yesterday]))?.promptID == "skip.exception")
        #expect(afterOpening(skip, habits(["skip.small": yesterday, "skip.exception": "2026-09-16"]))?.promptID == "skip.block")

        // Good: three rows, moment never used, the others yesterday.
        let walk = F.quest("Walk")
        let good = F.signals(quests: [walk], ratings: [F.rating(of: walk.id, 2)])
        #expect(afterOpening(good, habits(["good.repeat": yesterday, "good.who": yesterday]))?.promptID == "good.moment")
    }

    @Test func aMonthOfOpeningsNeverRepeatsInAThreeDayWindow() {
        var turns: [JournalTurn] = []
        var drawn: [String] = []
        for day in 1...30 {
            let key = String(format: "2026-09-%02d", day)
            let h = JournalHabits.derive(from: turns, asOf: key, timeZone: Fixtures.tokyo)
            guard let q = ask(F.signals(on: key), h) else { Issue.record("no opening on \(key)"); return }
            drawn.append(q.promptID)
            let turn = F.turn(.opening, index: 0, on: key)
            turn.promptID = q.promptID
            turns.append(turn)
        }
        for start in 0...(drawn.count - 3) {
            #expect(Set(drawn[start..<start + 3]).count == 3, "\(drawn[start..<start + 3])")
        }
    }

    @Test func aModelWordedTurnStillUsesUpTheRowItWasWordedFrom() {
        let model = F.turn(.opening, index: 0, on: "2026-09-17")
        model.questionText = "What stayed with you this evening?"
        model.promptID = "open.keep"
        model.source = .model
        let h = JournalHabits.derive(from: [model], asOf: F.day, timeZone: Fixtures.tokyo)
        #expect(h.lastUsedDay == ["open.keep": "2026-09-17"])
        #expect(ask(F.signals(), h)?.promptID == "open.feel")
    }

    // MARK: follow-ups draw too

    private func followUp(_ habits: JournalHabits, today extra: [JournalTurn] = []) -> JournalFollowUpRequest? {
        let turns = [F.turn(.opening, "That one went better than I expected.", index: 0)] + extra
        guard case .followUp(let request) = JournalPlanner.next(signals: F.signals(), habits: habits,
                                                                today: turns, language: .en)
        else { return nil }
        return request
    }

    @Test func theFollowUpTemplatesTakeTurnsStartingWithStand() {
        let yesterday = "2026-09-17"
        #expect(followUp(.none)?.fallback.promptID == "follow.stand")
        #expect(followUp(habits(["follow.stand": yesterday]))?.fallback.promptID == "follow.more")
        #expect(followUp(habits(["follow.stand": "2026-09-16", "follow.more": yesterday]))?.fallback.promptID == "follow.need")
        let all = ["follow.stand": "2026-09-15", "follow.more": "2026-09-16", "follow.need": yesterday]
        #expect(followUp(habits(all))?.fallback.promptID == "follow.stand")
    }

    @Test func aSecondFollowUpTheSameDayDrawsAnotherRow() {
        let opening = F.turn(.opening, "That one went better than I expected.", index: 0)
        let first = F.turn(.followUp, "It really did, I was surprised.", index: 1)
        first.promptID = "follow.stand"
        first.questionText = "You said \"x\". What stands out to you about that?"
        let signals = F.signals(tier: .low)
        guard case .ask = JournalPlanner.next(signals: signals, habits: .none, today: [opening, first], language: .en)
        else { Issue.record("a follow-up of a follow-up must not be offered"); return }
        let heavy = F.turn(.heavy, "A long answer about the body today.", index: 2)
        guard case .followUp(let second) = JournalPlanner.next(signals: signals, habits: .none,
                                                               today: [opening, first, heavy], language: .en)
        else { Issue.record("expected a second follow-up"); return }
        #expect(second.fallback.promptID == "follow.more")
    }

    @Test func theFollowUpRequestCarriesTheRowsAsExamplesAndTheRecentTextsToAvoid() throws {
        let request = try #require(followUp(habits(["follow.stand": "2026-09-17"],
                                                   texts: ["What did you notice?", "How was the walk?"])))
        #expect(request.examples.map(\.id) == ["follow.more", "follow.need", "follow.stand"])
        #expect(request.examples[0].text == "Say more about \"That one went better than I expected\".")
        #expect(request.avoid == ["question", "What did you notice?", "How was the walk?"])
        #expect(request.avoiding == request.examples.map(\.text) + request.avoid)
    }

    // MARK: the brief

    @Test func anOpeningCarriesItsBrief() throws {
        let quests = ["Walk", "Read", "Stretch"].map { F.quest($0) }
        let signals = F.signals(tier: .low, quests: quests, ratings: quests.map { F.rating(of: $0.id, -2) })
        let h = habits(["open.keep": "2026-09-17", "open.scale": "2026-09-10"],
                       texts: ["What stayed with you this evening?"])
        let q = try #require(ask(signals, h))
        #expect(q.promptID == "open.feel")
        let brief = try #require(q.brief)
        #expect(brief.language == .en)
        #expect(brief.approach == .open)            // the approach of the fallback row, open.feel
        #expect(brief.facts == JournalFacts(tier: .low, completedCount: 3, ratingBucket: .negative,
                                            hasChoiceItem: false, hasPhotoItem: false, hasSkippedItem: false))
        #expect(brief.examples.map(\.id) == ["open.feel", "open.scale", "open.keep"])
        #expect(brief.examples.map(\.text) == [
            "The day is almost over. How do you feel right now?",
            "If today were a number from 1 to 10, what would it be? What kept it from being lower?",
            "What from today do you want to remember?",
        ])
        #expect(brief.avoid == ["What stayed with you this evening?"])
        #expect(q.text == brief.examples[0].text)
    }

    @Test func todaysQuestionsComeFirstInTheAvoidList() throws {
        let opening = F.turn(.opening, "short", index: 0)
        opening.questionText = "What from today do you want to remember?"
        let q = try #require(ask(F.signals(), habits(texts: ["older one"]), today: [opening]))
        #expect(q.brief?.avoid == ["What from today do you want to remember?", "older one"])
    }

    @Test func theExamplesAreCappedAtThreeAndTheMostRecentlyUsedRowIsLeftOut() throws {
        let q = try #require(afterOpening(F.signals(tier: .low), habits(["heavy.body": "2026-09-17"])))
        let ids = try #require(q.brief).examples.map(\.id)
        #expect(ids.count == 3)
        #expect(!ids.contains("heavy.body"))
        #expect(JournalQuestionBrief.maxExamples == 3)
    }

    @Test func anExampleIsFilledWithTheSubjectAndARowTheDayCannotFillIsLeftOut() throws {
        let walk = F.quest("Morning walk")
        let good = try #require(afterOpening(F.signals(quests: [walk], ratings: [F.rating(of: walk.id, 2)])))
        let texts = try #require(good.brief).examples.map(\.text)
        #expect(Set(texts) == ["You rated Morning walk high. Which moment was the best part?",
                               "If you did Morning walk again, what would you keep exactly the same?",
                               "Who or what made it better?"])
        #expect(good.brief?.facts.hasChoiceItem == false)

        // choice.item says "You picked {item}" and the app never has a pick to put there.
        let photo = F.quest("Take a photo of the sky")
        let choice = try #require(afterOpening(F.signals(quests: [photo])))
        #expect(Set(try #require(choice.brief).examples.map(\.id)) == ["choice.photo", "choice.notice"])
        #expect(choice.brief?.facts.hasPhotoItem == true)
    }

    @Test func aSkipBriefNamesTheRoutineAndCarriesTheSubject() throws {
        let missed = F.occurrence("Take out the trash", due: "2026-09-15", skipped: true)
        let signals = F.signals(occurrences: [missed], ledger: [F.skipEntry(for: missed, on: F.day)])
        let q = try #require(afterOpening(signals, habits(["skip.small": "2026-09-17", "skip.exception": "2026-09-16"])))
        #expect(q.promptID == "skip.block")
        #expect(q.subject?.text == "Take out the trash")
        let brief = try #require(q.brief)
        #expect(brief.approach == .open)
        #expect(brief.facts.hasSkippedItem)
        #expect(brief.examples.map(\.text).first == "Take out the trash didn't happen. What got in the way?")
    }

    @Test func theBriefIsInTheUsersLanguage() throws {
        let q = try #require(ask(F.signals(), language: .zhHans))
        let brief = try #require(q.brief)
        #expect(brief.language == .zhHans)
        #expect(brief.examples.allSatisfy { $0.text.contains(where: { "\u{4E00}"..."\u{9FFF}" ~= $0 }) })
    }

    @Test func aTemplateFollowUpFallbackHasNoBriefOfItsOwn() {
        #expect(JournalFollowUp.template(answer: "I walked home in the rain", language: .en)?.brief == nil)
    }
}
