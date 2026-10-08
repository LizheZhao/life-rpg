import Foundation
import Testing
@testable import LifeRPGCore

/// When the model can not be used, "Ask me something" asks about one thing from the day before it
/// falls back to a chip (`JournalAsk.dayQuestion`).
struct JournalAskDayQuestionTests {
    typealias F = JournalFixtures
    private typealias E = EntryFixtures

    private func hard(_ text: String, done: Bool = true) -> DailyQuest {
        let q = F.quest(text, done: done)
        q.slot = .hard
        return q
    }

    private func dayQuestion(_ signals: JournalSignals, document: JournalDocument = JournalDocument(),
                             previous: [String] = [], language: JournalLanguage = .en) -> String? {
        JournalAsk.dayQuestion(signals: signals, document: document, previousQuestions: previous, language: language)
    }

    private func resolve(_ signals: JournalSignals, document: JournalDocument = JournalDocument(),
                         language: JournalLanguage = .en) async -> JournalAskResult {
        await JournalAsk.resolve(language: language, signals: signals, document: document,
                                 previousQuestions: [], includeWriting: true, wording: nil)
    }

    @Test func aHardQuestDoneIsAskedAboutByName() {
        let signals = F.signals(quests: [F.quest("Read 20 pages"), hard("Run 5 km")])
        #expect(dayQuestion(signals) == "Run 5 km was a hard one. What was the toughest moment?")
        #expect(dayQuestion(signals, language: .zhHans) == "「Run 5 km」不轻松。最难的是哪一刻？")
    }

    @Test func somethingStillOpenIsAskedWithoutBlame() {
        let signals = F.signals(quests: [F.quest("Call the bank", done: false)])
        #expect(dayQuestion(signals) == "Call the bank is still open. What got in the way today?")
    }

    @Test func withNothingSpecialTheLatestThingDoneIsAsked() {
        let signals = F.signals(quests: [F.quest("Walk", hour: 9), F.quest("Cook a meal", hour: 19)])
        #expect(dayQuestion(signals) == "You finished Cook a meal today. What was it like?")
    }

    /// A question already in the entry, or in one of the last entries, is passed over for the next.
    @Test func aQuestionAlreadyAskedGivesWayToTheNextThing() {
        let signals = F.signals(quests: [F.quest("Walk", hour: 9), F.quest("Cook a meal", hour: 19)])
        let asked = "You finished Cook a meal today. What was it like?"
        #expect(dayQuestion(signals, document: E.doc(E.prompt(1, asked, source: .fixed)))
                == "You finished Walk today. What was it like?")
        #expect(dayQuestion(signals, previous: [asked]) == "You finished Walk today. What was it like?")
    }

    @Test func anEmptyDayHasNothingToAsk() {
        #expect(dayQuestion(F.signals()) == nil)
    }

    @Test func aFailedModelOnADayWithFactsAsksAboutTheDay() async {
        let result = await resolve(F.signals(quests: [hard("Run 5 km")]))
        #expect(result == .fromDay("Run 5 km was a hard one. What was the toughest moment?",
                                   toast: "Couldn't reach the guide, here's one about your day"))
    }

    @Test func aFailedModelOnAnEmptyDayStillFallsBackToAChip() async {
        #expect(await resolve(F.signals()) == .fallback(.favoriteMoment, toast: JournalAsk.fallbackToast(language: .en)))
    }

    @Test func aDayQuestionGoesInAsAFixedPromptWithNoChipKey() throws {
        let doc = E.doc(E.text(1, "Long day."))
        let edit = try #require(JournalAsk.insert(.fromDay("You finished Walk today. What was it like?", toast: "t"),
                                                  into: doc, atBlock: E.id(1), offset: 9, language: .en))
        let prompts = edit.document.blocks.compactMap { block -> (String, PromptSource, JournalFixedKey?)? in
            if case .prompt(_, let q, _, let source, let key) = block { return (q, source, key) }
            return nil
        }
        #expect(prompts.count == 1)
        #expect(prompts[0].0 == "You finished Walk today. What was it like?")
        #expect(prompts[0].1 == .fixed)
        #expect(prompts[0].2 == nil)
        // It is not a model prompt, so it does not count toward the cap.
        #expect(edit.document.llmPromptCount == 0)
    }

    @Test func theDayToastSaysWhereTheQuestionCameFrom() {
        #expect(JournalAsk.dayFallbackToast(language: .en) == "Couldn't reach the guide, here's one about your day")
        #expect(JournalAsk.dayFallbackToast(language: .zhHans) == "没能联系上向导，换一个关于今天的问题")
        let notice = JournalAsk.notice(for: .fromDay("q?", toast: "t"), inserted: true,
                                       document: JournalDocument(), language: .en)
        #expect(notice == .toast("t"))
    }

    /// The model can not slip a chip question back in under other words.
    @Test func theChipQuestionsAreHeldAgainstTheModel() {
        let r = JournalAsk.request(language: .en, signals: F.signals(), document: JournalDocument(),
                                   previousQuestions: [], includeWriting: true)
        for key in JournalFixedKey.allCases {
            #expect(r.avoiding.contains(key.question(language: .en)))
        }
        #expect(JournalAsk.accept("What was your favorite moment of today?", request: r) == nil)
    }
}
