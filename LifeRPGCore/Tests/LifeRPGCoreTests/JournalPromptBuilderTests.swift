import Foundation
import Testing
@testable import LifeRPGCore

struct JournalPromptBuilderTests {
    typealias F = JournalFixtures

    /// The hand-written rules from `doc/JOURNAL_PROMPTS.md`, as phrases the instructions must carry.
    /// A softened or dropped rule fails here, which is the point: the model is held to these.
    private let englishMarkers = [
        "one question at a time", "no advice", "no diagnosis", "never start with why", "no praise or guilt",
        "user's own words", "no contrast staging", "no closing one-liner", "no triads", "no long dashes", "no markdown",
        "examples are anchors for tone, not templates", "never reuse their wording or sentence structure",
    ]
    private let chineseMarkers = [
        "一次只问一个问题", "不给建议", "不做诊断", "不要以“为什么”开头", "不夸奖，也不让人内疚",
        "沿用用户自己的话", "不要用“不是……而是……”", "不要用一句话收尾", "不要为了节奏凑三项并列", "不要用破折号", "不要用 markdown",
        "示例只是语气的参照，不是模板", "不要沿用它们的措辞和句式",
    ]

    @Test func theInstructionsCarryEveryRuleInBothLanguages() {
        let en = JournalPromptBuilder.instructions(language: .en).lowercased()
        for marker in englishMarkers { #expect(en.contains(marker), "\(marker)") }
        let zh = JournalPromptBuilder.instructions(language: .zhHans)
        for marker in chineseMarkers { #expect(zh.contains(marker), "\(marker)") }
    }

    @Test func theInstructionsAreInTheUsersLanguageOnly() {
        #expect(!JournalPromptBuilder.instructions(language: .en).contains("不"))
        #expect(!JournalPromptBuilder.instructions(language: .zhHans).contains("Never"))
    }

    private func request(question: String, answer: String, language: JournalLanguage = .en,
                         subject: JournalSubject? = nil) -> JournalFollowUpRequest {
        let fallback = JournalFollowUp.template(answer: answer, language: language)!
        return JournalFollowUpRequest(question: question, answer: answer, subject: subject,
                                      language: language, fallback: fallback)
    }

    @Test func theFollowUpPromptHasTheFactsTheTurnAndTheStyleHint() {
        let walk = F.quest("Walk"), read = F.quest("Read")
        let signals = F.signals(tier: .low, quests: [walk, read],
                                ratings: [F.rating(of: walk.id, -2), F.rating(of: read.id, -1)])
        let habits = JournalHabits(medianAnswerLength: 10, typicalHour: nil, usesEmoji: false, weights: [:])
        let prompt = JournalPromptBuilder.followUpPrompt(
            request(question: "Where did the day weigh on you most?", answer: "Mostly my shoulders, all afternoon.",
                    subject: JournalSubject(kind: .quest, id: walk.id, text: "Walk")),
            signals: signals, habits: habits)
        #expect(prompt == """
            Facts about the day:
            - Energy tier: low.
            - Things done: 2.
            - Average rating: -1.5 on a scale of -2 to 2.
            - The question was about: Walk.
            - The user was asked: Where did the day weigh on you most?
            - The user answered: Mostly my shoulders, all afternoon.
            - The user writes short answers. Keep the question under 12 words. Use a plain, calm register.
            """)
    }

    @Test func theChinesePromptIsInChinese() {
        let prompt = JournalPromptBuilder.followUpPrompt(
            request(question: "今天有什么事，你想记住？", answer: "走路回家，很安静", language: .zhHans),
            signals: F.signals(), habits: .none)
        #expect(prompt == """
            这一天的情况：
            - 精力档位：normal。
            - 完成的事：0 件。
            - 用户被问到：今天有什么事，你想记住？
            - 用户回答：走路回家，很安静
            - 问题控制在 30 个字以内。语气平静朴素。
            """)
    }

    /// The request holds one turn, so an earlier answer the caller did not pass cannot be in the prompt.
    @Test func nothingTheUserWroteElsewhereReachesThePrompt() {
        let earlier = "my secret from this morning"
        let turns = [F.turn(.opening, earlier, index: 0), F.turn(.good, "the second answer is long enough", index: 1)]
        guard case .followUp(let req) = JournalPlanner.next(signals: F.signals(), habits: .none, today: turns, language: .en)
        else { Issue.record("expected a follow-up"); return }
        let prompt = JournalPromptBuilder.followUpPrompt(req, signals: F.signals(), habits: .none)
        #expect(prompt.contains("the second answer is long enough"))
        #expect(!prompt.contains(earlier))
    }

    @Test func noAverageIsStatedWhenNothingWasRated() {
        let prompt = JournalPromptBuilder.followUpPrompt(request(question: "Q", answer: "something long enough"),
                                                         signals: F.signals(), habits: .none)
        #expect(!prompt.contains("Average rating"))
    }

    // MARK: fresh questions

    @Test func theQuestionInstructionsKeepTheRulesButNotTheOneAboutQuotingTheUser() {
        let en = JournalPromptBuilder.questionInstructions(language: .en).lowercased()
        for marker in englishMarkers where marker != "user's own words" { #expect(en.contains(marker), "\(marker)") }
        #expect(!en.contains("user's own words"))
        #expect(en.contains("one short, fresh question and nothing else"))
        #expect(!en.contains("reflection"))
        let zh = JournalPromptBuilder.questionInstructions(language: .zhHans)
        for marker in chineseMarkers where marker != "沿用用户自己的话" { #expect(zh.contains(marker), "\(marker)") }
        #expect(!zh.contains("沿用用户自己的话"))
        #expect(!zh.contains("Never"))
    }

    private func brief(_ language: JournalLanguage, signals: JournalSignals, approach: JournalApproach,
                       examples: [String], avoid: [String]) -> JournalQuestionBrief {
        JournalQuestionBrief(language: language, facts: JournalFacts(signals), approach: approach,
                             examples: examples.enumerated().map { JournalExample(id: "e\($0.offset)", text: $0.element) },
                             avoid: avoid)
    }

    private let shortWriter = JournalHabits(medianAnswerLength: 10, typicalHour: nil, usesEmoji: false, weights: [:])

    @Test func theQuestionPromptStatesTheIntentTheFactsTheAnchorsAndWhatToAvoid() {
        let walk = F.quest("Walk"), read = F.quest("Read")
        let signals = F.signals(tier: .low, quests: [walk, read],
                                ratings: [F.rating(of: walk.id, -2), F.rating(of: read.id, -1)])
        let question = JournalQuestion(
            promptID: "heavy.body", kind: .heavy, text: "fallback",
            brief: brief(.en, signals: signals, approach: .selfCompassion,
                         examples: ["Your body had less to give today. What did it ask for?",
                                    "If a friend had a day like this, what would you say to them?"],
                         avoid: ["Where did the day weigh on you most?", "How do you feel right now?"]))
        #expect(JournalPromptBuilder.questionPrompt(question, signals: signals, habits: shortWriter) == """
            Write one new question for the user's journal.
            To ask: a gentle question about a day that felt heavy.
            Shape: separate how it felt from what happened, with kindness toward themselves.
            Facts about the day:
            - Energy tier: low.
            - Things done: 2.
            - Average rating: -1.5 on a scale of -2 to 2.
            - The user writes short answers. Keep the question under 12 words. Use a plain, calm register.

            Examples. They show the tone only; do not reuse their wording or sentence structure:
            - Your body had less to give today. What did it ask for?
            - If a friend had a day like this, what would you say to them?

            Recently asked. Do not ask anything like these:
            - Where did the day weigh on you most?
            - How do you feel right now?
            """)
    }

    @Test func aSkipPromptNamesTheRoutineAndTheFlags() throws {
        let missed = F.occurrence("Take out the trash", due: "2026-09-15", skipped: true)
        let photo = F.quest("Take a photo of the sky")
        let signals = F.signals(quests: [photo], occurrences: [missed], ledger: [F.skipEntry(for: missed, on: F.day)])
        let subject = JournalSubject(kind: .routine, id: missed.id, text: "Take out the trash")
        let question = JournalQuestion(promptID: "skip.small", kind: .skip, text: "fallback", subject: subject,
                                       brief: brief(.en, signals: signals, approach: .exceptions, examples: [], avoid: []))
        let prompt = try #require(JournalPromptBuilder.questionPrompt(question, signals: signals, habits: .none))
        #expect(prompt == """
            Write one new question for the user's journal.
            To ask: a question about something that did not get done, with no blame.
            Shape: look for a time it went better, or the smallest step that would make it easier.
            Facts about the day:
            - Energy tier: normal.
            - Things done: 1.
            - The question is about: Take out the trash.
            - Something done today involved taking a photo.
            - Something done today involved choosing or noticing.
            - A routine was left undone.
            - Keep the question under 20 words. Use a plain, calm register.
            """)
    }

    @Test func theChineseQuestionPromptIsInChinese() throws {
        let signals = F.signals()
        let question = JournalQuestion(promptID: "open.keep", kind: .opening, text: "fallback",
                                       brief: brief(.zhHans, signals: signals, approach: .savoring,
                                                    examples: ["今天有什么事，你想记住？"], avoid: ["这一天快结束了，你现在感觉怎么样？"]))
        let prompt = try #require(JournalPromptBuilder.questionPrompt(question, signals: signals, habits: .none))
        #expect(prompt == """
            为用户的日记写一个新的问题。
            要问的：关于这一整天的问题。
            问法：停在一个好的时刻上，问是什么让它变好。
            这一天的情况：
            - 精力档位：normal。
            - 完成的事：0 件。
            - 问题控制在 30 个字以内。语气平静朴素。

            示例，只用来参考语气，不要沿用它们的措辞和句式：
            - 今天有什么事，你想记住？

            最近问过的问题，不要问得相似：
            - 这一天快结束了，你现在感觉怎么样？
            """)
        #expect(!prompt.contains("Facts"))
    }

    /// The prompt shows the examples the brief names and nothing else from the pool, and only the
    /// avoid-list it was given.
    @Test func onlyThePassedExamplesAndRecentQuestionsAppear() throws {
        let signals = F.signals()
        let question = JournalQuestion(promptID: "open.keep", kind: .opening, text: "What from today do you want to remember?",
                                       brief: brief(.en, signals: signals, approach: .open,
                                                    examples: ["The day is almost over. How do you feel right now?"],
                                                    avoid: ["What did you notice?"]))
        let prompt = try #require(JournalPromptBuilder.questionPrompt(question, signals: signals, habits: .none))
        #expect(prompt.contains("The day is almost over. How do you feel right now?"))
        #expect(prompt.contains("What did you notice?"))
        // The fallback text and every other pool row stay out.
        #expect(!prompt.contains("What from today do you want to remember?"))
        for row in JournalPool.all where row.id != "open.feel" {
            #expect(!prompt.contains(row.en), "\(row.id)")
        }
    }

    @Test func theAvoidListIsCappedAtTheNewestTen() throws {
        let signals = F.signals()
        let recent = (1...14).map { "question \($0)" }
        let question = JournalQuestion(promptID: "open.keep", kind: .opening, text: "x",
                                       brief: brief(.en, signals: signals, approach: .open, examples: [], avoid: recent))
        let prompt = try #require(JournalPromptBuilder.questionPrompt(question, signals: signals, habits: .none))
        #expect(prompt.contains("- question 10\n") || prompt.hasSuffix("- question 10"))
        #expect(!prompt.contains("question 11"))
        #expect(prompt.contains("question 1\n"))
        #expect(JournalPromptBuilder.maxAvoidInPrompt == 10)
    }

    @Test func aQuestionWithoutABriefHasNoPrompt() {
        let template = JournalFollowUp.template(answer: "I walked home in the rain", language: .en)!
        #expect(JournalPromptBuilder.questionPrompt(template, signals: F.signals(), habits: .none) == nil)
    }

    @Test func aFollowUpPromptListsItsExamplesAndRecentQuestionsWhenItHasThem() {
        let answer = "Mostly my shoulders, all afternoon."
        let fallback = JournalFollowUp.template(answer: answer, language: .en)!
        let request = JournalFollowUpRequest(question: "Q", answer: answer, subject: nil, language: .en, fallback: fallback,
                                             examples: [JournalExample(id: "follow.more", text: "Say more about \"Mostly my shoulders\".")],
                                             avoid: ["You said \"tired\". What stands out to you about that?"])
        let prompt = JournalPromptBuilder.followUpPrompt(request, signals: F.signals(), habits: .none)
        #expect(prompt.hasSuffix("""

            Examples. They show the tone only; do not reuse their wording or sentence structure:
            - Say more about "Mostly my shoulders".

            Recently asked. Do not ask anything like these:
            - You said "tired". What stands out to you about that?
            """))
    }
}
