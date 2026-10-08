import Foundation

/// How alike two pieces of text are, for deciding whether the model's question is new or a pool row
/// (or yesterday's question) in other clothes.
///
/// Jaccard over token sets. English tokens are the lowercased words with punctuation stripped, minus
/// the frame words a question is built from (`stopWords`): "what was it like" is in every question
/// and says nothing about which one it is, so counting it made "You finished Walk today. What was it
/// like?" and the same with "Cook a meal" 0.64 alike. Chinese has no word boundary, so tokens are
/// the character bigrams of the text with punctuation and spaces removed, and the frame is not
/// removed there. Word order is ignored on purpose: swapping two words is not a new question.
public enum JournalNovelty {
    /// A question at or above this similarity to anything it is held against is rejected. Of the
    /// content words, a copy with one of five swapped scores 4/6, and a different question on the
    /// same theme is under 0.3.
    public static let threshold = 0.6

    /// Words that build a question and are not what it asks about: articles, prepositions, the verbs
    /// be, do and have, pronouns, question words, and "today", which every question here is about.
    /// Kept short on purpose; a word missing from it only makes two questions look more alike.
    static let stopWords: Set<String> = [
        "a", "an", "the", "of", "to", "in", "on", "at", "for", "with", "and", "or", "but", "if", "as", "by",
        "from", "about", "than", "too", "very", "just", "so", "then", "there",
        "is", "are", "was", "were", "be", "been", "am", "do", "did", "does", "done", "have", "has", "had",
        "can", "could", "would", "will", "should", "may", "might", "not", "no",
        "you", "your", "yours", "i", "me", "my", "mine", "we", "our", "us", "they", "them", "their",
        "it", "its", "this", "that", "these", "those",
        "what", "which", "who", "whom", "whose", "how", "when", "where",
        "today", "tonight",
    ]

    /// 0 for nothing in common, 1 for the same tokens. Two texts with no tokens at all score 0:
    /// there is nothing to call alike.
    public static func similarity(_ a: String, _ b: String, language: JournalLanguage) -> Double {
        let left = tokens(a, language: language), right = tokens(b, language: language)
        let union = left.union(right).count
        return union == 0 ? 0 : Double(left.intersection(right).count) / Double(union)
    }

    /// The highest similarity of `text` to any of `others`; 0 with none.
    public static func closest(_ text: String, to others: [String], language: JournalLanguage) -> Double {
        others.map { similarity(text, $0, language: language) }.max() ?? 0
    }

    /// Whether `text` is below `threshold` against every one of `others`.
    public static func isFresh(_ text: String, avoiding others: [String], language: JournalLanguage) -> Bool {
        closest(text, to: others, language: language) < threshold
    }

    static func tokens(_ text: String, language: JournalLanguage) -> Set<String> {
        switch language {
        case .en:
            let words = JournalTextCheck.words(text)
            let content = Set(words.filter { !stopWords.contains($0) })
            // A question of nothing but frame words is compared whole, or it would match nothing.
            return content.isEmpty ? Set(words) : content
        case .zhHans:
            let chars = Array(text.filter { $0.isLetter || $0.isNumber })
            // A single character has no bigram; it stands as its own token so it still compares.
            guard chars.count >= 2 else { return Set(chars.map(String.init)) }
            return Set((0..<(chars.count - 1)).map { String(chars[$0...$0 + 1]) })
        }
    }
}
