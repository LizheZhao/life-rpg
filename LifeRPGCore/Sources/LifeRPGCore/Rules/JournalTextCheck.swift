import Foundation

/// Checks text the on-device model wrote before it is shown.
///
/// The model only ever words a follow-up; this decides whether the wording is allowed. The rules
/// are the voice rules of `doc/JOURNAL_PROMPTS.md` turned into patterns: the staged rhythms that
/// make generated text recognisable (contrast, dramatic openers and closers, em dashes), more than
/// one question, a question that opens with "why", a markdown marker, a wall of text. A failure
/// means the caller falls back to the template (`JournalFollowUp.template`), never to a retry.
///
/// The pool itself has to pass, which `JournalTextCheckTests` asserts, so the check can't drift
/// into rejecting the app's own questions.
public enum JournalTextCheck {
    public enum Violation: String, CaseIterable, Sendable {
        case contrastStaging, stagedOpener, stagedCloser, emDash
        case manyQuestions, startsWithWhy, tooLong, markdown
    }

    /// Questions are short. Counted in characters of the whole text, reflection and question
    /// together; Chinese packs more into a character, so its cap is half.
    public static func maxLength(_ language: JournalLanguage) -> Int {
        language == .zhHans ? 100 : 200
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
        if text.filter({ $0 == "?" || $0 == "？" }).count > 1 { found.insert(.manyQuestions) }
        if text.count > maxLength(language) { found.insert(.tooLong) }
        return Violation.allCases.filter(found.contains)
    }

    /// Whether the model's follow-up may be shown: a reflection and one question, both clean as a
    /// whole, the question actually a question, and the reflection built from the user's own words
    /// (a verbatim run of at least two words, or three characters in Chinese) rather than a
    /// paraphrase.
    public static func accept(reflection: String, question: String, answer: String,
                              language: JournalLanguage) -> Bool {
        let whole = reflection + " " + question
        return violations(of: whole, language: language).isEmpty
            && question.contains(where: { $0 == "?" || $0 == "？" })
            && reusesWords(reflection, from: answer, language: language)
    }

    /// A verbatim run of the answer inside `reflection`. Words are compared case-insensitively
    /// and without punctuation; Chinese has no word boundary, so a window of letters is compared.
    static func reusesWords(_ reflection: String, from answer: String, language: JournalLanguage) -> Bool {
        if language == .zhHans {
            let window = 3
            let chars = Array(reflection)
            guard chars.count >= window else { return false }
            return (0...(chars.count - window)).contains { start in
                let run = chars[start..<start + window]
                return run.allSatisfy { $0.isLetter || $0.isNumber } && answer.contains(String(run))
            }
        }
        let theirs = words(answer), mine = words(reflection)
        guard theirs.count >= 2, mine.count >= 2 else { return false }
        let pairs = Set((0..<(theirs.count - 1)).map { "\(theirs[$0]) \(theirs[$0 + 1])" })
        return (0..<(mine.count - 1)).contains { pairs.contains("\(mine[$0]) \(mine[$0 + 1])") }
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'") })
            .map(String.init)
    }
}
