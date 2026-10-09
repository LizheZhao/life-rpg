import Foundation

/// The voice rules of `doc/JOURNAL_PROMPTS.md` turned into patterns, for text the on-device model
/// wrote: the staged rhythms that make generated text recognisable (contrast, dramatic openers and
/// closers, em dashes), more than one question, a question that asks "why" anywhere in it, a markdown
/// marker. `JournalAsk.accept` adds the length, one-question, placeholder and novelty rules on top;
/// a failure there means the caller falls back to a fixed prompt, except that a copy of a
/// question already asked, a closed question and an unsupported "early" are asked for again, once
/// (`JournalAsk.resolve`).
///
/// The pool itself passes every rule except the one-question rule on two deliberate two-part
/// rows, which `JournalTextCheckTests` asserts, so the check can't drift into rejecting the app's
/// own questions.
public enum JournalTextCheck {
    public enum Violation: String, CaseIterable, Sendable {
        case contrastStaging, stagedOpener, stagedCloser, emDash
        case manyQuestions, asksWhy, markdown
    }

    private struct Tell {
        let violation: Violation
        let pattern: String
    }

    private static let englishTells: [Tell] = [
        // not just / only / merely ... but
        Tell(violation: .contrastStaging, pattern: #"(?is)\bnot\s+(?:just|only|merely)\b.{0,80}?\bbut\b"#),
        // it's not ..., it's
        Tell(violation: .contrastStaging, pattern: #"(?is)\bit(?:['’]s|\s+is)\s+not\b[^.!?]{0,80}?,\s*it(?:['’]s|\s+is)\b"#),
        // This does not mean ... It means
        Tell(violation: .contrastStaging,
             pattern: #"(?is)\bthis\s+(?:does\s+not|doesn['’]t)\s+mean\b[^.!?]{0,120}[.!?]\s*it\s+means\b"#),
        Tell(violation: .stagedOpener, pattern: #"(?i)\bhonestly\s*\?"#),
        Tell(violation: .stagedOpener, pattern: #"(?i)\blet['’]?s\s+dive\b"#),
        Tell(violation: .stagedOpener, pattern: #"(?i)\bhere(?:['’]s|\s+is)\s+the\s+thing\b"#),
        Tell(violation: .stagedOpener, pattern: #"(?i)\breal\s+talk\b"#),
        Tell(violation: .stagedCloser, pattern: #"(?i)\bthat(?:\s+is|['’]s)\s+the\s+real\b"#),
        Tell(violation: .stagedCloser, pattern: #"(?i)\bread\s+that\s+again\b"#),
        Tell(violation: .stagedCloser, pattern: #"(?i)\blet\s+that\s+sink\s+in\b"#),
        // why anywhere: "What did you think of today, and why did you skip …?" asks for a reason just
        // the same as a question that opens with it
        Tell(violation: .asksWhy, pattern: #"(?i)\bwhy\b"#),
    ]

    private static let chineseTells: [Tell] = [
        Tell(violation: .contrastStaging, pattern: #"(?s)不是.{0,30}?而是"#),
        Tell(violation: .contrastStaging, pattern: #"(?s)不只是.{0,30}?更是"#),
        Tell(violation: .stagedOpener, pattern: "说实话"),
        Tell(violation: .stagedCloser, pattern: "这正是"),
        Tell(violation: .asksWhy, pattern: "为什么"),
    ]

    /// Both languages: a long dash is the single most recognisable generated-text mark, and the
    /// Chinese double dash is two of them.
    private static let commonTells: [Tell] = [
        Tell(violation: .emDash, pattern: "\u{2014}"),
        Tell(violation: .markdown,
             pattern: #"\*\*|__|`|(?m)^\s{0,3}#{1,6}\s|(?m)^\s*[-*+]\s+\S|\[[^\]]+\]\([^)]+\)"#),
    ]

    /// Every rule `text` breaks, once each, in declaration order.
    public static func violations(of text: String, language: JournalLanguage) -> [Violation] {
        var found = Set<Violation>()
        let tells = (language == .zhHans ? chineseTells : englishTells) + commonTells
        for tell in tells where text.range(of: tell.pattern, options: .regularExpression) != nil {
            found.insert(tell.violation)
        }
        if text.filter(isQuestionMark).count > 1 { found.insert(.manyQuestions) }
        return Violation.allCases.filter(found.contains)
    }

    // MARK: what a pattern can say about a question's form

    /// Words that open a yes/no question in English: the auxiliary verbs, and any negative
    /// contraction of one ("didn't", "isn't", "can't").
    static let openingAuxiliaries: Set<String> = [
        "did", "do", "does", "is", "are", "was", "were", "am", "have", "has", "had",
        "can", "could", "will", "would", "should", "shall", "may", "might",
    ]

    /// A tag that turns a statement into a yes/no question: ", did you?", ", didn't you?", ", right?".
    private static let englishTag = #"(?i),\s*(?:(?:[a-z]+n['’]t|did|do|does|is|are|was|were|am|have|has|had|can|could|will|would|should|shall|may|might)\s+(?:you|it|they|we|he|she|i|there)|right|okay|ok)\s*[?？]\s*$"#

    /// A-not-A forms: the Chinese yes/no question without 吗.
    static let chineseAnyOrNot = ["有没有", "是不是", "能不能", "会不会", "要不要", "好不好", "对不对"]

    /// Whether `text` (one cleaned question) can be answered yes or no by its form: it opens with
    /// an auxiliary verb or ends in a tag (English), or ends in 吗 or holds an A-not-A form (Chinese).
    public static func isClosedQuestion(_ text: String, language: JournalLanguage) -> Bool {
        switch language {
        case .en:
            if let first = words(text).first, openingAuxiliaries.contains(first) || first.hasSuffix("n't") {
                return true
            }
            return text.range(of: englishTag, options: .regularExpression) != nil
        case .zhHans:
            return text.range(of: #"吗\s*[?？]\s*$"#, options: .regularExpression) != nil
                || chineseAnyOrNot.contains(where: text.contains)
        }
    }

    /// Whether `text` says something was early or ahead: the whole words "early" and "ahead", "in
    /// advance" and "before its day" (English), 提前, 提早 and 早早 (Chinese).
    public static func saysEarly(_ text: String, language: JournalLanguage) -> Bool {
        let pattern = language == .zhHans
            ? "提前|提早|早早"
            : #"(?i)\b(?:early|ahead)\b|\bin\s+advance\b|\bbefore\s+its\s+day\b"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    static func isQuestionMark(_ character: Character) -> Bool {
        character == "?" || character == "？"
    }

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'") })
            .map(String.init)
    }
}
