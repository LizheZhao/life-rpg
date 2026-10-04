import Foundation

/// How alike two pieces of text are, for deciding whether the model's question is new or a pool row
/// (or yesterday's question) in other clothes.
///
/// Jaccard over token sets. English tokens are lowercased words with punctuation stripped; Chinese
/// has no word boundary, so tokens are the character bigrams of the text with punctuation and
/// spaces removed. Word order is ignored on purpose: swapping two words is not a new question.
public enum JournalNovelty {
    /// A question at or above this similarity to anything it is held against is rejected. One word
    /// swapped in a ten-word question scores 9/11, a different question on the same theme under 0.3.
    public static let threshold = 0.6

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
            return Set(JournalTextCheck.words(text))
        case .zhHans:
            let chars = Array(text.filter { $0.isLetter || $0.isNumber })
            // A single character has no bigram; it stands as its own token so it still compares.
            guard chars.count >= 2 else { return Set(chars.map(String.init)) }
            return Set((0..<(chars.count - 1)).map { String(chars[$0...$0 + 1]) })
        }
    }
}
