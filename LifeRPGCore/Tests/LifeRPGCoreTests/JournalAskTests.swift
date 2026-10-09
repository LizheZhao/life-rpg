import Foundation
import Testing
@testable import LifeRPGCore

/// "Ask me something": the request, what is accepted of the model's text, and what the editor is
/// told when the model cannot be used. A fake `JournalWording` stands in for the on-device model.
struct JournalAskTests {
    typealias F = JournalFixtures
    private typealias E = EntryFixtures

    // MARK: fixtures

    private let walkQuestion = "What got in the way of the walk?"
    private let grateful = "What are you grateful for today?"

    /// What the user wrote, in a text and in an answer. Nothing of it may reach a privacy-off prompt.
    private let secretText = "I told nobody about the meeting."
    private let secretAnswer = "My sister called."

    private func entry() -> JournalDocument {
        E.doc(E.text(1, secretText),
              E.prompt(2, grateful, answer: secretAnswer, source: .fixed, key: .gratefulFor))
    }

    private func request(_ signals: JournalSignals? = nil, document: JournalDocument? = nil,
                         previous: [String] = [], includeWriting: Bool = true,
                         language: JournalLanguage = .en) -> JournalAskRequest {
        JournalAsk.request(language: language, signals: signals ?? F.signals(), document: document ?? entry(),
                           previousQuestions: previous, includeWriting: includeWriting)
    }

    /// Replies as scripted, counts its calls, or waits until `release()` and ignores cancellation.
    /// A script gives one behavior per call, the last repeating.
    private final class FakeWording: JournalWording, @unchecked Sendable {
        indirect enum Behavior { case reply(String?), hang, script([Behavior]) }
        private let lock = NSLock()
        private let behavior: Behavior
        private var released = false
        private var waiting: CheckedContinuation<Void, Never>?
        private(set) var instructions: [String] = []
        private(set) var prompts: [String] = []

        init(_ behavior: Behavior) { self.behavior = behavior }

        convenience init(_ reply: String?) { self.init(.reply(reply)) }

        convenience init(script replies: [String?]) { self.init(.script(replies.map { .reply($0) })) }

        var callCount: Int { lock.withLock { prompts.count } }

        func word(instructions: String, prompt: String) async -> String? {
            let call = lock.withLock {
                self.instructions.append(instructions)
                prompts.append(prompt)
                return prompts.count - 1
            }
            var current = behavior
            if case .script(let steps) = behavior { current = steps[min(call, steps.count - 1)] }
            switch current {
            case .reply(let text):
                return text
            case .script:
                return nil
            case .hang:
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    let now: Bool = lock.withLock {
                        if released { return true }
                        waiting = c
                        return false
                    }
                    if now { c.resume() }
                }
                return nil
            }
        }

