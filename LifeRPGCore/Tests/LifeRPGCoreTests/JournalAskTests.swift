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
    private final class FakeWording: JournalWording, @unchecked Sendable {
        enum Behavior { case reply(String?), hang }
        private let lock = NSLock()
        private let behavior: Behavior
        private var released = false
        private var waiting: CheckedContinuation<Void, Never>?
        private(set) var instructions: [String] = []
        private(set) var prompts: [String] = []

        init(_ behavior: Behavior) { self.behavior = behavior }

        convenience init(_ reply: String?) { self.init(.reply(reply)) }

        var callCount: Int { lock.withLock { prompts.count } }

        func word(instructions: String, prompt: String) async -> String? {
            lock.withLock {
                self.instructions.append(instructions)
                prompts.append(prompt)
            }
            switch behavior {
            case .reply(let text):
                return text
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
                         timeout: Duration = .seconds(60)) async -> JournalAskResult {
        await JournalAsk.resolve(language: language, signals: signals ?? F.signals(), document: document ?? entry(),
                                 previousQuestions: previous, includeWriting: includeWriting,
                                 wording: wording, timeout: timeout)
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
            existing: [grateful], recent: ["What did you notice yesterday?"],
            anchors: [
                "Where did the day weigh on you most, in your body or in your mood?",
                "If a friend had a day like this, what would you say to them?",
                "Your body had less to give today. What did it ask for?",
            ]))
        // The entry's questions first, then the older entries', then the anchors.
        #expect(r.avoiding == [
            grateful,
            "What did you notice yesterday?",
            "Where did the day weigh on you most, in your body or in your mood?",
            "If a friend had a day like this, what would you say to them?",
            "Your body had less to give today. What did it ask for?",
        ])
    }

    @Test func theChineseRequestIsInChineseThroughout() {
        let r = request(F.signals(tier: .low), document: JournalDocument(), language: .zhHans)
        #expect(r.instructions == JournalPromptBuilder.instructions(language: .zhHans))
        #expect(r.prompt.hasPrefix("为用户的日记写一个关于今天的问题。"))
        #expect(r.avoiding.first == "今天你做了不少事，但听起来感觉并不好。当时是什么样的？")
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
            "Round two didn't happen. What got in the way?",
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
            "You rated Morning run high. Which moment was the best part?",
            "If you did Morning run again, what would you keep exactly the same?",
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
        #expect(r.prompt.contains("- Done: Walk (+10 coins)."))
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
        #expect(accept("What got in the way of the run?", document: doc) == nil)
    }

    @Test func aCopyOfAnOlderEntrysQuestionOrAnAnchorIsRejected() {
        #expect(accept("What did you notice yesterday?", avoiding: ["What did you notice yesterday?"]) == nil)
        // The opening rows are the anchors of a plain day.
        #expect(accept("What from today do you want to remember?") == nil)
        #expect(accept("Which moment of this day would you like to hold onto?") != nil)
        #expect(accept("今天有什么事，你想记住？", language: .zhHans) == nil)
    }

    @Test func theSameThemeInDifferentWordsIsAccepted() {
        #expect(accept("Was there something small you almost missed this afternoon?",
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

    @Test func theChineseQuestionIsAcceptedAndAsked() async {
        let wording = FakeWording("今晚有哪一刻你想多留一会儿？")
        let result = await resolve(wording, language: .zhHans)
        #expect(result == .question("今晚有哪一刻你想多留一会儿？"))
        #expect(wording.instructions == [JournalPromptBuilder.instructions(language: .zhHans)])
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

    @Test func aRejectedAnswerFallsBackAndIsNotRetried() async {
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

    @Test func theTimeoutIsSixSeconds() {
        #expect(JournalAsk.timeout == .seconds(6))
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
}
