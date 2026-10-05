import Foundation

/// Checks text the on-device model wrote before it is shown.
///
/// The model words follow-ups and, from a brief, fresh questions; this decides whether the wording
/// is allowed. The rules are the voice rules of `doc/JOURNAL_PROMPTS.md` turned into patterns: the
/// staged rhythms that make generated text recognisable (contrast, dramatic openers and closers,
/// em dashes), more than one question, a question that opens with "why", a markdown marker, a wall
/// of text, and a copy of a pool row or of a recent question (`JournalNovelty`). A failure means
/// the caller falls back to the pool row (`JournalQuestion.text`,
/// `JournalFollowUpRequest.fallback`), never to a retry.
///
/// The pool itself passes every rule except the one-question rule on three deliberate two-part
/// rows, which `JournalTextCheckTests` asserts, so the check can't drift into rejecting the app's
/// own questions.
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
        if text.filter(isQuestionMark).count > 1 { found.insert(.manyQuestions) }
        if text.count > maxLength(language) { found.insert(.tooLong) }
        return Violation.allCases.filter(found.contains)
    }

    private static func isQuestionMark(_ character: Character) -> Bool {
        character == "?" || character == "？"
    }

    /// Whether the model's follow-up may be shown: a reflection and one question, both clean as a
    /// whole, the question actually a question, the reflection built from the user's own words
    /// (a verbatim run of at least two words, or three characters in Chinese) rather than a
    /// paraphrase, not a repeat of most of the answer (`parrotsAnswer`), and the whole not a copy
    /// of anything in `avoiding` (`JournalNovelty`): the follow-up examples it was shown and the
    /// follow-ups asked lately.
    public static func accept(reflection: String, question: String, answer: String,
                              language: JournalLanguage, avoiding: [String] = []) -> Bool {
        let whole = reflection + " " + question
        return violations(of: whole, language: language).isEmpty
            && question.contains(where: isQuestionMark)
            && reusesWords(reflection, from: answer, language: language)
            && !parrotsAnswer(reflection, answer: answer, language: language)
            && JournalNovelty.isFresh(whole, avoiding: avoiding, language: language)
    }

    /// Whether the model's wording of a question may be shown: clean, exactly one question mark, no
    /// placeholder left unfilled, and below `JournalNovelty.threshold` against everything in
    /// `avoiding`, which is the pool examples it was shown plus what was asked lately. A model
    /// that echoes an example or yesterday's question is rejected the same as one that breaks a
    /// voice rule.
    public static func acceptQuestion(_ text: String, language: JournalLanguage, avoiding: [String]) -> Bool {
        // A clean text has at most one mark, so one is there exactly when any is.
        violations(of: text, language: language).isEmpty
            && text.contains(where: isQuestionMark)
            && text.range(of: #"\{[^{}]*\}"#, options: .regularExpression) == nil
            && JournalNovelty.isFresh(text, avoiding: avoiding, language: language)
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

    /// A reflection that quotes a few words is listening; one that gives the answer back is not.
    /// Only an answer of at least this many words (characters in Chinese) is held to it, because a
    /// shorter one can only be quoted whole.
    static let parrotMinAnswerWords = 6
    static let parrotMinAnswerCharacters = 12
    /// The longest verbatim run may cover at most 3/5 of the answer's tokens; more is parroting.
    static let parrotMaxShareNumerator = 3
    static let parrotMaxShareDenominator = 5

    /// Whether the longest verbatim run `reflection` shares with `answer` is more than 60% of the
    /// answer. Tokens are words in English and letters or digits in Chinese (punctuation dropped),
    /// the same as `reusesWords`.
    static func parrotsAnswer(_ reflection: String, answer: String, language: JournalLanguage) -> Bool {
        let theirs: [String], mine: [String]
        let minimum: Int
        if language == .zhHans {
            theirs = answer.filter { $0.isLetter || $0.isNumber }.map(String.init)
            mine = reflection.filter { $0.isLetter || $0.isNumber }.map(String.init)
            minimum = parrotMinAnswerCharacters
        } else {
            theirs = words(answer)
            mine = words(reflection)
            minimum = parrotMinAnswerWords
        }
        guard theirs.count >= minimum else { return false }
        return longestSharedRun(mine, theirs) * parrotMaxShareDenominator > theirs.count * parrotMaxShareNumerator
    }

    private static func longestSharedRun(_ a: [String], _ b: [String]) -> Int {
        var best = 0
        var previous = [Int](repeating: 0, count: b.count + 1)
        for x in a {
            var current = [Int](repeating: 0, count: b.count + 1)
            for (j, y) in b.enumerated() where x == y {
                current[j + 1] = previous[j] + 1
                best = max(best, current[j + 1])
            }
            previous = current
        }
        return best
    }

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'") })
            .map(String.init)
    }
}