        /// Lets a hanging call finish, so no task outlives the test.
        func release() {
            let pending: CheckedContinuation<Void, Never>? = lock.withLock {
                released = true
                defer { waiting = nil }
                return waiting
            }
            pending?.resume()
        }
    }

    private func resolve(_ wording: (any JournalWording)?, document: JournalDocument? = nil,
                         signals: JournalSignals? = nil, previous: [String] = [], includeWriting: Bool = true,
                         language: JournalLanguage = .en,
                         timeout: Duration = .seconds(60),
                         retryTimeout: Duration = .seconds(60)) async -> JournalAskResult {
        await JournalAsk.resolve(language: language, signals: signals ?? F.signals(), document: document ?? entry(),
                                 previousQuestions: previous, includeWriting: includeWriting,
                                 wording: wording,
                                 timeout: timeout, retryTimeout: retryTimeout)
    }

    private func llmPrompts(_ count: Int) -> [JournalBlock] {
        (0..<count).map { E.prompt(10 + $0, "Question \($0) of the night about \($0 * 7)?", source: .llm) }
    }

    // MARK: the request

    @Test func theRequestCarriesTheInstructionsThePromptAndEverythingToAvoid() {
        let walk = F.quest("Walk")
        let signals = F.signals(tier: .low, quests: [walk])
        let r = request(signals, previous: ["What did you notice yesterday?"])
        #expect(r.language == .en)
        #expect(r.instructions == JournalPromptBuilder.instructions(language: .en))
        #expect(r.prompt == JournalPromptBuilder.prompt(
            language: .en, signals: signals,
            writing: "\(secretText)\n\nQ: \(grateful)\nA: \(secretAnswer)",
            existing: [grateful]))
        // The entry's questions first, then the older entries', then the anchors.
        #expect(r.avoiding == [
            grateful,
            "What did you notice yesterday?",
            "Where did the day weigh on you most, in your body or in your mood?",
            "If a friend had a day like this, what would you say to them?",
            "Your body had less to give today. What did it ask for?",
            "What was your favorite moment today?",
            "What are you grateful for today?",
            "What did the low energy feel like today?",
            "What do you want to carry into tomorrow?",
        ])
    }

    @Test func theChineseRequestIsInChineseThroughout() {
        let r = request(F.signals(tier: .low), document: JournalDocument(), language: .zhHans)
        #expect(r.instructions == JournalPromptBuilder.instructions(language: .zhHans))
        #expect(r.prompt.hasPrefix("为用户的日记写一个关于今天的问题。"))
        #expect(r.avoiding.first == "今天你做了不少事，但听起来感觉并不好。当时是什么样的？")
    }

    private let album = "What did you think of the new album?"

    @Test func thePromptListsNoQuestionFromRecentEntriesByDefault() {
        let r = request(previous: [album, "What was the best moment of your day?"])
        #expect(!r.prompt.contains(album))
        #expect(!r.prompt.contains("What was the best moment of your day?"))
        #expect(!r.prompt.contains("recent entries"))
    }

    @Test func aRecentEntrysQuestionIsStillHeldAgainstTheAnswerWhenThePromptLeftItOut() {
        let r = request(previous: [album])
        #expect(r.avoiding.contains(album))
        #expect(JournalAsk.check(album, request: r) == .failure(.notFresh))
        #expect(JournalAsk.check("what did you think of the new album?", request: r) == .failure(.notFresh))
    }

    /// The model copied the tone anchors it was shown, so it is not shown them. They stay in `avoiding`.
    @Test func theToneAnchorsAreNotInThePromptButAreStillHeldAgainstTheAnswer() {
        let anchorRows = [
            "You got a lot done today, and it doesn't sound like it felt good. What was it like?",
            "Where did the day weigh on you most, in your body or in your mood?",
            "If a friend had a day like this, what would you say to them?",
        ]
        let signals = F.signals(tier: .low)
        #expect(JournalAsk.anchors(signals: signals, questionsInEntry: 0, language: .en) == anchorRows)
        let r = request(signals, document: JournalDocument())
        for row in anchorRows {
            #expect(!r.prompt.contains(row))
            #expect(!r.instructions.contains(row))
            #expect(r.avoiding.contains(row))
        }
        #expect(JournalAsk.check(anchorRows[2], request: r) == .failure(.notFresh))
        #expect(!r.prompt.contains("Examples"))
        #expect(!r.instructions.contains("Examples"))
    }

    // MARK: anchors by the day's facts

    private func anchors(_ signals: JournalSignals, existing: Int = 0, language: JournalLanguage = .en) -> [String] {
        JournalAsk.anchors(signals: signals, questionsInEntry: existing, language: language)
    }

    @Test func aLowDayGetsTheHeavyRowsEvenWithARoutineSkipped() {
        let skipped = F.occurrence("Round two", due: "2026-09-17")
        for tier in [Tier.low, .veryLow] {
            #expect(anchors(F.signals(tier: tier, occurrences: [skipped])) == [
                "You got a lot done today, and it doesn't sound like it felt good. What was it like?",
                "Where did the day weigh on you most, in your body or in your mood?",
                "If a friend had a day like this, what would you say to them?",
            ], "\(tier)")
        }
    }

    @Test func aSkippedRoutineGetsTheSkipRowsWithItsNameFilledIn() {
        let skipped = F.occurrence("Round two", due: "2026-09-17")
        #expect(anchors(F.signals(occurrences: [skipped])) == [
            "“Round two” didn't happen. What got in the way?",
            "Was there a recent time this went more easily? What was different then?",
            "What would make it 10% easier tomorrow?",
        ])
        #expect(anchors(F.signals(occurrences: [skipped]), language: .zhHans).first
                == "「Round two」没做成。是什么挡了一下？")
    }

    @Test func aHighRatedQuestGetsTheGoodRowsWithItsNameFilledIn() {
        let walk = F.quest("Morning run")
        let signals = F.signals(quests: [walk], ratings: [F.rating(of: walk.id, 2)])
        #expect(anchors(signals) == [
            "You rated “Morning run” high. Which moment was the best part?",
            "If you did “Morning run” again, what would you keep exactly the same?",
            "Who or what made it better?",
        ])
    }

    @Test func otherwiseTheOpenRowsAreUsed() {
        let walk = F.quest("Walk")
        let mild = F.signals(quests: [walk], ratings: [F.rating(of: walk.id, 0)])
        let expected = [
            "If today were a number from 1 to 10, what would it be? What kept it from being lower?",
            "The day is almost over. How do you feel right now?",
            "What from today do you want to remember?",
        ]
        #expect(anchors(mild) == expected)
        #expect(anchors(F.signals()) == expected)
    }

    @Test func theAnchorsStartOneRowLaterForEachQuestionAlreadyInTheEntry() {
        let signals = F.signals()
        #expect(anchors(signals, existing: 1) == [
            "The day is almost over. How do you feel right now?",
            "What from today do you want to remember?",
            "If today were a number from 1 to 10, what would it be? What kept it from being lower?",
        ])
        // Three rows in the kind, so the fourth question starts over.
        #expect(anchors(signals, existing: 3) == anchors(signals, existing: 0))
    }

    @Test func aKindWithFourRowsGivesThreeOfThem() {
        #expect(anchors(F.signals(tier: .low), existing: 0).count == 3)
        #expect(anchors(F.signals(tier: .low), existing: 3) == [
            "Your body had less to give today. What did it ask for?",
            "You got a lot done today, and it doesn't sound like it felt good. What was it like?",
            "Where did the day weigh on you most, in your body or in your mood?",
        ])
    }

    // MARK: the privacy switch

    @Test func withTheSwitchOnTheEntryIsInThePromptAsQAndA() {
        let prompt = request().prompt
        #expect(prompt.contains(secretText))
        #expect(prompt.contains("Q: \(grateful)\nA: \(secretAnswer)"))
    }

    @Test func withTheSwitchOffNothingTheUserWroteIsInThePrompt() {
        let walk = F.quest("Walk")
        let r = request(F.signals(quests: [walk]), previous: ["What did you notice yesterday?"], includeWriting: false)
        #expect(!r.prompt.contains(secretText))
        #expect(!r.prompt.contains(secretAnswer))
        #expect(!r.prompt.contains("Q: "))
        #expect(!r.prompt.contains("A: "))
        #expect(!r.prompt.contains("written so far"))
        // What the switch leaves: the day's quests and the questions already listed.
        #expect(r.prompt.contains("- Done: Walk."))
        #expect(r.prompt.contains("Questions already in this entry. Do not ask these again:\n- \(grateful)"))
    }

    @Test func withTheSwitchOffOlderEntriesAreNotSentButStillHeldAgainstTheAnswer() {
        let older = "What did you notice yesterday?"
        let r = request(previous: [older], includeWriting: false)
        #expect(!r.prompt.contains(older))
        #expect(!r.prompt.contains("recent entries"))
        #expect(r.avoiding.contains(older))
        #expect(JournalAsk.accept(older, request: r) == nil)
    }

    @Test func withTheSwitchOffAnEntryOfOnlyFreeTextListsNoQuestionsAndStillNothingOfTheText() {
        let doc = E.doc(E.text(1, secretText))
        let r = request(document: doc, includeWriting: false)
        #expect(!r.prompt.contains(secretText))
        #expect(!r.prompt.contains("Questions already in this entry"))
    }

    // MARK: the questions of earlier entries

    private func row(_ dayKey: String, _ questions: [String]) -> JournalEntry {
        let e = JournalEntry()
        e.dayKey = dayKey
        e.blocks = questions.enumerated().map { E.prompt($0.offset + 1, $0.element, answer: "x") }
        return e
    }

    @Test func theLastThreeOlderEntriesGiveTheirQuestionsNewestFirst() {
        let entries = [
            row("2026-09-10", ["too old"]),
            row("2026-09-14", ["14 a", "14 b"]),
            row("2026-09-15", ["15 a"]),
            row("2026-09-17", ["17 a", "17 b"]),
            row("2026-09-18", ["today"]),
            row("2026-09-19", ["the future"]),
        ]
        #expect(JournalAsk.previousQuestions(before: "2026-09-18", in: entries)
                == ["17 b", "17 a", "15 a", "14 b", "14 a"])
    }

    @Test func anEntryWithoutQuestionsStillCountsAsOneOfTheThree() {
        let entries = [row("2026-09-14", ["14 a"]), row("2026-09-15", []), row("2026-09-16", []),
                       row("2026-09-17", ["17 a"])]
        #expect(JournalAsk.previousQuestions(before: "2026-09-18", in: entries) == ["17 a"])
    }

    @Test func noOlderEntriesGivesNoQuestions() {
        #expect(JournalAsk.previousQuestions(before: "2026-09-18", in: []).isEmpty)
        #expect(JournalAsk.previousQuestions(before: "2026-09-18", in: [row("2026-09-18", ["today"])]).isEmpty)
    }

    // MARK: accepting the model's text

    private func accept(_ raw: String, avoiding: [String] = [], language: JournalLanguage = .en,
                        document: JournalDocument = JournalDocument()) -> String? {
        let r = JournalAsk.request(language: language, signals: F.signals(), document: document,
                                   previousQuestions: avoiding, includeWriting: true)
        return JournalAsk.accept(raw, request: r)
    }

    @Test func aGoodQuestionIsAcceptedAsItIs() {
        #expect(accept("What got in the way of the walk?") == "What got in the way of the walk?")
    }

    @Test func whitespaceSurroundingQuotesAndAllButTheFirstLineAreStripped() {
        #expect(accept("  \n What got in the way of the walk? \n") == "What got in the way of the walk?")
        #expect(accept("\"What got in the way of the walk?\"") == "What got in the way of the walk?")
        #expect(accept("\u{201C}What got in the way of the walk?\u{201D}") == "What got in the way of the walk?")
        #expect(accept("'What got in the way of the walk?'") == "What got in the way of the walk?")
        #expect(accept("\u{300C}今天哪件事你想留下来？\u{300D}", language: .zhHans) == "今天哪件事你想留下来？")
        #expect(accept("What got in the way of the walk?\nLet me know how it goes!")
                == "What got in the way of the walk?")
        // The question mark of a quoted line inside the first is kept, a quote inside is not stripped.
        #expect(accept("What was \"the best part\" of the walk?") == "What was \"the best part\" of the walk?")
    }

    @Test func twoQuestionsOrNoneOrADoubledMarkAreRejected() {
        #expect(accept("What happened? How did it feel?") == nil)
        #expect(accept("What happened today") == nil)
        #expect(accept("What happened??") == nil)
        #expect(accept("今天累吗？想休息吗？", language: .zhHans) == nil)
        // A second question on a second line is dropped with that line, so the first alone passes.
        #expect(accept("What happened today?\nHow did it feel?") == "What happened today?")
    }

    @Test func fifteenWordsAreTooLongAndFourteenAreNot() {
        let fourteen = "What part of the walk home in the rain felt easiest to you today?"
        #expect(fourteen.split(separator: " ").count == 14)
        #expect(accept(fourteen) == fourteen)
        let fifteen = "What part of the long walk home in the rain felt easiest to you today?"
        #expect(fifteen.split(separator: " ").count == 15)
        #expect(accept(fifteen) == nil)
    }

    @Test func aContractionIsOneWord() {
        let text = "What didn't you want to do today, and what got in the way of it at all?"
        #expect(JournalTextCheck.words(text).count == 17)
        #expect(accept(text) == nil)
        #expect(accept("What didn't you want to do today and what got in the way?") != nil)
    }

    @Test func aChineseQuestionIsHeldToTwentyFourCharacters() {
        let ok = "今天哪件事你想留下来，哪一刻最好？"
        #expect(accept(ok, language: .zhHans) == ok)
        let twentyFour = String(repeating: "字", count: 23) + "？"
        let twentyFive = String(repeating: "字", count: 24) + "？"
        #expect(accept(twentyFour, language: .zhHans) == twentyFour)
        #expect(accept(twentyFive, language: .zhHans) == nil)
    }

    @Test func aChineseQuestionIsNotHeldToTheEnglishWordCap() {
        let text = "今天你最想对自己说的一句话是什么呢？"
        #expect(accept(text, language: .zhHans) == text)
    }

    @Test func aPlaceholderLeftInIsRejected() {
        #expect(accept("What got in the way of {quest}?") == nil)
        #expect(accept("「{quest}」没做成。是什么挡了一下？", language: .zhHans) == nil)
        #expect(accept("What got in the way of the walk?") != nil)
    }

    @Test func everyVoiceRuleStillApplies() {
        #expect(accept("Why did you skip it?") == nil)
        #expect(accept("What was it like \u{2014} the walk?") == nil)
        #expect(accept("It's not just the walk, but the rain. What was that like?") == nil)
        #expect(accept("**Bold** question?") == nil)
        #expect(accept("为什么没去？", language: .zhHans) == nil)
    }

    @Test func aCopyOfAQuestionAlreadyInTheEntryIsRejectedWhateverTheCaseOrPunctuation() {
        let doc = E.doc(E.prompt(1, walkQuestion))
        #expect(accept(walkQuestion, document: doc) == nil)
        #expect(accept("what got in the way of the walk", document: doc) == nil)
        #expect(accept("What got in the way of the walk??", document: doc) == nil)
    }

    /// The same frame asked about another thing is another question: the walk and the run were two
    /// things that day (`JournalNovelty` compares what a question is about, not how it is built).
    @Test func theSameFrameAboutAnotherThingIsNotACopy() {
        let doc = E.doc(E.prompt(1, walkQuestion))
        #expect(accept("What got in the way of the run?", document: doc) != nil)
    }

    @Test func aCopyOfAnOlderEntrysQuestionOrAnAnchorIsRejected() {
        #expect(accept("What did you notice yesterday?", avoiding: ["What did you notice yesterday?"]) == nil)
        // The opening rows are the anchors of a plain day.
        #expect(accept("What from today do you want to remember?") == nil)
        #expect(accept("Which moment of this day would you like to hold onto?") != nil)
        #expect(accept("今天有什么事，你想记住？", language: .zhHans) == nil)
    }

    @Test func theSameThemeInDifferentWordsIsAccepted() {
        #expect(accept("Which small thing did you almost miss this afternoon?",
                       avoiding: ["What did you notice today that you would normally walk past?"]) != nil)
    }

    @Test func nothingAtAllIsRejected() {
        #expect(accept("") == nil)
        #expect(accept("  \n  ") == nil)
        #expect(accept("\"\"") == nil)
    }

    // MARK: resolving

    private let toast = "Couldn't reach the guide, here's a standard one"

    @Test func aGoodAnswerFromTheModelIsTheQuestion() async {
        let wording = FakeWording(" \"What got in the way of the walk?\" \n")
        let result = await resolve(wording)
        #expect(result == .question("What got in the way of the walk?"))
        #expect(wording.callCount == 1)
    }

    @Test func theModelIsHandedTheRequestsInstructionsAndPrompt() async {
        let wording = FakeWording(walkQuestion)
        _ = await resolve(wording, previous: ["What did you notice yesterday?"])
        let r = request(previous: ["What did you notice yesterday?"])
        #expect(wording.instructions == [r.instructions])
        #expect(wording.prompts == [r.prompt])
    }

    @Test func withTheSwitchOffTheModelNeverSeesTheWriting() async {
        let wording = FakeWording(walkQuestion)
        _ = await resolve(wording, includeWriting: false)
        #expect(wording.callCount == 1)
        #expect(!wording.prompts[0].contains(secretText))
        #expect(!wording.prompts[0].contains(secretAnswer))
    }

    @Test func aModelThatHasNothingToSayGivesTheFirstFixedPromptTheEntryLacks() async {
        let wording = FakeWording(nil as String?)
        #expect(await resolve(wording, document: JournalDocument())
                == .fallback(.favoriteMoment, toast: toast))
        #expect(wording.callCount == 1)
    }

    @Test func theFallbackOrderIsFavoriteMomentGratefulTomorrowThenLowEnergy() async {
        func key(_ held: [JournalFixedKey]) async -> JournalAskResult {
            let blocks = held.enumerated().map { E.prompt($0.offset + 1, "q", source: .fixed, key: $0.element) }
            return await resolve(FakeWording(nil as String?), document: JournalDocument(blocks: blocks))
        }
        #expect(await key([]) == .fallback(.favoriteMoment, toast: toast))
        #expect(await key([.favoriteMoment]) == .fallback(.gratefulFor, toast: toast))
        #expect(await key([.favoriteMoment, .gratefulFor]) == .fallback(.tomorrow, toast: toast))
        // Out of order and skipping: the first of the order that is missing.
        #expect(await key([.gratefulFor, .tomorrow]) == .fallback(.favoriteMoment, toast: toast))
        #expect(await key([.favoriteMoment, .gratefulFor, .tomorrow]) == .fallback(.lowEnergyFeltLike, toast: toast))
    }

    @Test func aModelThatFailsWithEveryFixedPromptInTheEntryIsExhausted() async {
        let blocks = JournalFixedKey.allCases.enumerated().map { E.prompt($0.offset + 1, "q", source: .fixed, key: $0.element) }
        let result = await resolve(FakeWording(nil as String?), document: JournalDocument(blocks: blocks))
        #expect(result == .exhausted)
    }

    @Test func aRejectedAnswerOtherThanNotFreshFallsBackAndIsNotRetried() async {
        let wording = FakeWording("What happened? How did it feel?")
        #expect(await resolve(wording, document: JournalDocument()) == .fallback(.favoriteMoment, toast: toast))
        #expect(wording.callCount == 1)
    }

    @Test func aDuplicateOfAQuestionInTheEntryFallsBack() async {
        let doc = E.doc(E.prompt(1, walkQuestion, answer: "x", source: .llm))
        let result = await resolve(FakeWording(walkQuestion), document: doc)
        #expect(result == .fallback(.favoriteMoment, toast: toast))
    }

    @Test func aDuplicateOfAnOlderEntrysQuestionFallsBackEvenWithTheSwitchOff() async {
        let result = await resolve(FakeWording(walkQuestion), document: JournalDocument(), previous: [walkQuestion],
                                   includeWriting: false)
        #expect(result == .fallback(.favoriteMoment, toast: toast))
    }

    @Test func noModelOnTheDeviceIsTheFallbackWithoutAsking() async {
        #expect(await resolve(nil, document: JournalDocument()) == .fallback(.favoriteMoment, toast: toast))
    }

    @Test(.timeLimit(.minutes(1)))
    func aModelThatHangsPastTheTimeoutIsTheFallbackAndTheCallerIsNotHeldByIt() async {
        let wording = FakeWording(.hang)
        let result = await resolve(wording, document: JournalDocument(), timeout: .milliseconds(50))
        // The fake only finishes when released below, so returning at all is the proof that the
        // caller did not wait for it. No clock is read.
        #expect(result == .fallback(.favoriteMoment, toast: toast))
        wording.release()
    }

    @Test func theTimeoutIsTenSeconds() {
        #expect(JournalAsk.timeout == .seconds(10))
    }

    // MARK: the diagnosis

    private final class Heard: @unchecked Sendable {
        private let lock = NSLock()
        private var value: [JournalAskDiagnosis] = []
        func add(_ d: JournalAskDiagnosis) { lock.withLock { value.append(d) } }
        var all: [JournalAskDiagnosis] { lock.withLock { value } }
    }

    private func diagnosis(_ wording: (any JournalWording)?, previous: [String] = [],
                           timeout: Duration = .seconds(60),
                           retryTimeout: Duration = .seconds(60)) async -> [JournalAskDiagnosis] {
        let heard = Heard()
        _ = await JournalAsk.resolve(language: .en, signals: F.signals(), document: JournalDocument(),
                                     previousQuestions: previous, includeWriting: true, wording: wording,
                                     timeout: timeout, retryTimeout: retryTimeout, diagnose: { heard.add($0) })
        return heard.all
    }

    @Test func eachWayTheModelFailsIsToldApart() async {
        #expect(await diagnosis(nil) == [JournalAskDiagnosis(.noModel)])
        #expect(await diagnosis(FakeWording(nil)) == [JournalAskDiagnosis(.noAnswer)])
        #expect(await diagnosis(FakeWording("Absolutely, here you go!"))
                == [JournalAskDiagnosis(.rejected(text: "Absolutely, here you go!", reason: .noQuestionMark,
                                                  nearest: nil))])
        #expect(await diagnosis(FakeWording(walkQuestion)) == [JournalAskDiagnosis(.answered)])
    }

    @Test(.timeLimit(.minutes(1)))
    func aHangingModelIsDiagnosedAsTimedOut() async {
        let wording = FakeWording(.hang)
        #expect(await diagnosis(wording, timeout: .milliseconds(50)) == [JournalAskDiagnosis(.timedOut)])
        wording.release()
    }

    // MARK: the retry

    @Test func aCopyOfAnOlderQuestionIsAskedAgainWithTheRejectedTextInThePrompt() async {
        let wording = FakeWording(script: [album, walkQuestion])
        let result = await resolve(wording, document: JournalDocument(), previous: [album])
        #expect(result == .question(walkQuestion))
        #expect(wording.callCount == 2)
        let first = request(document: JournalDocument(), previous: [album])
        #expect(wording.prompts[0] == first.prompt)
        #expect(wording.prompts[1] == JournalPromptBuilder.retryPrompt(first.prompt, rejected: album, reason: .notFresh, language: .en))
        #expect(wording.prompts[1].contains(album))
        #expect(wording.instructions == [first.instructions, first.instructions])
    }

    @Test func theRetryPromptNamesTheRejectedQuestionAsItWouldHaveBeenShown() async {
        // Quoted, with a second line: the retry prompt names the question as it would have been shown.
        let wording = FakeWording(script: ["\"\(album)\"\nand a second line", walkQuestion])
        _ = await resolve(wording, document: JournalDocument(), previous: [album])
        #expect(wording.prompts[1].hasSuffix(JournalPromptBuilder.retryPrompt("", rejected: album, reason: .notFresh, language: .en)))
        #expect(!wording.prompts[1].contains("second line"))
    }

    @Test func aSecondAnswerThatIsAlsoRejectedFallsBackAfterTwoCalls() async {
        let wording = FakeWording(script: [album, album])
        let result = await resolve(wording, document: JournalDocument(), previous: [album])
        #expect(result == .fallback(.favoriteMoment, toast: toast))
        #expect(wording.callCount == 2)
    }

    @Test func aSecondAnswerRejectedForAnotherReasonFallsBackAfterTwoCalls() async {
        let wording = FakeWording(script: [album, "Absolutely, here you go!"])
        let result = await resolve(wording, document: JournalDocument(), previous: [album])
        #expect(result == .fallback(.favoriteMoment, toast: toast))
        #expect(wording.callCount == 2)
    }

    @Test func aSecondCallThatAnswersNothingFallsBack() async {
        let wording = FakeWording(script: [album, nil])
        let result = await resolve(wording, document: JournalDocument(), previous: [album])
        #expect(result == .fallback(.favoriteMoment, toast: toast))
        #expect(wording.callCount == 2)
    }

    @Test func aFirstAnswerRejectedForAnyOtherReasonIsNotAskedAgain() async {
        let cases: [(String, JournalAskRejection)] = [
            ("", .empty),
            ("What happened? How did it feel?", .noQuestionMark), ("What about {quest}?", .placeholder),
            ("Why did the walk feel slow?", .voice),
        ]
        for (text, reason) in cases {
            let wording = FakeWording(script: [text, walkQuestion])
            let result = await resolve(wording, document: JournalDocument(), previous: [album])
            #expect(result == .fallback(.favoriteMoment, toast: toast), "\(reason)")
            #expect(wording.callCount == 1, "\(reason)")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aFirstCallThatTimesOutIsNotAskedAgain() async {
        let wording = FakeWording(.hang)
        let result = await resolve(wording, document: JournalDocument(), timeout: .milliseconds(50))
        #expect(result == .fallback(.favoriteMoment, toast: toast))
        #expect(wording.callCount == 1)
        wording.release()
    }

    @Test func aModelThatThrewIsNotAskedAgain() async {
        let wording = FakeWording(nil as String?)
        _ = await resolve(wording, document: JournalDocument(), previous: [album])
        #expect(wording.callCount == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func aSecondCallThatHangsIsCutOffByTheRetryTimeoutAlone() async {
        let wording = FakeWording(.script([.reply(album), .hang]))
        let result = await resolve(wording, document: JournalDocument(), previous: [album],
                                   timeout: .seconds(60), retryTimeout: .milliseconds(50))
        #expect(result == .fallback(.favoriteMoment, toast: toast))
        #expect(wording.callCount == 2)
        wording.release()
    }

    @Test func theRetryHasFiveSeconds() {
        #expect(JournalAsk.retryTimeout == .seconds(5))
    }

    // MARK: the diagnosis of a retry

    @Test func aCopyIsDiagnosedWithTheNearestQuestionAndHowAlike() async {
        let heard = await diagnosis(FakeWording(album), previous: [album], retryTimeout: .seconds(60))
        #expect(heard == [JournalAskDiagnosis(
            .rejected(text: album, reason: .notFresh, nearest: JournalNovelty.Match(question: album, similarity: 1)),
            retried: true)])
    }

    @Test func aFreshSecondAnswerIsToldApartFromAFreshFirstOne() async {
        let heard = await diagnosis(FakeWording(script: [album, walkQuestion]), previous: [album])
        #expect(heard == [JournalAskDiagnosis(.answered, retried: true)])
        #expect(heard != [JournalAskDiagnosis(.answered)])
    }

    @Test func aSecondAnswerRejectedForAnotherReasonIsDiagnosedAsThatReasonAfterARetry() async {
        let heard = await diagnosis(FakeWording(script: [album, "Absolutely, here you go!"]), previous: [album])
        #expect(heard == [JournalAskDiagnosis(
            .rejected(text: "Absolutely, here you go!", reason: .noQuestionMark, nearest: nil), retried: true)])
    }

    @Test(.timeLimit(.minutes(1)))
    func aSecondCallThatHangsIsDiagnosedAsTimedOutAfterARetry() async {
        let wording = FakeWording(.script([.reply(album), .hang]))
        let heard = await diagnosis(wording, previous: [album], retryTimeout: .milliseconds(50))
        #expect(heard == [JournalAskDiagnosis(.timedOut, retried: true)])
        wording.release()
    }

    @Test func nearestAvoidedQuestionComesFromEverythingTheAnswerIsHeldAgainst() {
        let r = request(previous: ["What was the best moment of your day?", album])
        let match = JournalAsk.nearestAvoided(" \"\(album)\" ", request: r)
        #expect(match == JournalNovelty.Match(question: album, similarity: 1))
        // Only "moment" is shared, with the favorite-moment chip: 1 of 4 distinct content words.
        #expect(JournalAsk.nearestAvoided("Which moment stood out?", request: r)
                == JournalNovelty.Match(question: "What was your favorite moment today?", similarity: 0.25))
    }

    @Test func theSummariesReadAsOneLineEach() {
        func summary(_ outcome: JournalAskDiagnosis.Outcome, retried: Bool = false) -> String {
            JournalAskDiagnosis(outcome, retried: retried).summary
        }
        let copy = JournalAskDiagnosis.Outcome.rejected(
            text: album, reason: .notFresh, nearest: JournalNovelty.Match(question: album, similarity: 1))
        #expect(summary(.noModel) == "no model on this device")
        #expect(summary(.timedOut) == "timed out after 10 s")
        #expect(summary(.timedOut, retried: true) == "timed out after 5 s, on the second ask")
        #expect(summary(.noAnswer) == "the model threw or answered nothing")
        #expect(summary(.answered) == "answered")
        #expect(summary(.answered, retried: true) == "answered on the second ask")
        #expect(summary(.rejected(text: "Hi", reason: .noQuestionMark, nearest: nil))
                == "rejected (noQuestionMark): Hi")
        #expect(summary(copy) == "rejected (notFresh): What did you think of the new album? "
                + "closest to \"What did you think of the new album?\" at 1.00")
        #expect(summary(.rejected(text: "Which moment stood out?", reason: .notFresh,
                                  nearest: JournalNovelty.Match(question: "Q?", similarity: 0.6666)), retried: true)
                == "rejected (notFresh): Which moment stood out? closest to \"Q?\" at 0.67, on the second ask")
    }

    @Test func checkNamesTheFirstRuleATextBreaks() {
        let r = request(F.signals())
        #expect(JournalAsk.check("", request: r) == .failure(.empty))
        #expect(JournalAsk.check(String(repeating: "word ", count: 20) + "?", request: r) == .failure(.tooLong))
        #expect(JournalAsk.check("What about {quest}?", request: r) == .failure(.placeholder))
        #expect(JournalAsk.check("Why did the walk feel slow?", request: r) == .failure(.voice))
    }

    // MARK: closed questions

    private func verdict(_ raw: String, language: JournalLanguage = .en,
                         signals: JournalSignals? = nil) -> Result<String, JournalAskRejection> {
        JournalAsk.check(raw, request: request(signals, document: JournalDocument(), language: language))
    }

    /// The first two are what the on-device model wrote in the evaluation.
    @Test func aQuestionThatOpensWithAnAuxiliaryVerbIsClosed() {
        let closed = [
            "Did you enjoy cleaning the kitchen?",
            "Did you find the stretch enjoyable, or did you find it difficult to complete?",
            "did you enjoy it?", "\"Did you enjoy it?\"",
            "Do you want to try again tomorrow?", "Does the walk feel easier now?",
            "Is the desk tidy now?", "Are you glad you went?", "Was the run hard?", "Were you tired?",
            "Am I wrong about the walk?", "Have you eaten yet?", "Has the week been heavy?",
            "Had you planned the walk?", "Can you describe the run?", "Could you stay longer?",
            "Will you walk tomorrow?", "Would you do it again?", "Should you rest?",
            "Shall we call the run easy?", "May I ask about the run?", "Might you walk tomorrow?",
            "Didn't the walk help?", "Isn't it nice out?", "Couldn\u{2019}t you stay longer?",
        ]
        for text in closed {
            #expect(verdict(text) == .failure(.closedQuestion), "\(text)")
        }
    }

    @Test func aQuestionThatEndsInATagIsClosed() {
        let closed = [
            "You liked the walk, didn't you?", "That was a hard run, wasn't it?", "You enjoyed it, right?",
            "You did the laundry, did you?", "It went fine, didn\u{2019}t it?", "You can say it, can't you?",
            "The kitchen is done, is it?", "You will go tomorrow, won't you?", "That was hard, okay?",
        ]
        for text in closed {
            #expect(verdict(text) == .failure(.closedQuestion), "\(text)")
        }
    }

    @Test func anOpenEnglishQuestionIsNotClosed() {
        let open = [
            "What was it like to finish the run?", "How did the walk feel?", "What got in the way of the walk?",
            "Which part of the stretch felt hardest?", "Where did you feel it most?", "Who made lunch better?",
            "When did the kitchen start to feel done?", "Dinner with Mei: what stood out?",
            "Island air, tight legs: what stayed with you?", "Having a hard run, what helped?",
            "What did you do, right after the run?", "What made it feel right?",
            "What did you say to the person who did the dishes?",
        ]
        for text in open {
            #expect(verdict(text) == .success(text), "\(text)")
        }
    }

    @Test func aChineseQuestionThatEndsInMaOrHoldsAnAOrNotAFormIsClosed() {
        let closed = [
            "你喜欢今天的散步吗？", "今天过得还好吗？", "你累吗?", "有没有哪一刻特别难？", "你是不是有点累？",
            "能不能说说那次跑步？", "会不会太累了？", "要不要明天再试一次？", "好不好玩？", "对不对？",
        ]
        for text in closed {
            #expect(verdict(text, language: .zhHans) == .failure(.closedQuestion), "\(text)")
        }
    }

    @Test func anOpenChineseQuestionIsNotClosed() {
        let open = [
            "你觉得怎么样？", "是什么挡了一下？", "那次跑步，哪一刻最难？", "今天哪件事你想留下来？",
            "你是怎么做到的？", "今晚有哪一刻你想多留一会儿？",
        ]
        for text in open {
            #expect(verdict(text, language: .zhHans) == .success(text), "\(text)")
        }
    }

    @Test func theEnglishWordsAreNotReadInAChineseQuestionNorTheChineseFormsInAnEnglishOne() {
        #expect(verdict("Did 你觉得怎么样？", language: .zhHans) == .success("Did 你觉得怎么样？"))
        #expect(verdict("What was 吗 like?") == .success("What was 吗 like?"))
    }

    // MARK: early and ahead

    @Test func earlyOrAheadWithNoFactSayingSoIsRejected() {
        let early = [
            "What was it like to finish the run early?", "How did finishing ahead of time feel?",
            "Early on, what felt hardest?", "What was it like to do the laundry in advance?",
            "What did the dishes feel like before its day?", "AHEAD of the deadline, what changed?",
            "What was the early part like?",
        ]
        for text in early {
            #expect(verdict(text) == .failure(.unsupportedEarly), "\(text)")
        }
        let chinese = ["提前完成是什么感觉？", "提早做完那件事后，你做了什么？", "你早早做完了，然后呢？"]
        for text in chinese {
            #expect(verdict(text, language: .zhHans) == .failure(.unsupportedEarly), "\(text)")
        }
    }

    @Test func wordsThatOnlyContainEarlyOrAheadAreNotRejected() {
        let fine = [
            "What did you do after the earlier walk?", "What went through your head during the run?",
            "Where did you head after lunch?", "What did the earliest hour of the day feel like?", "How did the yearly review feel?",
        ]
        for text in fine {
            #expect(verdict(text) == .success(text), "\(text)")
        }
        let chinese = ["早上的散步是什么感觉？", "你最早想到的是什么？", "前一天晚上你做了什么？"]
        for text in chinese {
            #expect(verdict(text, language: .zhHans) == .success(text), "\(text)")
        }
    }

    /// A hard quest done on its own day is the case the model got wrong.
    @Test func aPlainHardQuestDoneOnItsOwnDayDoesNotAllowEarly() {
        let hard = F.quest("Run 5 km")
        hard.slot = .hard
        let signals = F.signals(quests: [hard])
        #expect(request(signals).allowsEarly == false)
        #expect(verdict("What was it like to finish the run early?", signals: signals) == .failure(.unsupportedEarly))
    }

    private func epicDay(finished doneDay: String, on dayKey: String) -> JournalSignals {
        let epic = F.quest("Write up a technical topic", on: "2026-09-14", hour: 9)
        epic.slot = .epic
        epic.points = 100
        epic.completedAt = Fixtures.date(doneDay, hour: 20)
        return JournalSignals(dayKey: dayKey, quests: [], occurrences: [], context: F.context(tier: .normal),
                              ratings: [], epic: epic, timeZone: Fixtures.tokyo)
    }

    @Test func anEpicFinishedTodayWithDaysToSpareAllowsEarly() {
        let signals = epicDay(finished: "2026-09-18", on: "2026-09-18")
        #expect(request(signals).allowsEarly)
        let text = "What was it like to finish the report early?"
        #expect(verdict(text, signals: signals) == .success(text))
        let chinese = "提前完成报告是什么感觉？"
        #expect(verdict(chinese, language: .zhHans, signals: signals) == .success(chinese))
    }

    @Test func anEpicFinishedOnItsLastDayOrEarlierInTheWeekOrNotYetDoesNotAllowEarly() {
        #expect(request(epicDay(finished: "2026-09-20", on: "2026-09-20")).allowsEarly == false)
        #expect(request(epicDay(finished: "2026-09-16", on: "2026-09-18")).allowsEarly == false)
        let open = F.quest("Write up a technical topic", on: "2026-09-14", done: false)
        open.slot = .epic
        #expect(request(F.signals(quests: [open], on: "2026-09-14")).allowsEarly == false)
    }

    @Test func aRoutineDoneBeforeItsDayAllowsEarly() {
        let ahead = F.routineDone("Laundry")
        ahead.dueDayKey = "2026-09-19"
        let signals = F.signals(occurrences: [ahead])
        #expect(request(signals).allowsEarly)
        let text = "How did the laundry feel, done a day ahead?"
        #expect(verdict(text, signals: signals) == .success(text))
    }

    @Test func aRoutineDoneOnItsDayOrLateDoesNotAllowEarly() {
        let late = F.routineDone("Laundry")
        late.dueDayKey = "2026-09-16"
        #expect(request(F.signals(occurrences: [F.routineDone("Dishes"), late])).allowsEarly == false)
    }

    @Test func theChecksRunInOrderAndNotFreshIsLast() {
        let r = request(F.signals(), document: JournalDocument(), previous: ["Did you finish the run early?"])
        // Closed and early and a copy: the first rule it breaks.
        #expect(JournalAsk.check("Did you finish the run early?", request: r) == .failure(.closedQuestion))
        #expect(JournalAsk.check("What was it like to finish the run early?", request: r) == .failure(.unsupportedEarly))
        // Voice before closed; placeholder before closed; length before both.
        #expect(JournalAsk.check("Why did you finish early?", request: r) == .failure(.voice))
        #expect(JournalAsk.check("Did you enjoy {quest}?", request: r) == .failure(.placeholder))
        #expect(JournalAsk.check("Did you finish the long run early and then rest for most of the evening at home?",
                                 request: r) == .failure(.tooLong))
        // A copy that is neither closed nor early is still notFresh.
        let copy = request(F.signals(), document: JournalDocument(), previous: [album])
        #expect(JournalAsk.check(album, request: copy) == .failure(.notFresh))
    }

    // MARK: the wider retry

    @Test func aClosedFirstAnswerIsAskedAgainWithItsOwnSentence() async {
        let closed = "Did you enjoy cleaning the kitchen?"
        let wording = FakeWording(script: [closed, walkQuestion])
        let result = await resolve(wording, document: JournalDocument())
        #expect(result == .question(walkQuestion))
        #expect(wording.callCount == 2)
        let first = request(document: JournalDocument())
        #expect(wording.prompts[1] == first.prompt + "\n\nYour last question could be answered yes or no. "
                + "Ask an open question that starts with What or How.")
        #expect(wording.instructions == [first.instructions, first.instructions])
    }

    @Test func anEarlyFirstAnswerWithNoFactIsAskedAgainWithItsOwnSentence() async {
        let early = "What was it like to finish the run early?"
        let wording = FakeWording(script: [early, walkQuestion])
        let result = await resolve(wording, document: JournalDocument())
        #expect(result == .question(walkQuestion))
        #expect(wording.callCount == 2)
        let first = request(document: JournalDocument())
        #expect(wording.prompts[1] == first.prompt + "\n\nYour last question said something was early, "
                + "but nothing in the facts was. Ask again without saying early or ahead.")
    }

    @Test func anEarlyAnswerIsNotAskedAgainWhenAFactSaysEarly() async {
        let ahead = F.routineDone("Laundry")
        ahead.dueDayKey = "2026-09-19"
        let early = "How did the laundry feel, done early?"
        let wording = FakeWording(script: [early, walkQuestion])
        let result = await resolve(wording, document: JournalDocument(), signals: F.signals(occurrences: [ahead]))
        #expect(result == .question(early))
        #expect(wording.callCount == 1)
    }

    @Test func theRetryIsOnceWhicheverRuleSentItThere() async {
        let closed = "Did you enjoy cleaning the kitchen?"
        let early = "What was it like to finish the run early?"
        let cases: [[String?]] = [[closed, closed], [closed, early], [early, closed], [early, early],
                                  [album, closed], [closed, album], [closed, nil], [early, nil],
                                  [tooLong, tooLong], [tooLong, closed], [closed, tooLong], [album, tooLong],
                                  [tooLong, album], [tooLong, nil]]
        for script in cases {
            let wording = FakeWording(script: script + [walkQuestion])
            let result = await resolve(wording, document: JournalDocument(), previous: [album])
            #expect(result == .fallback(.favoriteMoment, toast: toast), "\(script)")
            #expect(wording.callCount == 2, "\(script)")
        }
    }

    @Test func aClosedRetryDoesNotShowTheModelTheQuestionItJustWrote() async {
        let wording = FakeWording(script: ["\"Did you enjoy it?\"\nand a second line", walkQuestion])
        _ = await resolve(wording, document: JournalDocument())
        #expect(wording.prompts[1].hasSuffix("Your last question could be answered yes or no. Ask an open question that starts with What or How."))
        #expect(!wording.prompts[1].contains("enjoy it"))
        #expect(!wording.prompts[1].contains("second line"))
    }

    // MARK: the retry on a long answer

    private var tooLong: String { String(repeating: "word ", count: 20) + "?" }

    @Test func aTooLongFirstAnswerIsAskedAgainWithItsOwnSentence() async {
        let wording = FakeWording(script: [tooLong, walkQuestion])
        let result = await resolve(wording, document: JournalDocument())
        #expect(result == .question(walkQuestion))
        #expect(wording.callCount == 2)
        let first = request(document: JournalDocument())
        #expect(wording.prompts[0] == first.prompt)
        #expect(wording.prompts[1] == first.prompt + "\n\nYour last question was too long. Ask one short question, under 15 words.")
        #expect(!wording.prompts[1].contains("word word"))
        #expect(wording.instructions == [first.instructions, first.instructions])
    }

    @Test func aChineseTooLongRetryNamesTheCharacterLimit() {
        #expect(JournalPromptBuilder.retryPrompt("", rejected: "x", reason: .tooLong, language: .zhHans)
                .hasSuffix("你上一个问题太长了。请只问一个短问题，少于 25 个字。"))
    }

    @Test func aTooLongAnswerRejectedTwiceGivesTheDayQuestionAfterTwoCalls() async {
        let hard = F.quest("Run 5 km")
        hard.slot = .hard
        let wording = FakeWording(script: [tooLong, tooLong, walkQuestion])
        let result = await resolve(wording, document: JournalDocument(), signals: F.signals(quests: [hard]))
        #expect(result == .fromDay("\u{201C}Run 5 km\u{201D} was a hard one. What was the toughest moment?",
                                   toast: JournalAsk.dayFallbackToast(language: .en)))
        #expect(wording.callCount == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func aRetryAfterATooLongAnswerIsCutOffByTheRetryTimeout() async {
        let wording = FakeWording(.script([.reply(tooLong), .hang]))
        let result = await resolve(wording, document: JournalDocument(),
                                   timeout: .seconds(60), retryTimeout: .milliseconds(50))
        #expect(result == .fallback(.favoriteMoment, toast: toast))
        #expect(wording.callCount == 2)
        wording.release()
    }

    @Test func theRejectionsThatAreAskedAgainAreExactlyTheseFour() {
        let reasons = Dictionary(uniqueKeysWithValues: JournalAskRejection.allCases.map { ($0, $0.retryReason) })
        #expect(reasons == [.empty: nil, .tooLong: .tooLong, .noQuestionMark: nil, .placeholder: nil, .voice: nil,
                            .closedQuestion: .closedQuestion, .unsupportedEarly: .unsupportedEarly,
                            .notFresh: .notFresh])
    }

    @Test(.timeLimit(.minutes(1)))
    func aRetryAfterAClosedAnswerIsCutOffByTheRetryTimeout() async {
        let wording = FakeWording(.script([.reply("Did you enjoy it?"), .hang]))
        let result = await resolve(wording, document: JournalDocument(),
                                   timeout: .seconds(60), retryTimeout: .milliseconds(50))
        #expect(result == .fallback(.favoriteMoment, toast: toast))
        #expect(wording.callCount == 2)
        wording.release()
    }

    @Test func theDiagnosisNamesTheRuleAndSaysWhenTheSecondAskHappened() async {
        let closed = "Did you enjoy cleaning the kitchen?"
        let early = "What was it like to finish the run early?"
        #expect(await diagnosis(FakeWording(script: [closed, closed]))
                == [JournalAskDiagnosis(.rejected(text: closed, reason: .closedQuestion, nearest: nil), retried: true)])
        #expect(await diagnosis(FakeWording(script: [early, early]))
                == [JournalAskDiagnosis(.rejected(text: early, reason: .unsupportedEarly, nearest: nil), retried: true)])
        #expect(await diagnosis(FakeWording(script: [closed, walkQuestion]))
                == [JournalAskDiagnosis(.answered, retried: true)])
        #expect(await diagnosis(FakeWording(script: [tooLong, tooLong]))
                == [JournalAskDiagnosis(.rejected(text: tooLong, reason: .tooLong, nearest: nil), retried: true)])
        #expect(await diagnosis(FakeWording(script: [tooLong, walkQuestion]))
                == [JournalAskDiagnosis(.answered, retried: true)])
        #expect(JournalAskDiagnosis(.rejected(text: closed, reason: .closedQuestion, nearest: nil), retried: true).summary
                == "rejected (closedQuestion): Did you enjoy cleaning the kitchen?, on the second ask")
        #expect(JournalAskDiagnosis(.rejected(text: early, reason: .unsupportedEarly, nearest: nil)).summary
                == "rejected (unsupportedEarly): What was it like to finish the run early?")
    }

    @Test func notFreshIsTheLastRuleInTheList() {
        #expect(JournalAskRejection.allCases.map(\.rawValue)
                == ["empty", "tooLong", "noQuestionMark", "placeholder", "voice", "closedQuestion",
                    "unsupportedEarly", "notFresh"])
    }

    // MARK: the languages the model is used for

    @Test func onlyEnglishUsesTheModelForNow() {
        #expect(JournalAsk.modelLanguages == [.en])
        #expect(JournalAsk.usesModel(for: .en))
        #expect(!JournalAsk.usesModel(for: .zhHans))
    }

    @Test func aChineseTapNeverCallsTheModelAndGetsTheDayQuestion() async {
        let wording = FakeWording("今晚有哪一刻你想多留一会儿？")
        let signals = F.signals(quests: [F.quest("散步")])
        let result = await resolve(wording, document: JournalDocument(), signals: signals, language: .zhHans)
        #expect(result == .fromDay("你今天完成了「散步」。当时是什么样的？", toast: "没能联系上向导，换一个关于今天的问题"))
        #expect(wording.callCount == 0)
    }

    @Test func aChineseTapWithNothingToAskAboutGetsTheFirstChipWithoutTheModel() async {
        let wording = FakeWording("今晚有哪一刻你想多留一会儿？")
        let result = await resolve(wording, document: JournalDocument(), language: .zhHans)
        #expect(result == .fallback(.favoriteMoment, toast: "没能联系上向导，换一个常用的问题"))
        #expect(wording.callCount == 0)
    }

    @Test func theSameDayInEnglishStillAsksTheModel() async {
        let wording = FakeWording(walkQuestion)
        let result = await resolve(wording, document: JournalDocument(), signals: F.signals(quests: [F.quest("Walk")]))
        #expect(result == .question(walkQuestion))
        #expect(wording.callCount == 1)
    }

    @Test func aChineseTapIsDiagnosedAsLanguageOffOnce() async {
        let heard = Heard()
        _ = await JournalAsk.resolve(language: .zhHans, signals: F.signals(), document: JournalDocument(),
                                     previousQuestions: [], includeWriting: true, wording: FakeWording(walkQuestion),
                                     diagnose: { heard.add($0) })
        #expect(heard.all == [JournalAskDiagnosis(.languageOff)])
        #expect(JournalAskDiagnosis(.languageOff).summary == "the model is not used for this language yet")
    }

    @Test func theCapAndTheSafetyLineStillComeBeforeTheLanguageRule() async {
        let wording = FakeWording(walkQuestion)
        let capped = await resolve(wording, document: JournalDocument(blocks: llmPrompts(5)), language: .zhHans)
        #expect(capped == .capped)
        let safety = await resolve(wording, document: JournalDocument(blocks: [E.text(1, "I want to die")]),
                                   language: .zhHans)
        #expect(safety == .safety(JournalSafety.line(language: .zhHans)))
        let heard = Heard()
        _ = await JournalAsk.resolve(language: .zhHans, signals: F.signals(), document: JournalDocument(blocks: llmPrompts(5)),
                                     previousQuestions: [], includeWriting: true, wording: wording,
                                     diagnose: { heard.add($0) })
        #expect(heard.all.isEmpty)
        #expect(wording.callCount == 0)
    }

    // MARK: the order of the checks

    @Test func fiveModelPromptsInTheEntryIsCappedBeforeTheModelIsCalled() async {
        let wording = FakeWording(walkQuestion)
        let result = await resolve(wording, document: JournalDocument(blocks: llmPrompts(5)))
        #expect(result == .capped)
        #expect(wording.callCount == 0)
    }

    @Test func fourModelPromptsStillAskAndFixedPromptsDoNotCount() async {
        let fixed = JournalFixedKey.allCases.enumerated().map { E.prompt(40 + $0.offset, "fixed \($0.offset)?", source: .fixed, key: $0.element) }
        let wording = FakeWording(walkQuestion)
        let result = await resolve(wording, document: JournalDocument(blocks: llmPrompts(4) + fixed))
        #expect(result == .question(walkQuestion))
        #expect(wording.callCount == 1)
        #expect(JournalAsk.maxLLMPrompts == 5)
    }

    @Test func aKeywordInTheWritingGivesTheSafetyLineWithoutCallingTheModel() async {
        let wording = FakeWording(walkQuestion)
        let doc = E.doc(E.text(1, "Some days I just want to die."))
        let result = await resolve(wording, document: doc)
        #expect(result == .safety("That sounds heavy. This is only a journaling tool and can't help the way a person can. If you might hurt yourself, please reach out to someone you trust or a local crisis line."))
        #expect(wording.callCount == 0)
    }

    @Test func aKeywordInAnAnswerCountsAndTheLineIsInTheSystemLanguage() async {
        let wording = FakeWording(walkQuestion)
        let doc = E.doc(E.prompt(1, grateful, answer: "今天真的撑不下去了", source: .fixed, key: .gratefulFor))
        let result = await resolve(wording, document: doc, language: .zhHans)
        #expect(result == .safety("听起来很沉重。这只是个记日记的工具，帮不上真人能帮的忙。如果你有可能伤害自己，请联系信任的人，或当地的危机求助热线。"))
        #expect(wording.callCount == 0)
    }

    @Test func aKeywordInAQuestionIsNotTheUsersWritingAndIsIgnored() async {
        let doc = E.doc(E.prompt(1, "Do you ever feel hopeless?", answer: "", source: .llm))
        let result = await resolve(FakeWording(walkQuestion), document: doc)
        #expect(result == .question(walkQuestion))
    }

    @Test func theSafetyCheckRunsWithTheSwitchOffToo() async {
        let wording = FakeWording(walkQuestion)
        let doc = E.doc(E.text(1, "I feel hopeless"))
        let result = await resolve(wording, document: doc, includeWriting: false)
        guard case .safety = result else { Issue.record("expected the safety line, got \(result)"); return }
        #expect(wording.callCount == 0)
    }

    @Test func theCapComesBeforeTheSafetyLine() async {
        let blocks = llmPrompts(5) + [E.text(1, "I want to die")]
        let result = await resolve(FakeWording(walkQuestion), document: JournalDocument(blocks: blocks))
        #expect(result == .capped)
    }

    // MARK: what the editor says

    @Test func theTextsTheEditorShowsAreFixedInBothLanguages() {
        #expect(JournalAsk.fallbackToast(language: .en) == "Couldn't reach the guide, here's a standard one")
        #expect(JournalAsk.fallbackToast(language: .zhHans) == "没能联系上向导，换一个常用的问题")
        #expect(JournalAsk.cappedTooltip(language: .en) == "Enough questions for one night")
        #expect(JournalAsk.cappedTooltip(language: .zhHans) == "今晚问得够多了")
        #expect(JournalAsk.exhaustedToast(language: .en)
                == "Couldn't reach the guide, and every standard question is already in your entry")
        #expect(JournalAsk.exhaustedToast(language: .zhHans) == "没能联系上向导，常用的问题也都已经在日记里了")
    }

    @Test func theFallbackToastFollowsTheLanguageOfTheRequest() async {
        let result = await resolve(FakeWording(nil as String?), document: JournalDocument(), language: .zhHans)
        #expect(result == .fallback(.favoriteMoment, toast: "没能联系上向导，换一个常用的问题"))
    }

    // MARK: insertion

    private func insert(_ result: JournalAskResult, into doc: JournalDocument, block: Int?, offset: Int,
                        language: JournalLanguage = .en) -> JournalEdit? {
        let ids = E.Ids(from: 100)
        return JournalAsk.insert(result, into: doc, atBlock: block.map(E.id), offset: offset, language: language,
                                 makeID: ids.make)
    }

    @Test func aQuestionIsInsertedAtTheCursorAsAnLLMPromptWithNoKey() throws {
        let doc = E.doc(E.text(1, "hello world"))
        let edit = try #require(insert(.question(walkQuestion), into: doc, block: 1, offset: 5))
        #expect(edit.document.blocks == [E.text(1, "hello"),
                                         E.prompt(100, walkQuestion, answer: "", source: .llm, key: nil),
                                         E.text(101, " world")])
        #expect(edit.focus == BlockFocus(blockID: E.id(100), offset: 0))
    }

    @Test func aFallbackIsInsertedAsTheFixedPromptWithItsKeyInTheLanguageOfTheEditor() throws {
        let doc = E.doc(E.text(1, "hello"))
        let en = try #require(insert(.fallback(.tomorrow, toast: toast), into: doc, block: 1, offset: 5))
        #expect(en.document.blocks == [E.text(1, "hello"),
                                       E.prompt(100, "What do you want to carry into tomorrow?", answer: "",
                                                source: .fixed, key: .tomorrow)])
        let zh = try #require(insert(.fallback(.tomorrow, toast: toast), into: doc, block: 1, offset: 5, language: .zhHans))
        #expect(zh.document.blocks.last == E.prompt(100, "你想把什么带进明天？", answer: "", source: .fixed, key: .tomorrow))
    }

    @Test func theCursorFromBeforeTheWaitIsUsedEvenIfTheTextGrewOrShrank() throws {
        let grown = E.doc(E.text(1, "hello world and more typed while waiting"))
        let edit = try #require(insert(.question(walkQuestion), into: grown, block: 1, offset: 5))
        #expect(edit.document.blocks.first == E.text(1, "hello"))
        let shrunk = E.doc(E.text(1, "hi"))
        let clamped = try #require(insert(.question(walkQuestion), into: shrunk, block: 1, offset: 5))
        #expect(clamped.document.blocks == [E.text(1, "hi"), E.prompt(100, walkQuestion, answer: "", source: .llm, key: nil)])
    }

    @Test func aFallbackWhoseChipWasTappedWhileWaitingTakesTheNextOneInstead() throws {
        let doc = E.doc(E.text(1, "hello"), E.prompt(2, "q", source: .fixed, key: .favoriteMoment))
        let edit = try #require(insert(.fallback(.favoriteMoment, toast: toast), into: doc, block: 1, offset: 5))
        let inserted = edit.document.blocks.compactMap { block -> JournalFixedKey? in
            if case .prompt(let id, _, _, _, let key) = block, id == E.id(100) { key } else { nil }
        }
        #expect(inserted == [.gratefulFor])
    }

    @Test func aFallbackWithEveryFixedPromptAlreadyInTheEntryInsertsNothing() {
        let blocks = JournalFixedKey.allCases.enumerated().map { E.prompt($0.offset + 1, "q", source: .fixed, key: $0.element) }
        #expect(insert(.fallback(.favoriteMoment, toast: toast), into: JournalDocument(blocks: blocks), block: 1, offset: 0) == nil)
    }

    @Test func theResultsThatAreNotAQuestionInsertNothing() {
        let doc = E.doc(E.text(1, "hello"))
        for result in [JournalAskResult.capped, .exhausted, .safety("line")] {
            #expect(insert(result, into: doc, block: 1, offset: 5) == nil, "\(result)")
        }
    }

    @Test func aCursorInABlockThatIsGoneInsertsNothing() {
        #expect(insert(.question(walkQuestion), into: E.doc(E.text(1, "hello")), block: 99, offset: 0) == nil)
    }

    // MARK: before the tap

    @Test func thePillIsCappedAtFiveModelPromptsAndNotBeforeAndFixedPromptsDoNotCount() {
        #expect(!JournalAsk.isCapped(JournalDocument()))
        #expect(!JournalAsk.isCapped(JournalDocument(blocks: llmPrompts(4))))
        #expect(JournalAsk.isCapped(JournalDocument(blocks: llmPrompts(5))))
        #expect(JournalAsk.isCapped(JournalDocument(blocks: llmPrompts(6))))
        let fixed = JournalFixedKey.allCases.enumerated().map { E.prompt(40 + $0.offset, "fixed \($0.offset)?", source: .fixed, key: $0.element) }
        #expect(!JournalAsk.isCapped(JournalDocument(blocks: llmPrompts(4) + fixed)))
    }

    // MARK: what the editor shows after the insertion

    private func notice(_ result: JournalAskResult, inserted: Bool, document: JournalDocument = E.doc(E.text(1, "hello")),
                        language: JournalLanguage = .en) -> JournalAskNotice? {
        JournalAsk.notice(for: result, inserted: inserted, document: document, language: language)
    }

    @Test func anInsertedQuestionSaysNothing() {
        #expect(notice(.question(walkQuestion), inserted: true) == nil)
    }

    @Test func aFallbackThatWasInsertedShowsTheOneLineToast() {
        #expect(notice(.fallback(.tomorrow, toast: toast), inserted: true) == .toast(toast))
    }

    @Test func exhaustedShowsItsToastAndCappedShowsNoneBecauseThePillAlreadySaysSo() {
        #expect(notice(.exhausted, inserted: false)
                == .toast("Couldn't reach the guide, and every standard question is already in your entry"))
        #expect(notice(.capped, inserted: false) == nil)
    }

    @Test func theSafetyLineIsShownAsItsOwnNoticeAndNotAsAToast() {
        #expect(notice(.safety("line"), inserted: false) == .safety("line"))
    }

    @Test func aQuestionWhoseSpotIsGoneSaysSoInBothLanguages() {
        #expect(notice(.question(walkQuestion), inserted: false)
                == .toast("The place you asked from is gone, so no question was added"))
        #expect(notice(.question(walkQuestion), inserted: false, language: .zhHans)
                == .toast("你提问的位置已经不在了，所以没有加入问题"))
    }

    @Test func aFallbackThatCouldNotBeInsertedBlamesTheSpotUnlessEveryStandardQuestionIsInNow() {
        #expect(notice(.fallback(.tomorrow, toast: toast), inserted: false)
                == .toast("The place you asked from is gone, so no question was added"))
        let all = JournalDocument(blocks: JournalFixedKey.allCases.enumerated().map {
            E.prompt($0.offset + 1, "q", source: .fixed, key: $0.element)
        })
        #expect(notice(.fallback(.tomorrow, toast: toast), inserted: false, document: all)
                == .toast("Couldn't reach the guide, and every standard question is already in your entry"))
    }
}
