import Foundation

/// The voice rules of `doc/JOURNAL_PROMPTS.md` turned into patterns, for text the on-device model
/// wrote: the staged rhythms that make generated text recognisable (contrast, dramatic openers and
/// closers, em dashes), more than one question, a question that opens with "why", a markdown
/// marker. `JournalAsk.accept` adds the length, one-question, placeholder and novelty rules on top;
/// a failure there means the caller falls back to a fixed prompt, never to a retry.
///
/// The pool itself passes every rule except the one-question rule on three deliberate two-part
/// rows, which `JournalTextCheckTests` asserts, so the check can't drift into rejecting the app's
/// own questions.
public enum JournalTextCheck {
    public enum Violation: String, CaseIterable, Sendable {
        case contrastStaging, stagedOpener, stagedCloser, emDash
        case manyQuestions, startsWithWhy, markdown
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
        // a sentence that opens with why
        Tell(violation: .startsWithWhy, pattern: #"(?i)(?:^|[.!?]\s+)\s*why\b"#),
    ]

    private static let chineseTells: [Tell] = [
        Tell(violation: .contrastStaging, pattern: #"(?s)不是.{0,30}?而是"#),
        Tell(violation: .contrastStaging, pattern: #"(?s)不只是.{0,30}?更是"#),
        Tell(violation: .stagedOpener, pattern: "说实话"),
        Tell(violation: .stagedCloser, pattern: "这正是"),
        Tell(violation: .startsWithWhy, pattern: "(?:^|[。！？!?])\\s*为什么"),
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
