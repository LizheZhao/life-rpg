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
    ]
    private let chineseMarkers = [
        "一次只问一个问题", "不给建议", "不做诊断", "不要以“为什么”开头", "不夸奖，也不让人内疚",
        "沿用用户自己的话", "不要用“不是……而是……”", "不要用一句话收尾", "不要为了节奏凑三项并列", "不要用破折号", "不要用 markdown",
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
}
