import Foundation

/// Whether an answer calls for the safety line (`JournalPool` row `safety`) instead of a follow-up.
///
/// A keyword list, deliberately blunt. A missed signal costs far more than a gentle line shown by
/// mistake, so the lists lean towards matching. Both languages are always checked whatever the app
/// language is: people write in the language they feel in.
public enum JournalSafety {
    /// The one table. Matched against the lowercased answer with curly apostrophes straightened
    /// and runs of whitespace collapsed, so entries are written in that form.
    static let phrases: [String] = [
        // Self-harm, English.
        "kill myself", "killing myself", "suicide", "suicidal", "end my life", "ending my life",
        "take my own life", "want to die", "wanna die", "wish i were dead", "wish i was dead",
        "better off dead", "hurt myself", "hurting myself", "harm myself", "self-harm", "self harm",
        "cut myself", "cutting myself", "don't want to be here anymore", "don't want to exist",
        // Hopelessness, English.
        "hopeless", "no way out", "no reason to live", "not worth living", "no point in living",
        "can't go on", "cannot go on", "can't do this anymore", "give up on life", "nothing matters",
        "end it all",
        // Self-harm, Chinese.
        "自杀", "轻生", "不想活", "不想再活", "想死", "去死", "寻死", "结束生命", "结束自己",
        "了结自己", "一了百了", "死了算了", "自残", "伤害自己", "割腕", "想消失",
        // Hopelessness, Chinese.
        "绝望", "没有希望", "没希望了", "撑不下去", "活不下去", "活着没意思", "活着没有意义",
        "没有出路", "看不到出路", "没有意义了",
    ]

    /// The text of the safety line, from the pool like every other question.
    public static func line(language: JournalLanguage) -> String {
        JournalPool.prompt(id: "safety")?.text(in: language) ?? ""
    }

    public static func needsSafetyLine(answer: String) -> Bool {
        let text = normalized(answer)
        return phrases.contains(where: text.contains)
    }

    private static func normalized(_ answer: String) -> String {
        answer.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
