import Foundation

/// Which hand-drawn icon a thing wears. Chosen from a quest's text, never stored: a stored key
/// would be a schema change (`SchemaV4`) for something the text already says.
public enum DoodleKey: String, CaseIterable, Sendable {
    case avatar, sneaker, potion, braces, notebook, dumbbell, paperPlane, trendLine, flag, sparkle

    /// A plain keyword matches a whole word (or its plural); a trailing `*` matches any word that
    /// starts with it; several words in one keyword (`"apply to"`) must follow each other. The
    /// first entry that matches wins, so the narrow, specific ones come before the broad ones.
    /// `avatar` and `flag` are placed by the layout and have no keywords.
    static let table: [(key: DoodleKey, keywords: [String])] = [
        (.braces, ["code", "coding", "leetcode", "debug*", "ship", "problem", "interview", "algorithm*"]),
        (.trendLine, ["trade", "trading", "chart", "stock", "bill", "statement", "budget", "numbers",
                      "credit card", "metric", "finance"]),
        (.paperPlane, ["email", "mail", "message", "send", "sent", "reply", "application", "apply to",
                       "call", "invite", "thank"]),
        (.sneaker, ["walk*", "run*", "jog*", "step", "hike", "bike", "cardio"]),
        (.dumbbell, ["lift*", "gym", "strength training", "weight*", "dumbbell*", "workout*", "stretch*",
                     "mobility", "exercise*", "massage"]),
        (.notebook, ["journal", "write", "writing", "reflect*", "note", "dream", "read", "reading",
                     "book", "paper", "summary", "draft", "diary", "learn", "study"]),
        (.sparkle, ["clean*", "tidy", "tidying", "declutter", "trash", "sort"]),
        (.potion, ["project", "experiment", "water", "drink", "tea", "cocktail", "cook*", "soak", "brew"]),
    ]

    public static func forText(_ text: String) -> DoodleKey {
        let words = text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        for entry in table where entry.keywords.contains(where: { matches($0, words) }) {
            return entry.key
        }
        return .sparkle
    }

    private static func matches(_ keyword: String, _ words: [String]) -> Bool {
        let parts = keyword.split(separator: " ").map(String.init)
        guard parts.count <= words.count else { return false }
        return (0...(words.count - parts.count)).contains { start in
            parts.indices.allSatisfy { wordMatches(parts[$0], words[start + $0]) }
        }
    }

    private static func wordMatches(_ pattern: String, _ word: String) -> Bool {
        if pattern.hasSuffix("*") { return word.hasPrefix(pattern.dropLast()) }
        return word == pattern || word == pattern + "s"
    }
}
