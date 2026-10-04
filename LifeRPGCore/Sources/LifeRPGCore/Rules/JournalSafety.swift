import Foundation

/// Whether an answer calls for the safety line (`JournalPool` row `safety`) instead of a follow-up.
///
/// A keyword list, deliberately blunt. A missed signal costs far more than a gentle line shown by
/// mistake, so the lists lean towards matching. Both languages are always checked whatever the app
/// language is: people write in the language they feel in.
public enum JournalSafety {
    public enum Category: String, CaseIterable, Sendable {
        case selfHarm, hopelessness
    }

    /// The one table. Matched against the lowercased answer with curly apostrophes straightened
    /// and runs of whitespace collapsed, so entries are written in that form.
    static let terms: [(category: Category, language: JournalLanguage, phrases: [String])] = [
        (.selfHarm, .en, [
            "kill myself", "killing myself", "suicide", "suicidal", "end my life", "ending my life",
            "take my own life", "want to die", "wanna die", "wish i were dead", "wish i was dead",
            "better off dead", "hurt myself", "hurting myself", "harm myself", "self-harm", "self harm",
            "cut myself", "cutting myself", "don't want to be here anymore", "don't want to exist",
        ]),
        (.hopelessness, .en, [
            "hopeless", "no way out", "no reason to live", "not worth living", "no point in living",
            "can't go on", "cannot go on", "can't do this anymore", "give up on life", "nothing matters",
            "end it all",
        ]),
        (.selfHarm, .zhHans, [
            "自杀", "轻生", "不想活", "不想再活", "想死", "去死", "寻死", "结束生命", "结束自己",
            "了结自己", "一了百了", "死了算了", "自残", "伤害自己", "割腕", "想消失",
        ]),
        (.hopelessness, .zhHans, [
            "绝望", "没有希望", "没希望了", "撑不下去", "活不下去", "活着没意思", "活着没有意义",
            "没有出路", "看不到出路", "没有意义了",
        ]),
    ]

    /// The text of the safety line, from the pool like every other question.
    public static func line(language: JournalLanguage) -> String {
        JournalPool.prompt(id: "safety")?.text(in: language) ?? ""
    }

    public static func needsSafetyLine(answer: String) -> Bool {
        !categories(in: answer).isEmpty
    }

    /// Which lists matched, for a caller that wants to say more than "yes".
    public static func categories(in answer: String) -> Set<Category> {
        let text = normalized(answer)
        var found = Set<Category>()
        for entry in terms where entry.phrases.contains(where: text.contains) {
            found.insert(entry.category)
        }
        return found
    }

    private static func normalized(_ answer: String) -> String {
        answer.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
