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
            - Pick one specific thing from the facts below: something done, something not done or skipped, or something finished ahead of time. A specific thing beats a general question about the day.
            - When something hard or the epic was finished early, you may ask what finishing it felt like.
            - When something was not done or skipped, ask what got in the way, without blame.
            - Give no advice.
            - Make no diagnosis.
            - No praise or guilt. The app already tracks coins, so do not add to it.
            - Never ask a question that is already listed, or one close to it.
            - Never start with why; ask what got in the way, or what it was like.
            - No contrast staging such as "not X, but Y".
            - No closing one-liner that repeats the point.
            - No triads for rhythm; no long dashes; no markdown.
            - Examples show tone only; never reuse their wording or sentence structure.
            """)
    }

    @Test func theChineseInstructionsArePinnedWhole() {
        #expect(JournalPromptBuilder.instructions(language: .zhHans) == """
            你在帮用户写一篇简短的睡前日记。用户点一下按钮，你给出一个可以写一写的问题。只回复这个问题，用纯文本。
            - 只问一个问题，少于 25 个字。
            - 用第二人称，直接对“你”说。
            - 从下面的情况里挑一件具体的事来问：做完的、没做或跳过的、或者提前完成的。具体的事比笼统地问这一天更好。
            - 如果提前完成了困难的任务或 Epic，可以问完成时是什么感觉。
            - 如果有事没做或跳过了，问是什么挡住了，不带责备。
            - 不给建议。
            - 不做诊断。
            - 不夸奖，也不让人内疚。金币的事应用已经记着，不要再多说。
            - 已经列出的问题不要再问，相近的也不要。
            - 不要以“为什么”开头；问是什么挡了一下，或者当时是什么样的。
            - 不要用“不是……而是……”这类对比句式。
            - 不要用一句话收尾来重复要点。
            - 不要为了节奏凑三项并列；不要用破折号；不要用 markdown。
            - 示例只是语气的参照；不要沿用它们的措辞和句式。
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

    @Test func theEnglishPromptCarriesTheFactsTheEntryAndTheLists() {
        let prompt = JournalPromptBuilder.prompt(
            language: .en, signals: day(), writing: entry.joined(separator: "\n\n"),
            existing: ["What are you grateful for today?"],
            recent: ["What did you notice yesterday?"],
            anchors: ["If a friend had a day like this, what would you say to them?"])
        #expect(prompt == """
            Write one question for the user's journal, about today.

            Facts about today:
            - Day type: low.
            - Coins earned: 32.
            - Done: Walk (+12 coins); A 30 minute walk (light version, +20 coins).
            - Skipped: Round two.
            - Not done yet: Stretch; Water the plants.

            What the user has written so far:
            Long day.

            Q: What are you grateful for today?
            A: My sister.

            Questions already in this entry. Do not ask these again:
            - What are you grateful for today?

            Questions from recent entries. Do not ask anything like these:
            - What did you notice yesterday?

            Examples. They show the tone only; do not reuse their wording or sentence structure:
            - If a friend had a day like this, what would you say to them?
            """)
    }

    @Test func theChinesePromptCarriesTheSameThingsInChinese() {
        let prompt = JournalPromptBuilder.prompt(
            language: .zhHans, signals: day(), writing: "今天很累。",
            existing: ["今天你感恩什么？"], recent: ["昨天你注意到了什么？"],
            anchors: ["如果朋友过了这样的一天，你会对他说什么？"])
        #expect(prompt == """
            为用户的日记写一个关于今天的问题。

            今天的情况：
            - 今天的精力：偏低。
            - 赚到的金币：32。
            - 做完的：Walk（+12 金币）；A 30 minute walk（轻量版，+20 金币）。
            - 跳过的：Round two。
            - 还没做的：Stretch；Water the plants。

            用户到目前为止写的：
            今天很累。

            这篇日记里已经有的问题，不要再问：
            - 今天你感恩什么？

            最近几篇日记里的问题，不要问得相似：
            - 昨天你注意到了什么？

            示例，只用来参考语气，不要沿用它们的措辞和句式：
            - 如果朋友过了这样的一天，你会对他说什么？
            """)
    }

    @Test func aDayWithNothingInItSaysSoAndOmitsEveryEmptySection() {
        let prompt = JournalPromptBuilder.prompt(language: .en, signals: F.signals(), writing: nil,
                                                 existing: [], recent: [], anchors: [])
        #expect(prompt == """
            Write one question for the user's journal, about today.

            Facts about today:
            - Day type: normal.
            - Coins earned: 0.
            - Done: nothing.
            """)
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
                                                  existing: [], recent: [], anchors: [])
        #expect(english.hasSuffix("""
            - Coins earned: 155.
            - Done: Deep clean the kitchen (hard, +40 coins); Laundry (done before its day, +15 coins).
            - This week's epic: Write up a technical topic. Finished today, 2 days before it was due.
            """))
        let chinese = JournalPromptBuilder.prompt(language: .zhHans, signals: signals, writing: nil,
                                                  existing: [], recent: [], anchors: [])
        #expect(chinese.hasSuffix("""
            - 做完的：Deep clean the kitchen（困难，+40 金币）；Laundry（提前做的，+15 金币）。
            - 本周的 Epic：Write up a technical topic。今天完成了，比截止早 2 天。
            """))
    }

    @Test func anOpenEpicIsNotLeftOpenAndSaysHowManyDaysAreLeft() {
        let epic = F.quest("Write up a technical topic", on: "2026-09-14", done: false)
        epic.slot = .epic
        #expect(F.signals(quests: [epic], on: "2026-09-14").leftOpen.isEmpty)
        let prompt = JournalPromptBuilder.prompt(language: .en, signals: F.signals(quests: [epic], on: "2026-09-14"),
                                                 writing: nil, existing: [], recent: [], anchors: [])
        #expect(prompt.hasSuffix("- This week's epic: Write up a technical topic. Not done yet, 6 days left."))
    }

    @Test func eachDayTypeHasItsOwnWordInBothLanguages() {
        let expected: [(Tier, String, String)] = [(.veryLow, "very low", "很低"), (.low, "low", "偏低"),
                                                  (.normal, "normal", "正常"), (.high, "high", "充沛")]
        for (tier, en, zh) in expected {
            let signals = F.signals(tier: tier)
            let english = JournalPromptBuilder.prompt(language: .en, signals: signals, writing: nil,
                                                      existing: [], recent: [], anchors: [])
            let chinese = JournalPromptBuilder.prompt(language: .zhHans, signals: signals, writing: nil,
                                                      existing: [], recent: [], anchors: [])
            #expect(english.contains("- Day type: \(en).\n"), "\(tier)")
            #expect(chinese.contains("- 今天的精力：\(zh)。\n"), "\(tier)")
        }
    }

    @Test func aLongEntryIsCutToItsLastCharactersWithAnEllipsis() {
        let long = String(repeating: "A", count: 2_000) + String(repeating: "B", count: JournalPromptBuilder.maxWritingCharacters)
        let prompt = JournalPromptBuilder.prompt(language: .en, signals: F.signals(), writing: long,
                                                 existing: [], recent: [], anchors: [])
        #expect(JournalPromptBuilder.maxWritingCharacters == 1_500)
        #expect(prompt.hasSuffix("What the user has written so far:\n\u{2026}" + String(repeating: "B", count: 1_500)))
        #expect(!prompt.contains("AAAA"))
    }

    @Test func anEntryThatFitsIsNotCut() {
        let exact = String(repeating: "B", count: 1_500)
        let prompt = JournalPromptBuilder.prompt(language: .en, signals: F.signals(), writing: exact,
                                                 existing: [], recent: [], anchors: [])
        #expect(prompt.hasSuffix("written so far:\n" + exact))
        #expect(!prompt.contains("\u{2026}"))
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
