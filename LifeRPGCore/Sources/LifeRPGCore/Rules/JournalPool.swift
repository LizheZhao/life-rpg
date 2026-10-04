import Foundation

/// A question the journal can ask, in both languages. The wording is `doc/JOURNAL_PROMPTS.md`.
public struct JournalPrompt: Equatable, Sendable {
    public let id: String
    public let kind: JournalPromptKind
    public let en: String
    public let zh: String

    public func text(in language: JournalLanguage) -> String {
        language == .zhHans ? zh : en
    }
}

/// What a `{placeholder}` in a pool row stands for.
public enum JournalPlaceholder: String, CaseIterable, Sendable {
    /// The quest or routine text.
    case quest
    /// What the user chose: the quest's `variantSnapshot`.
    case item
    /// A short quote from the user's last answer.
    case phrase
}

/// The question pool: the only source of question wording that does not come from the model.
///
/// A table rather than code, so a wording change is one edited row. Every row is also what the
/// model is checked against (`JournalTextCheck`), and the fallback when it is unavailable.
public enum JournalPool {
    public static let all: [JournalPrompt] = [
        .init(id: "open.scale", kind: .opening,
              en: "If today were a number from 1 to 10, what would it be? What kept it from being lower?",
              zh: "如果给今天打 1 到 10 分，你会打几分？是什么没让它更低？"),
        .init(id: "open.feel", kind: .opening,
              en: "The day is almost over. How do you feel right now?",
              zh: "这一天快结束了，你现在感觉怎么样？"),
        .init(id: "open.keep", kind: .opening,
              en: "What from today do you want to remember?",
              zh: "今天有什么事，你想记住？"),

        .init(id: "heavy.done", kind: .heavy,
              en: "You got a lot done today, and it doesn't sound like it felt good. What was it like?",
              zh: "今天你做了不少事，但听起来感觉并不好。当时是什么样的？"),
        .init(id: "heavy.weight", kind: .heavy,
              en: "Where did the day weigh on you most, in your body or in your mood?",
              zh: "这一天压在你身上最重的地方在哪，是身体还是情绪？"),
        .init(id: "heavy.friend", kind: .heavy,
              en: "If a friend had a day like this, what would you say to them?",
              zh: "如果朋友过了这样的一天，你会对他说什么？"),
        .init(id: "heavy.body", kind: .heavy,
              en: "Your body had less to give today. What did it ask for?",
              zh: "今天身体能给的比平时少。它想要什么？"),

        .init(id: "good.moment", kind: .good,
              en: "You rated {quest} high. Which moment was the best part?",
              zh: "你给「{quest}」打了高分。哪一刻最好？"),
        .init(id: "good.repeat", kind: .good,
              en: "If you did {quest} again, what would you keep exactly the same?",
              zh: "如果再做一次「{quest}」，你想原样保留什么？"),
        .init(id: "good.who", kind: .good,
              en: "Who or what made it better?",
              zh: "是谁或是什么让它变得更好？"),

        .init(id: "choice.photo", kind: .choice,
              en: "Of the photos you took, which is your favorite? What pulled you to it?",
              zh: "你拍的照片里，最喜欢哪一张？它哪里吸引了你？"),
        .init(id: "choice.item", kind: .choice,
              en: "You picked {item}. What made it the one?",
              zh: "你选了{item}。是什么让它成为那个？"),
        .init(id: "choice.notice", kind: .choice,
              en: "What did you notice today that you would normally walk past?",
              zh: "今天你注意到了什么，是平时会直接走过的？"),

        .init(id: "skip.block", kind: .skip,
              en: "{quest} didn't happen. What got in the way?",
              zh: "「{quest}」没做成。是什么挡了一下？"),
        .init(id: "skip.exception", kind: .skip,
              en: "Was there a recent time this went more easily? What was different then?",
              zh: "最近有没有哪次做这件事比较顺？那次有什么不一样？"),
        .init(id: "skip.small", kind: .skip,
              en: "What would make it 10% easier tomorrow?",
              zh: "怎样能让它明天容易一成？"),

        .init(id: "follow.stand", kind: .followUp,
              en: "You said \"{phrase}\". What stands out to you about that?",
              zh: "你说到「{phrase}」。关于这一点，你最在意的是什么？"),
        .init(id: "follow.more", kind: .followUp,
              en: "Say more about \"{phrase}\".",
              zh: "再多说一点「{phrase}」吧。"),
        .init(id: "follow.need", kind: .followUp,
              en: "What does \"{phrase}\" tell you about what you need right now?",
              zh: "「{phrase}」让你看到自己现在需要什么？"),

        .init(id: "close.more", kind: .closing,
              en: "Anything else you want to put down before you close the day?",
              zh: "合上今天之前，还有什么想写下来的吗？"),
        .init(id: "close.carry", kind: .closing,
              en: "Is there one thing you want to carry into tomorrow?",
              zh: "有没有一件事，你想带进明天？"),

        .init(id: "safety", kind: .safety,
              en: "That sounds heavy. This is only a journaling tool and can't help the way a person can. If you might hurt yourself, please reach out to someone you trust or a local crisis line.",
              zh: "听起来很沉重。这只是个记日记的工具，帮不上真人能帮的忙。如果你有可能伤害自己，请联系信任的人，或当地的危机求助热线。"),
    ]

    private static let byID: [String: JournalPrompt] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func prompt(id: String) -> JournalPrompt? { byID[id] }

    public static func prompts(of kind: JournalPromptKind) -> [JournalPrompt] {
        all.filter { $0.kind == kind }
    }

    /// The placeholders a row's text asks for, in either language. Rows carry the same set in both.
    public static func placeholders(in text: String) -> Set<JournalPlaceholder> {
        var found = Set<JournalPlaceholder>()
        for placeholder in JournalPlaceholder.allCases where text.contains("{\(placeholder.rawValue)}") {
            found.insert(placeholder)
        }
        return found
    }

    /// The row with its placeholders filled, or nil when a fill is missing or blank, so a raw
    /// `{quest}` can never reach the screen. Substitution is a single pass over the row, so a fill
    /// that itself contains braces is inserted as text and never read as a placeholder.
    public static func render(id: String, language: JournalLanguage,
                              fills: [JournalPlaceholder: String] = [:]) -> String? {
        guard let prompt = prompt(id: id) else { return nil }
        return render(template: prompt.text(in: language), fills: fills)
    }

    static func render(template: String, fills: [JournalPlaceholder: String]) -> String? {
        var out = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            out += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}") else { return nil }
            let name = rest[rest.index(after: open)..<close]
            guard let placeholder = JournalPlaceholder(rawValue: String(name)),
                  let fill = fills[placeholder], !fill.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            out += fill
            rest = rest[rest.index(after: close)...]
        }
        return out + rest
    }
}
