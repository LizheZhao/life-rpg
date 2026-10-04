import Foundation

/// The text handed to the on-device model, written here so the rules it is held to exist in one
/// place and are the same ones `JournalTextCheck` enforces afterwards.
public enum JournalPromptBuilder {
    /// One hand-written rule, in both languages. `JournalPromptBuilderTests` pins the wording of
    /// each, because a softened rule is the failure nobody notices until the voice drifts.
    struct Rule {
        let en: String
        let zh: String
    }

    static let rules: [Rule] = [
        Rule(en: "Ask one question at a time.", zh: "一次只问一个问题。"),
        Rule(en: "Give no advice.", zh: "不给建议。"),
        Rule(en: "Make no diagnosis.", zh: "不做诊断。"),
        Rule(en: "Never start with why; ask what got in the way, or what it was like.",
             zh: "不要以“为什么”开头；问是什么挡了一下，或者当时是什么样的。"),
        Rule(en: "No praise or guilt. The app already tracks points, so do not add to it.",
             zh: "不夸奖，也不让人内疚。分数的事应用已经记着，不要再多说。"),
        Rule(en: "Reuse the user's own words; do not rephrase them into something fancier.",
             zh: "沿用用户自己的话，不要改写成更漂亮的说法。"),
        Rule(en: "No contrast staging such as \"not X, but Y\".",
             zh: "不要用“不是……而是……”这类对比句式。"),
        Rule(en: "No closing one-liner that repeats the point.", zh: "不要用一句话收尾来重复要点。"),
        Rule(en: "No triads for rhythm; no long dashes; no markdown.",
             zh: "不要为了节奏凑三项并列；不要用破折号；不要用 markdown。"),
    ]

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

    /// The prompt for one follow-up. It carries the day's facts, the one question and answer being
    /// followed up and the style hint, and nothing else the user wrote: the request holds only that turn.
    public static func followUpPrompt(_ request: JournalFollowUpRequest,
                                      signals: JournalSignals,
                                      habits: JournalHabits) -> String {
        let language = request.language
        var facts: [String]
        switch language {
        case .en:
            facts = ["Energy tier: \(signals.tier.rawValue).", "Things done: \(signals.completedCount)."]
            if let average = signals.averageRating {
                facts.append("Average rating: \(String(format: "%.1f", average)) on a scale of -2 to 2.")
            }
            if let subject = request.subject { facts.append("The question was about: \(subject.text).") }
            facts += ["The user was asked: \(request.question)",
                      "The user answered: \(request.answer)",
                      habits.styleHint(language: language)]
            return "Facts about the day:\n" + facts.map { "- " + $0 }.joined(separator: "\n")
        case .zhHans:
            facts = ["精力档位：\(signals.tier.rawValue)。", "完成的事：\(signals.completedCount) 件。"]
            if let average = signals.averageRating {
                facts.append("平均评分：\(String(format: "%.1f", average))（范围 -2 到 2）。")
            }
            if let subject = request.subject { facts.append("这个问题问的是：\(subject.text)。") }
            facts += ["用户被问到：\(request.question)",
                      "用户回答：\(request.answer)",
                      habits.styleHint(language: language)]
            return "这一天的情况：\n" + facts.map { "- " + $0 }.joined(separator: "\n")
        }
    }
}
