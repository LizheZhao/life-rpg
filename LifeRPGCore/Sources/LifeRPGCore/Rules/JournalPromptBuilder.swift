import Foundation

/// The text handed to the on-device model, written here so the rules it is held to exist in one
/// place. `JournalTextCheck` afterwards enforces only the ones a pattern can catch.
public enum JournalPromptBuilder {
    /// One hand-written rule, in both languages. `JournalPromptBuilderTests` pins the wording of
    /// each, because a softened rule is the failure nobody notices until the voice drifts.
    struct Rule {
        let en: String
        let zh: String
        /// A rule about quoting what the user wrote, which a fresh question has none of.
        var followUpOnly = false
    }

    static let rules: [Rule] = [
        Rule(en: "Ask one question at a time.", zh: "一次只问一个问题。"),
        Rule(en: "Give no advice.", zh: "不给建议。"),
        Rule(en: "Make no diagnosis.", zh: "不做诊断。"),
        Rule(en: "Never start with why; ask what got in the way, or what it was like.",
             zh: "不要以“为什么”开头；问是什么挡了一下，或者当时是什么样的。"),
        Rule(en: "No praise or guilt. The app already tracks points, so do not add to it.",
             zh: "不夸奖，也不让人内疚。分数的事应用已经记着，不要再多说。"),
        Rule(en: "Reuse the user's own words; do not rephrase them into something fancier. Quote only a few words, never the whole answer.",
             zh: "沿用用户自己的话，不要改写成更漂亮的说法。只引用其中几个字，不要整段照抄。", followUpOnly: true),
        Rule(en: "No contrast staging such as \"not X, but Y\".",
             zh: "不要用“不是……而是……”这类对比句式。"),
        Rule(en: "No closing one-liner that repeats the point.", zh: "不要用一句话收尾来重复要点。"),
        Rule(en: "No triads for rhythm; no long dashes; no markdown.",
             zh: "不要为了节奏凑三项并列；不要用破折号；不要用 markdown。"),
        Rule(en: "Examples are anchors for tone, not templates; never reuse their wording or sentence structure.",
             zh: "示例只是语气的参照，不是模板；不要沿用它们的措辞和句式。"),
    ]

    /// How many of the recent questions the prompt lists. `JournalTextCheck.acceptQuestion` is
    /// held against all of them; the model only needs the newest to see what to stay away from,
    /// and a small context window has no room for two weeks of them.
    public static let maxAvoidInPrompt = 10

    public static func instructions(language: JournalLanguage) -> String {
        switch language {
        case .en:
            return "You help someone write a short end-of-day journal. Reply with one short reflection that quotes a few of their words exactly, then one question.\n"
                + rules.map { "- " + $0.en }.joined(separator: "\n")
        case .zhHans:
            return "你在帮用户写一篇简短的睡前日记。回复一句简短的回应，原样引用用户说过的几个字，然后问一个问题。\n"
                + rules.map { "- " + $0.zh }.joined(separator: "\n")
        }
    }

    /// The instructions for wording a fresh question from a brief: the same rules as a follow-up
    /// without the one about quoting the user, since there is nothing of theirs to quote.
    public static func questionInstructions(language: JournalLanguage) -> String {
        let kept = rules.filter { !$0.followUpOnly }
        switch language {
        case .en:
            return "You help someone write a short end-of-day journal. Reply with one short, fresh question and nothing else.\n"
                + kept.map { "- " + $0.en }.joined(separator: "\n")
        case .zhHans:
            return "你在帮用户写一篇简短的睡前日记。只回复一个简短、新鲜的问题，不要说别的。\n"
                + kept.map { "- " + $0.zh }.joined(separator: "\n")
        }
    }

    /// The prompt for one follow-up. It carries the day's facts, the one question and answer being
    /// followed up and the style hint, and nothing else the user wrote: the request holds only that
    /// turn. The follow-up examples and recent questions follow when the request has them.
    public static func followUpPrompt(_ request: JournalFollowUpRequest,
                                      signals: JournalSignals,
                                      habits: JournalHabits) -> String {
        let language = request.language
        var facts = dayFacts(signals, language: language)
        switch language {
        case .en:
            if let subject = request.subject { facts.append("The question was about: \(subject.text).") }
            facts += ["The user was asked: \(request.question)",
                      "The user answered: \(request.answer)",
                      habits.styleHint(language: language)]
        case .zhHans:
            if let subject = request.subject { facts.append("这个问题问的是：\(subject.text)。") }
            facts += ["用户被问到：\(request.question)",
                      "用户回答：\(request.answer)",
                      habits.styleHint(language: language)]
        }
        return bullets(heading(language), facts)
            + anchorSections(examples: request.examples, avoid: request.avoid, language: language)
    }

