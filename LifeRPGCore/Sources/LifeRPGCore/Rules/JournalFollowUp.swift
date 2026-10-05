import Foundation

/// The follow-up that needs no model: a pool row with a short quote of the user's own answer. The
/// planner fills the follow-up rows with `phrase(in:)`, and the first of them is what the app shows
/// when the model is unavailable or its wording fails `JournalTextCheck.accept`.
public enum JournalFollowUp {
    /// The quote is cut to this many characters. A quote is a handle on what they said, not a
    /// transcript, and a Chinese character carries about three English ones.
    public static func phraseLimit(_ language: JournalLanguage) -> Int {
        language == .zhHans ? 12 : 40
    }

    private static let clauseEnds: Set<Character> = [".", "!", "?", ",", ";", ":", "\n", "。", "！", "？", "，", "；", "：", "、", "…"]

    /// The answer's first clause, cut at the language's limit on a word boundary (English) or at
    /// the limit (Chinese). Always a contiguous piece of the answer, never reworded, so quoting it
    /// back is quoting the user. An answer of nothing but punctuation is quoted as it stands.
    public static func phrase(in answer: String, language: JournalLanguage) -> String? {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let limit = phraseLimit(language)

        let start = trimmed.firstIndex { !clauseEnds.contains($0) && !$0.isWhitespace } ?? trimmed.startIndex
        let body = trimmed[start...]
        let clauseEnd = body.firstIndex(where: clauseEnds.contains) ?? body.endIndex
        var clause = body[..<clauseEnd]

        if clause.count > limit {
            let cut = clause.index(clause.startIndex, offsetBy: limit)
            clause = clause[..<cut]
            // English backs off to the last space when the cut would split a word; a single word
            // longer than the whole limit is cut where it stands.
            if language == .en, body[cut].isLetter || body[cut].isNumber,
               let space = clause.lastIndex(where: \.isWhitespace) {
                clause = clause[..<space]
            }
        }
        let phrase = clause.trimmingCharacters(in: .whitespacesAndNewlines)
        return phrase.isEmpty ? String(trimmed.prefix(limit)) : phrase
    }
}
