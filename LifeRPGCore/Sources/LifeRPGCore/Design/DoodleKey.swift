import Foundation

/// Which hand-drawn icon a thing wears. Suggested by the text (`forText`); only a custom ad-hoc
/// routine stores a chosen one (`RoutineOccurrence.iconKey`, `SchemaV4`), and `resolve` is the one
/// place that reads it back.
public enum DoodleKey: String, CaseIterable, Sendable {
    case avatar, sneaker, potion, braces, notebook, dumbbell, paperPlane, trendLine, flag, sparkle
    case headphones, camera, paw, forkKnife, moon, heart, speechBubble, mapPin, screen, broom

    /// A plain keyword matches a whole word (or its plural); a trailing `*` matches any word that
    /// starts with it; several words in one keyword (`"apply to"`) must follow each other. The
    /// first entry that matches wins, so the narrow, specific ones come before the broad ones.
    /// `avatar` and `flag` are placed by the layout and have no keywords, and `sparkle` is not an
    /// entry at all: it is what a text gets when nothing here matches.
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
        (.broom, ["clean*", "tidy", "tidying", "declutter", "trash", "sort", "laundry", "dishes", "vacuum",
                  "clothes", "chore*"]),
        (.potion, ["project", "experiment", "water", "drink", "tea", "cocktail", "cook*", "soak", "brew"]),
        (.headphones, ["listen*", "song", "songs", "sing", "singing", "album", "playlist", "music", "concert",
                       "podcast"]),
        (.camera, ["photo*", "picture", "pictures", "camera", "selfie", "draw", "drawing", "sketch*"]),
        (.paw, ["cat", "cats", "dog", "pet", "litter", "groom*", "playtime"]),
        (.forkKnife, ["meal", "meals", "eat*", "food", "snack*", "supermarket", "restaurant", "lunch",
                      "dinner", "breakfast"]),
        (.moon, ["meditat*", "mindful*", "sleep*", "nap", "rest", "relax*", "sunset", "sunrise", "sky",
                 "window", "stare", "pillow", "bedsheet*", "bed", "calm", "breath*"]),
        (.heart, ["mask", "cream", "lotion", "floss", "eye drops", "nail", "nails", "skincare", "shower",
                  "bath", "forgive*", "compliment*", "kind*", "gratitude", "grateful"]),
        (.speechBubble, ["say", "speak*", "talk*", "chat", "conversation", "opinion", "ask", "name"]),
        (.mapPin, ["trip", "visit", "event", "show", "exhibition", "class", "travel", "museum", "go to",
                   "town", "city"]),
        (.screen, ["watch*", "video*", "movie*", "film*", "comedy", "tv", "stream*"]),
    ]

    /// A short name for the picker's VoiceOver label.
    public var title: String {
        switch self {
        case .avatar: "Person"
        case .sneaker: "Sneaker"
        case .potion: "Potion"
        case .braces: "Braces"
        case .notebook: "Notebook"
        case .dumbbell: "Dumbbell"
        case .paperPlane: "Paper plane"
        case .trendLine: "Trend line"
        case .flag: "Flag"
        case .sparkle: "Sparkle"
        case .headphones: "Headphones"
        case .camera: "Camera"
        case .paw: "Paw"
        case .forkKnife: "Fork and knife"
        case .moon: "Moon"
        case .heart: "Heart"
        case .speechBubble: "Speech bubble"
        case .mapPin: "Map pin"
        case .screen: "Screen"
        case .broom: "Broom"
        }
    }

    /// The doodle for something that may carry a stored key: that key when this build knows it,
    /// otherwise what the text suggests. An unknown key (written by a newer build, or damaged in a
    /// backup) is never an error — the row simply reads as it did before the key existed.
    public static func resolve(iconKey: String?, text: String) -> DoodleKey {
        iconKey.flatMap(DoodleKey.init(rawValue:)) ?? forText(text)
    }

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