    /// The prompt for wording one fresh question: what to ask about and in what shape, the day's
    /// facts, the pool rows as tone anchors, and the recent questions to stay away from. Nil for a
    /// question without a brief (a template follow-up), which the model is never asked to reword.
    /// Only the examples and recent questions the brief carries appear, so nothing the user wrote
    /// can reach the model through it.
    public static func questionPrompt(_ question: JournalQuestion,
                                      signals: JournalSignals,
                                      habits: JournalHabits) -> String? {
        guard let brief = question.brief else { return nil }
        let language = brief.language
        var facts = dayFacts(signals, language: language)
        switch language {
        case .en:
            if let subject = question.subject { facts.append("The question is about: \(subject.text).") }
            if brief.facts.hasPhotoItem { facts.append("Something done today involved taking a photo.") }
            if brief.facts.hasChoiceItem { facts.append("Something done today involved choosing or noticing.") }
            if brief.facts.hasSkippedItem { facts.append("A routine was left undone.") }
            facts.append(habits.styleHint(language: language))
            return "Write one new question for the user's journal.\n"
                + "To ask: \(intent(question.kind, language))\n"
                + "Shape: \(shape(brief.approach, language))\n"
                + bullets(heading(language), facts)
                + anchorSections(examples: brief.examples, avoid: brief.avoid, language: language)
        case .zhHans:
            if let subject = question.subject { facts.append("这个问题问的是：\(subject.text)。") }
            if brief.facts.hasPhotoItem { facts.append("今天做过的事里有拍照。") }
            if brief.facts.hasChoiceItem { facts.append("今天做过的事里有选择或留意。") }
            if brief.facts.hasSkippedItem { facts.append("有一件例行的事没有做。") }
            facts.append(habits.styleHint(language: language))
            return "为用户的日记写一个新的问题。\n"
                + "要问的：\(intent(question.kind, language))\n"
                + "问法：\(shape(brief.approach, language))\n"
                + bullets(heading(language), facts)
                + anchorSections(examples: brief.examples, avoid: brief.avoid, language: language)
        }
    }

    private static func heading(_ language: JournalLanguage) -> String {
        language == .zhHans ? "这一天的情况：" : "Facts about the day:"
    }

    private static func bullets(_ heading: String, _ lines: [String]) -> String {
        heading + "\n" + lines.map { "- " + $0 }.joined(separator: "\n")
    }

    /// Tier, count and mean rating, worded the same in every prompt so the model reads one format.
    private static func dayFacts(_ signals: JournalSignals, language: JournalLanguage) -> [String] {
        switch language {
        case .en:
            var facts = ["Energy tier: \(signals.tier.rawValue).", "Things done: \(signals.completedCount)."]
            if let average = signals.averageRating {
                facts.append("Average rating: \(String(format: "%.1f", average)) on a scale of -2 to 2.")
            }
            return facts
        case .zhHans:
            var facts = ["精力档位：\(signals.tier.rawValue)。", "完成的事：\(signals.completedCount) 件。"]
            if let average = signals.averageRating {
                facts.append("平均评分：\(String(format: "%.1f", average))（范围 -2 到 2）。")
            }
            return facts
        }
    }

    /// The two lists after the facts, each left out when empty. The examples carry their own
    /// warning in the heading: they are anchors for tone, and the model is told what copying is.
    private static func anchorSections(examples: [JournalExample], avoid: [String],
                                       language: JournalLanguage) -> String {
        var out = ""
        if !examples.isEmpty {
            let heading = language == .zhHans
                ? "示例，只用来参考语气，不要沿用它们的措辞和句式："
                : "Examples. They show the tone only; do not reuse their wording or sentence structure:"
            out += "\n\n" + bullets(heading, examples.map(\.text))
        }
        if !avoid.isEmpty {
            let heading = language == .zhHans
                ? "最近问过的问题，不要问得相似："
                : "Recently asked. Do not ask anything like these:"
            out += "\n\n" + bullets(heading, Array(avoid.prefix(maxAvoidInPrompt)))
        }
        return out
    }

    private static func intent(_ kind: JournalPromptKind, _ language: JournalLanguage) -> String {
        switch (kind, language) {
        case (.opening, .en): "a question about the day as a whole."
        case (.heavy, .en): "a gentle question about a day that felt heavy."
        case (.good, .en): "a question about a moment that went well."
        case (.choice, .en): "a question about something the user chose or noticed."
        case (.skip, .en): "a question about something that did not get done, with no blame."
        case (.closing, .en): "a closing question before the day ends."
        case (.followUp, .en), (.safety, .en): "one question about the day."
        case (.opening, .zhHans): "关于这一整天的问题。"
        case (.heavy, .zhHans): "关于感觉沉重的一天的温和问题。"
        case (.good, .zhHans): "关于一个进行得不错的时刻的问题。"
        case (.choice, .zhHans): "关于用户选过或留意到的事的问题。"
        case (.skip, .zhHans): "关于没做成的事的问题，不带责备。"
        case (.closing, .zhHans): "结束这一天之前的收尾问题。"
        case (.followUp, .zhHans), (.safety, .zhHans): "关于这一天的一个问题。"
        }
    }

    private static func shape(_ approach: JournalApproach, _ language: JournalLanguage) -> String {
        switch (approach, language) {
        case (.scale, .en): "ask them to place something on a scale, then what keeps it from being lower."
        case (.selfCompassion, .en): "separate how it felt from what happened, with kindness toward themselves."
        case (.savoring, .en): "stay with a good moment and what made it good."
        case (.values, .en): "ask what matters to them in this."
        case (.exceptions, .en): "look for a time it went better, or the smallest step that would make it easier."
        case (.reflection, .en): "reflect back what they said, then ask one thing about it."
        case (.open, .en): "a plain open question with no particular technique."
        case (.scale, .zhHans): "请他给某件事打个分，再问是什么没让它更低。"
        case (.selfCompassion, .zhHans): "把感受和事实分开，对自己温和一点。"
        case (.savoring, .zhHans): "停在一个好的时刻上，问是什么让它变好。"
        case (.values, .zhHans): "问这件事里他在意什么。"
        case (.exceptions, .zhHans): "找一次进行得更顺的时候，或者最小的一步让它更容易。"
        case (.reflection, .zhHans): "先复述他说过的话，再就此问一件事。"
        case (.open, .zhHans): "一个朴素的开放式问题，不用特别的技巧。"
        }
    }
}
