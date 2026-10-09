import Foundation
import Testing
@testable import LifeRPGCore

/// The text handed to the model is pinned whole, in both languages: a softened rule is the failure
/// nobody notices until the voice drifts, and a prompt that quietly gains a line of the user's
/// writing is the privacy failure.
struct JournalPromptBuilderTests {
    typealias F = JournalFixtures
    private typealias E = EntryFixtures

    @Test func theEnglishInstructionsArePinnedWhole() {
        #expect(JournalPromptBuilder.instructions(language: .en) == """
            You help someone write a short end-of-day journal. They tap a button and you give them one question to write about. Reply with the question only, as plain text.
            - Ask exactly one question, under 15 words.
            - Write it in the second person, speaking to "you".
            - Pick one specific thing to ask about. When the user has written something, take it from what they wrote; otherwise take it from the facts: something done, or something not done or skipped. A specific thing beats a general question about the day.
            - Only say something was finished early or ahead of time when a fact above says so. When a fact says that of something hard or the epic, you may ask what finishing it felt like.
            - When a fact lists something as not done or skipped, ask what got in the way of it, without blame. Never ask that about something done, or something the user wrote they did.
            - Give no advice.
            - Make no diagnosis.
            - No praise or guilt.
            - Do not mention coins, points or numbers from the facts.
            - Never ask a question that is already listed, or one close to it.
            - Never start with why.
            - Do not ask a question that can be answered yes or no.
            - Do not restate the facts; just ask.
            - No contrast staging such as "not X, but Y".
            - No closing one-liner that repeats the point.
            - No triads for rhythm; no long dashes; no markdown.
            """)
    }

    @Test func theChineseInstructionsArePinnedWhole() {
        #expect(JournalPromptBuilder.instructions(language: .zhHans) == """
            你在帮用户写一篇简短的睡前日记。用户点一下按钮，你给出一个可以写一写的问题。只回复这个问题，用纯文本。
            - 只问一个问题，少于 25 个字。
            - 用第二人称，直接对“你”说。
            - 挑一件具体的事来问。用户已经写了内容时，从用户写的内容里挑；否则从下面的情况里挑：做完的，或者没做、跳过的。具体的事比笼统地问这一天更好。
            - 只有上面的情况明确写了提前完成，才可以说“提前”或“早”。如果情况里写了困难的任务或 Epic 是提前完成的，可以问完成时是什么感觉。
            - 如果情况里列出某件事没做或跳过了，问是什么挡住了，不带责备。做完的事，或者用户写了自己做过的事，不要这样问。
            - 不给建议。
            - 不做诊断。
            - 不夸奖，也不让人内疚。
            - 不要提金币、分数或情况里的数字。
            - 已经列出的问题不要再问，相近的也不要。
            - 不要以“为什么”开头。
            - 不要问可以用“是”或“不是”回答的问题。
            - 不要复述情况，直接提问。
            - 不要用“不是……而是……”这类对比句式。
            - 不要用一句话收尾来重复要点。
            - 不要为了节奏凑三项并列；不要用破折号；不要用 markdown。
            """)
    }

    @Test func theLimitsTheInstructionsNameAreTheOnesAcceptEnforces() {
        #expect(JournalAsk.wordLimit == 15)
        #expect(JournalAsk.characterLimit == 25)
    }

    // MARK: the prompt

    /// A low day: a quest and a light-version routine done, an overdue routine given up on, and a
    /// quest and a routine still open.
    private func day() -> JournalSignals {
        let walk = F.quest("Walk")
        walk.points = 12
        let light = F.routineDone("Strength session")
        light.usedDegraded = true
        light.degradedTextSnapshot = "A 30 minute walk"
        light.awardedPoints = 20
        return F.signals(tier: .low,
                         quests: [walk, F.quest("Stretch", done: false)],
                         occurrences: [light, F.occurrence("Round two", due: "2026-09-17"),
                                       F.occurrence("Water the plants", due: "2026-09-18")])
    }

    private let entry = [
        "Long day.",
        "Q: What are you grateful for today?\nA: My sister.",
    ]

    @Test func theEnglishPromptCarriesTheFactsTheEntryAndTheEntrysQuestions() {
        let prompt = JournalPromptBuilder.prompt(
            language: .en, signals: day(), writing: entry.joined(separator: "\n\n"),
            existing: ["What are you grateful for today?"])
        #expect(prompt == """
            Write one question for the user's journal, about today.

            Facts about today:
            - Day type: low.
            - Done: Walk; A 30 minute walk (light version).
            - Skipped: Round two.
            - Not done yet: Stretch; Water the plants.

            What the user has written so far. Ask about one specific thing in it, not about the day in general:
            Long day.

            Q: What are you grateful for today?
            A: My sister.

            Questions already in this entry. Do not ask these again:
            - What are you grateful for today?
            """)
    }

    @Test func theChinesePromptCarriesTheSameThingsInChinese() {
        let prompt = JournalPromptBuilder.prompt(
            language: .zhHans, signals: day(), writing: "今天很累。",
            existing: ["今天你感恩什么？"])
        #expect(prompt == """
            为用户的日记写一个关于今天的问题。

            今天的情况：
            - 今天的精力：偏低。
            - 做完的：Walk；A 30 minute walk（轻量版）。
            - 跳过的：Round two。
            - 还没做的：Stretch；Water the plants。

            用户到目前为止写的。请只针对其中一件具体的事提问，不要笼统地问这一天：
            今天很累。

            这篇日记里已经有的问题，不要再问：
            - 今天你感恩什么？
            """)
    }

    @Test func aDayWithNothingInItSaysSoAndOmitsEveryEmptySection() {
        let prompt = JournalPromptBuilder.prompt(language: .en, signals: F.signals(), writing: nil, existing: [])
        #expect(prompt == """
            Write one question for the user's journal, about today.

            Facts about today:
            - Day type: normal.
            - Done: nothing.
            """)
    }

    @Test func noCoinsAppearInThePromptInEitherLanguage() {
        let signals = day()
        #expect(signals.coinsEarned == 32)
        for language in [JournalLanguage.en, .zhHans] {
            let prompt = JournalPromptBuilder.prompt(language: language, signals: signals, writing: nil, existing: [])
            #expect(!prompt.lowercased().contains("coin"), "\(language)")
            #expect(!prompt.contains("金币"), "\(language)")
            #expect(!prompt.contains("32"), "\(language)")
        }
    }

    /// The model invented "finished early" for a hard quest that was not early, so only a fact may say it.
    @Test func aHardQuestDoneOnItsOwnDayIsNotWordedAsEarlyOrAhead() {
        let hard = F.quest("Run 5 km")
        hard.slot = .hard
        hard.points = 40
        let prompt = JournalPromptBuilder.prompt(language: .en, signals: F.signals(quests: [hard]),
                                                 writing: nil, existing: [])
        #expect(prompt.hasSuffix("- Done: Run 5 km (hard)."))
        for word in ["early", "ahead", "before", "spare"] {
            #expect(!prompt.contains(word), "\(word)")
        }
    }

    /// A hard quest, a routine done before its day, and the week's epic finished two days early.
    @Test func hardWorkEarlyRoutinesAndAnEarlyEpicAreInTheFacts() {
        let hard = F.quest("Deep clean the kitchen")
        hard.slot = .hard
        hard.points = 40
        let ahead = F.routineDone("Laundry")
        ahead.dueDayKey = "2026-09-19"
        ahead.awardedPoints = 15
        let epic = F.quest("Write up a technical topic", on: "2026-09-14", hour: 9)
        epic.slot = .epic
        epic.points = 100
        epic.completedAt = Fixtures.date("2026-09-18", hour: 20)
        let signals = JournalSignals(dayKey: F.day, quests: [hard], occurrences: [ahead],
                                     context: F.context(tier: .normal), ratings: [],
                                     epic: epic, timeZone: Fixtures.tokyo)
        let english = JournalPromptBuilder.prompt(language: .en, signals: signals, writing: nil,
                                                  existing: [])
        #expect(english.hasSuffix("""
            - Done: Deep clean the kitchen (hard); Laundry (done before its day); Write up a technical topic (this week's epic).
            - This week's epic: Write up a technical topic. Finished today, 2 days before it was due.
            """))
        let chinese = JournalPromptBuilder.prompt(language: .zhHans, signals: signals, writing: nil,
                                                  existing: [])
        #expect(chinese.hasSuffix("""
            - 做完的：Deep clean the kitchen（困难）；Laundry（提前做的）；Write up a technical topic（本周的 Epic）。
            - 本周的 Epic：Write up a technical topic。今天完成了，比截止早 2 天。
            """))
    }

    /// An epic finished today is something done today: listing it apart under "Done: nothing" made
    /// the model ask what the day was like with nothing finished.
    @Test func anEpicFinishedTodayIsDoneEvenWhenNothingElseIs() {
        let epic = F.quest("Write up a technical topic", on: "2026-09-14", hour: 9)
        epic.slot = .epic
        epic.completedAt = Fixtures.date("2026-09-18", hour: 20)
        let signals = JournalSignals(dayKey: F.day, quests: [], occurrences: [], context: F.context(tier: .normal),
                                     ratings: [], epic: epic, timeZone: Fixtures.tokyo)
        let prompt = JournalPromptBuilder.prompt(language: .en, signals: signals, writing: nil, existing: [])
        #expect(prompt.hasSuffix("""
            - Done: Write up a technical topic (this week's epic).
            - This week's epic: Write up a technical topic. Finished today, 2 days before it was due.
            """))
        #expect(!prompt.contains("nothing"))
    }

    /// One finished earlier in the week was not done today.
    @Test func anEpicFinishedEarlierInTheWeekIsNotDoneToday() {
        let epic = F.quest("Write up a technical topic", on: "2026-09-14", hour: 9)
        epic.slot = .epic
        epic.completedAt = Fixtures.date("2026-09-16", hour: 20)
        let signals = JournalSignals(dayKey: F.day, quests: [], occurrences: [], context: F.context(tier: .normal),
                                     ratings: [], epic: epic, timeZone: Fixtures.tokyo)
        let prompt = JournalPromptBuilder.prompt(language: .en, signals: signals, writing: nil, existing: [])
        #expect(prompt.contains("- Done: nothing.\n- This week's epic: Write up a technical topic. Already finished earlier this week."))
    }

    @Test func anOpenEpicIsNotLeftOpenAndSaysHowManyDaysAreLeft() {
        let epic = F.quest("Write up a technical topic", on: "2026-09-14", done: false)
        epic.slot = .epic
        #expect(F.signals(quests: [epic], on: "2026-09-14").leftOpen.isEmpty)
        let prompt = JournalPromptBuilder.prompt(language: .en, signals: F.signals(quests: [epic], on: "2026-09-14"),
                                                 writing: nil, existing: [])
        #expect(prompt.hasSuffix("- This week's epic: Write up a technical topic. Not done yet, 6 days left."))
    }

    @Test func eachDayTypeHasItsOwnWordInBothLanguages() {
        let expected: [(Tier, String, String)] = [(.veryLow, "very low", "很低"), (.low, "low", "偏低"),
                                                  (.normal, "normal", "正常"), (.high, "high", "充沛")]
        for (tier, en, zh) in expected {
            let signals = F.signals(tier: tier)
            let english = JournalPromptBuilder.prompt(language: .en, signals: signals, writing: nil,
                                                      existing: [])
            let chinese = JournalPromptBuilder.prompt(language: .zhHans, signals: signals, writing: nil,
                                                      existing: [])
            #expect(english.contains("- Day type: \(en).\n"), "\(tier)")
            #expect(chinese.contains("- 今天的精力：\(zh)。\n"), "\(tier)")
        }
    }

    @Test func aLongEntryIsCutToItsLastCharactersWithAnEllipsis() {
        let long = String(repeating: "A", count: 2_000) + String(repeating: "B", count: JournalPromptBuilder.maxWritingCharacters)
        let prompt = JournalPromptBuilder.prompt(language: .en, signals: F.signals(), writing: long,
                                                 existing: [])
        #expect(JournalPromptBuilder.maxWritingCharacters == 1_500)
        #expect(prompt.hasSuffix("not about the day in general:\n\u{2026}" + String(repeating: "B", count: 1_500)))
        #expect(!prompt.contains("AAAA"))
    }

    @Test func anEntryThatFitsIsNotCut() {
        let exact = String(repeating: "B", count: 1_500)
        let prompt = JournalPromptBuilder.prompt(language: .en, signals: F.signals(), writing: exact,
                                                 existing: [])
        #expect(prompt.hasSuffix("in general:\n" + exact))
        #expect(!prompt.contains("\u{2026}"))
    }

    // MARK: the retry

    @Test func theEnglishRetryPromptsArePromptPlusOneSentencePinnedWhole() {
        #expect(JournalPromptBuilder.retryPrompt("THE PROMPT", rejected: "What did you think of the new album?",
                                                 reason: .notFresh, language: .en) == """
            THE PROMPT

            The question you just wrote, "What did you think of the new album?", is too close to one that was already asked. Ask about something else from the facts.
            """)
        #expect(JournalPromptBuilder.retryPrompt("THE PROMPT", rejected: "Did you enjoy cleaning the kitchen?",
                                                 reason: .closedQuestion, language: .en) == """
            THE PROMPT

            Your last question could be answered yes or no. Ask an open question that starts with What or How.
            """)
        #expect(JournalPromptBuilder.retryPrompt("THE PROMPT", rejected: "What was it like to finish the run early?",
                                                 reason: .unsupportedEarly, language: .en) == """
            THE PROMPT

            Your last question said something was early, but nothing in the facts was. Ask again without saying early or ahead.
            """)
        #expect(JournalPromptBuilder.retryPrompt("THE PROMPT", rejected: "What was the part of the long walk that felt best?",
                                                 reason: .tooLong, language: .en) == """
            THE PROMPT

            Your last question was too long. Ask one short question, under 15 words.
            """)
    }

    @Test func theChineseRetryPromptsArePromptPlusOneSentencePinnedWhole() {
        #expect(JournalPromptBuilder.retryPrompt("提示", rejected: "你觉得新专辑怎么样？", reason: .notFresh, language: .zhHans) == """
            提示

            你刚写的问题“你觉得新专辑怎么样？”和已经问过的太接近了。请从上面的情况里换一件事来问。
            """)
        #expect(JournalPromptBuilder.retryPrompt("提示", rejected: "你喜欢今天的散步吗？",
                                                 reason: .closedQuestion, language: .zhHans) == """
            提示

            你上一个问题可以用“是”或“不是”回答。请换一个开放式的问题，用“什么”或“怎么”来问。
            """)
        #expect(JournalPromptBuilder.retryPrompt("提示", rejected: "提前完成是什么感觉？",
                                                 reason: .unsupportedEarly, language: .zhHans) == """
            提示

            你上一个问题说某件事是提前的，但上面的情况里没有提前完成的事。请重新问，不要提“提前”或“提早”。
            """)
        #expect(JournalPromptBuilder.retryPrompt("提示", rejected: "今天的散步里让你觉得最舒服的那一段是什么样的呢？",
                                                 reason: .tooLong, language: .zhHans) == """
            提示

            你上一个问题太长了。请只问一个短问题，少于 25 个字。
            """)
    }

    /// The model handed a quoted question straight back, so these two sentences do not show it.
    @Test func theClosedAndTooLongSentencesDoNotQuoteTheRejectedText() {
        for language in JournalLanguage.allCases {
            for reason in [JournalPromptBuilder.RetryReason.closedQuestion, .tooLong] {
                let again = JournalPromptBuilder.retryPrompt("P", rejected: "UNIQUE REJECTED TEXT?", reason: reason,
                                                             language: language)
                #expect(!again.contains("UNIQUE"), "\(language) \(reason)")
            }
        }
    }

    // MARK: the entry as text

    @Test func promptsReadAsQAndAAndTextsAsTheyAre() {
        let doc = E.doc(E.text(1, "Long day."),
                        E.prompt(2, "What are you grateful for today?", answer: "My sister.", source: .fixed, key: .gratefulFor),
                        E.prompt(3, "What did the walk give you?", answer: "", source: .llm),
                        E.text(4, "  \n"))
        #expect(JournalPromptBuilder.writing(of: doc) == """
            Long day.

            Q: What are you grateful for today?
            A: My sister.

            Q: What did the walk give you?
            A:
            """)
    }

    @Test func anEntryWithNothingWrittenIsNil() {
        #expect(JournalPromptBuilder.writing(of: JournalDocument()) == nil)
        #expect(JournalPromptBuilder.writing(of: E.doc(E.text(1, " \n "))) == nil)
        #expect(JournalPromptBuilder.writing(of: E.doc(E.prompt(1, "What did the walk give you?"))) == nil)
    }
}
