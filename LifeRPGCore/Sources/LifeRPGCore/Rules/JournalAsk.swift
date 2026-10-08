import Foundation

/// What one tap of "Ask me something" sends to the model: its instructions, the prompt, and
/// everything a new question must not resemble.
public struct JournalAskRequest: Equatable, Sendable {
    public let language: JournalLanguage
    public let instructions: String
    public let prompt: String
    /// The entry's own questions, then those of the last three entries, then the tone anchors the
    /// prompt showed, then the four chip questions, so the model can not hand back a chip in other
    /// words. Held against the model's answer even when the prompt left some of them out (it does
    /// not list the last entries' questions unless asked to).
    public let avoiding: [String]
}

/// What the editor does after a tap.
public enum JournalAskResult: Equatable, Sendable {
    /// The model's question, to insert as an `llm` prompt.
    case question(String)
    /// The model could not be used; insert this question about one thing from the day
    /// (`JournalAsk.dayQuestion`) as a fixed prompt with no chip key, and show `toast`.
    case fromDay(String, toast: String)
    /// The model could not be used and the day had nothing fresh to ask about; insert this fixed
    /// prompt and show `toast`.
    case fallback(JournalFixedKey, toast: String)
    /// The model could not be used and every fixed prompt is already in the entry: insert nothing
    /// and show `JournalAsk.exhaustedToast`.
    case exhausted
    /// Five model prompts are in the entry: the pill is dimmed with `JournalAsk.cappedTooltip`.
    case capped
    /// The entry's writing holds a word `JournalSafety` knows. The model was not called; show this
    /// line instead of a question.
    case safety(String)
}

/// Why `JournalAsk.check` turned the model's text away, in the order the checks run.
public enum JournalAskRejection: String, Error, Equatable, CaseIterable, Sendable {
    case empty, tooLong, noQuestionMark, placeholder, voice, notFresh
}

/// What became of the model on one tap. The editor shows the same fallback toast for every case
/// but `answered`, so the Debug page reads this to tell them apart.
public struct JournalAskDiagnosis: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        /// No model on the device (`JournalWordingProvider` answered nil).
        case noModel
        /// The model did not answer within `JournalAsk.timeout` (`retryTimeout` on the second ask).
        case timedOut
        /// The model answered nil: it threw (guardrails, an unsupported language) or said nothing.
        case noAnswer
        /// The model wrote this, and `check` turned it away for this reason. For `notFresh`,
        /// `nearest` is the question it was closest to.
        case rejected(text: String, reason: JournalAskRejection, nearest: JournalNovelty.Match?)
        case answered
    }

    /// What became of the last call to the model.
    public let outcome: Outcome
    /// The first answer was `notFresh`, so the model was asked a second time and `outcome` is what
    /// became of that second call.
    public let retried: Bool

    public init(_ outcome: Outcome, retried: Bool = false) {
        self.outcome = outcome
        self.retried = retried
    }

    public var summary: String {
        let timeout = retried ? JournalAsk.retryTimeout : JournalAsk.timeout
        let text: String
        switch outcome {
        case .noModel: text = "no model on this device"
        case .timedOut: text = "timed out after \(timeout.components.seconds) s"
        case .noAnswer: text = "the model threw or answered nothing"
        case .rejected(let written, let reason, let nearest):
            text = "rejected (\(reason.rawValue)): \(written)"
                + (nearest.map { " closest to \"\($0.question)\" at " + String(format: "%.2f", $0.similarity) } ?? "")
        case .answered: text = "answered"
        }
        guard retried else { return text }
        if case .answered = outcome { return text + " on the second ask" }
        return text + ", on the second ask"
    }
}

/// What the editor shows besides the inserted prompt: a one-line toast that fades, or the safety
/// line, which stays until the reader dismisses it.
public enum JournalAskNotice: Equatable, Sendable {
    case toast(String)
    case safety(String)
}

/// The rules of the editor's "Ask me something" button: the request, what is accepted of the
/// model's text, and the choice between the model's question and a fixed one. The app supplies the
/// model (`JournalWording`) and the cursor; nothing here reads a store.
public enum JournalAsk {
    /// A question is under this many words (English) or characters (Chinese, punctuation counted,
    /// whitespace not), which read about the same length.
    public static let wordLimit = 15
    public static let characterLimit = 25

    /// Past this many model prompts in one entry the button is dimmed.
    public static let maxLLMPrompts = 5

    /// A slower model is treated as unavailable: the user is waiting on a spinner. The first call
    /// after launch loads the model, which is why this is not shorter; the editor prewarms it.
    public static let timeout: Duration = .seconds(10)

    /// The second ask, after a `notFresh` first answer, is to a model that is already warm.
    public static let retryTimeout: Duration = .seconds(5)

    /// How many earlier entries the request holds its question against.
    static let previousEntryCount = 3

    /// The pill is dimmed and does nothing: five model prompts are in the entry. `resolve` answers
    /// `capped` by this same rule.
    public static func isCapped(_ document: JournalDocument) -> Bool {
        document.llmPromptCount >= maxLLMPrompts
    }

    // MARK: the request

    /// - Parameters:
    ///   - document: the entry as it is now.
    ///   - previousQuestions: `previousQuestions(before:in:)`.
    ///   - includeWriting: the Settings switch "Send my writing with the question request". Off,
    ///     the prompt carries the day's quests and the entry's own questions and nothing else:
    ///     no text, no answers, and not the older entries' questions either. Those are still held
    ///     against the answer, locally.
    ///   - listsRecentQuestions: whether the prompt lists `previousQuestions`, which only goes in with
    ///     the writing. Off by default, since a small model copies from a list it is told to avoid;
    ///     they are held against the answer either way. Exists to compare the two prompts.
    public static func request(language: JournalLanguage, signals: JournalSignals, document: JournalDocument,
                               previousQuestions: [String], includeWriting: Bool,
                               listsRecentQuestions: Bool = false) -> JournalAskRequest {
        let existing = document.questions
        let anchors = anchors(signals: signals, questionsInEntry: existing.count, language: language)
        let prompt = JournalPromptBuilder.prompt(
            language: language, signals: signals,
            writing: includeWriting ? JournalPromptBuilder.writing(of: document) : nil,
            existing: existing, recent: includeWriting && listsRecentQuestions ? previousQuestions : [], anchors: anchors)
        return JournalAskRequest(language: language,
                                 instructions: JournalPromptBuilder.instructions(language: language),
                                 prompt: prompt,
                                 avoiding: existing + previousQuestions + anchors
                                     + JournalFixedKey.allCases.map { $0.question(language: language) })
    }

    /// Up to three pool rows as tone anchors, chosen by the day: a low day gets the heavy-day rows,
    /// else a routine given up on the skip rows, else a quest rated 1 or more the good rows,
    /// otherwise the opening rows. They start one row later for each question already in the entry,
    /// so repeated taps do not show the model the same three.
    static func anchors(signals: JournalSignals, questionsInEntry: Int, language: JournalLanguage) -> [String] {
        let kind: JournalPromptKind
        var fills: [JournalPlaceholder: String] = [:]
        if signals.tier.isLow {
            kind = .heavy
        } else if let skipped = signals.skipped.first {
            kind = .skip
            fills[.quest] = skipped.text
        } else if let best = signals.bestRated {
            kind = .good
            fills[.quest] = best.subject.text
        } else {
            kind = .opening
        }
        let rows = JournalPool.prompts(of: kind).compactMap {
            JournalPool.render(id: $0.id, language: language, fills: fills)
        }
        guard !rows.isEmpty else { return [] }
        let start = questionsInEntry % rows.count
        return Array((rows[start...] + rows[..<start]).prefix(3))
    }

    /// The questions of the last three entries before `dayKey`, newest entry first and the latest
    /// question of each first. An entry with no questions still counts as one of the three.
    public static func previousQuestions(before dayKey: String, in entries: [JournalEntry]) -> [String] {
        entries.filter { $0.dayKey < dayKey }
            .sorted { $0.dayKey > $1.dayKey }
            .prefix(previousEntryCount)
            .flatMap { $0.document.questions.reversed() }
    }

    // MARK: accepting the model's text

    /// The question the model wrote, cleaned, or nil when it may not be shown: surrounding quotes
    /// stripped and only the first line kept, then under the length limit, exactly one question
    /// mark, no placeholder left unfilled, no tell of `JournalTextCheck`, and not close
    /// (`JournalNovelty`) to anything in `request.avoiding`.
    public static func accept(_ raw: String, request: JournalAskRequest) -> String? {
        try? check(raw, request: request).get()
    }

    /// `accept` with the reason for a refusal: the first check the text fails.
    public static func check(_ raw: String, request: JournalAskRequest) -> Result<String, JournalAskRejection> {
        let language = request.language
        let text = cleaned(raw)
        guard !text.isEmpty else { return .failure(.empty) }
        guard withinLimit(text, language: language) else { return .failure(.tooLong) }
        // At most one mark is `JournalTextCheck`'s rule below, so one is there exactly when any is.
        guard text.contains(where: JournalTextCheck.isQuestionMark) else { return .failure(.noQuestionMark) }
        guard text.range(of: #"\{[^{}]*\}"#, options: .regularExpression) == nil else { return .failure(.placeholder) }
        guard JournalTextCheck.violations(of: text, language: language).isEmpty else { return .failure(.voice) }
        guard JournalNovelty.isFresh(text, avoiding: request.avoiding, language: language) else {
            return .failure(.notFresh)
        }
        return .success(text)
    }

    /// What `check` judges: the first line of `raw`, without surrounding quotes.
    private static func cleaned(_ raw: String) -> String {
        unquoted(firstLine(of: raw))
    }

    /// The question in `request.avoiding` that `raw` is closest to, for saying why a `notFresh`
    /// text was turned away.
    public static func nearestAvoided(_ raw: String, request: JournalAskRequest) -> JournalNovelty.Match? {
        JournalNovelty.closestMatch(cleaned(raw), to: request.avoiding, language: request.language)
    }

    private static func firstLine(of raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return line.trimmingCharacters(in: .whitespaces)
    }

    private static let quotePairs: [(open: Character, close: Character)] = [
        ("\"", "\""), ("'", "'"), ("\u{201C}", "\u{201D}"), ("\u{2018}", "\u{2019}"),
        ("\u{300C}", "\u{300D}"), ("\u{300E}", "\u{300F}"), ("\u{00AB}", "\u{00BB}"),
    ]

    private static func unquoted(_ text: String) -> String {
        guard text.count >= 2, let first = text.first, let last = text.last,
              quotePairs.contains(where: { $0.open == first && $0.close == last })
        else { return text }
        return String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }

    private static func withinLimit(_ text: String, language: JournalLanguage) -> Bool {
        switch language {
        case .en: JournalTextCheck.words(text).count < wordLimit
        case .zhHans: text.filter { !$0.isWhitespace }.count < characterLimit
        }
    }

    // MARK: resolving

    /// The one decision behind a tap, in this order. Five model prompts already in the entry is
    /// `capped`, before anything else. Writing that holds a safety word gets the safety line and
    /// the model is not called, whether or not the writing would have been sent. Otherwise the
    /// model is asked: a question it wrote that `accept` takes is the result. An answer that is
    /// `notFresh` (a copy of a question already asked) is asked for once more, with
    /// `JournalPromptBuilder.retryPrompt` and `retryTimeout`; a second answer that `accept` takes is
    /// the result. Anything else (no model, a timeout, an error, nothing, a text rejected for
    /// another reason, a second answer that fails) is a question about one thing from the day
    /// (`dayQuestion`), else the first fixed prompt in `JournalFixedKey.fallbackOrder` the entry
    /// lacks, or `exhausted` when it has them all.
    /// The model is called at most twice. `diagnose` hears what became of the model, once, whenever
    /// it was the model's turn, which is every result but `capped` and `safety`.
    public static func resolve(language: JournalLanguage, signals: JournalSignals, document: JournalDocument,
                               previousQuestions: [String], includeWriting: Bool,
                               listsRecentQuestions: Bool = false,
                               wording: (any JournalWording)?,
                               timeout: Duration = JournalAsk.timeout,
                               retryTimeout: Duration = JournalAsk.retryTimeout,
                               diagnose: (@Sendable (JournalAskDiagnosis) -> Void)? = nil) async -> JournalAskResult {
        if isCapped(document) { return .capped }
        let written = document.blocks.map(\.writtenText).joined(separator: "\n")
        if JournalSafety.needsSafetyLine(answer: written) {
            return .safety(JournalSafety.line(language: language))
        }
        if let wording {
            let asked = request(language: language, signals: signals, document: document,
                                previousQuestions: previousQuestions, includeWriting: includeWriting,
                                listsRecentQuestions: listsRecentQuestions)
            var attempt = await ask(wording, asked, prompt: asked.prompt, timeout: timeout)
            var retried = false
            if case .failed(.rejected(let text, .notFresh, _)) = attempt {
                retried = true
                let again = JournalPromptBuilder.retryPrompt(asked.prompt, rejected: cleaned(text), language: language)
                attempt = await ask(wording, asked, prompt: again, timeout: retryTimeout)
            }
            switch attempt {
            case .accepted(let question):
                diagnose?(JournalAskDiagnosis(.answered, retried: retried))
                return .question(question)
            case .failed(let outcome):
                diagnose?(JournalAskDiagnosis(outcome, retried: retried))
            }
        } else {
            diagnose?(JournalAskDiagnosis(.noModel))
        }
        if let question = dayQuestion(signals: signals, document: document,
                                      previousQuestions: previousQuestions, language: language) {
            return .fromDay(question, toast: dayFallbackToast(language: language))
        }
        guard let key = JournalFixedKey.nextFallback(missingFrom: document) else { return .exhausted }
        return .fallback(key, toast: fallbackToast(language: language))
    }

    private enum Attempt {
        case accepted(String)
        case failed(JournalAskDiagnosis.Outcome)
    }

    /// One call to the model, judged by `check`.
    private static func ask(_ wording: any JournalWording, _ asked: JournalAskRequest, prompt: String,
                            timeout: Duration) async -> Attempt {
        // Wrapped, so a model that answered nothing is told apart from one that ran out of time.
        let answer = await JournalConversation.raced(timeout) {
            Answer(text: await wording.word(instructions: asked.instructions, prompt: prompt))
        }
        guard let answer else { return .failed(.timedOut) }
        guard let raw = answer.text else { return .failed(.noAnswer) }
        switch check(raw, request: asked) {
        case .success(let question):
            return .accepted(question)
        case .failure(let reason):
            let nearest = reason == .notFresh ? nearestAvoided(raw, request: asked) : nil
            return .failed(.rejected(text: raw, reason: reason, nearest: nearest))
        }
    }

    /// A `fact` row filled with one concrete thing from the day, for when the model could not be
    /// used. Tried in this order, and the first that is not close to a question in the entry or the
    /// last three entries wins: the epic finished early, a routine done ahead of its day, a hard
    /// quest done, a routine given up on, something still open today, the best-rated thing done,
    /// then anything done, latest first. Nil when the day has nothing fresh to ask about.
    public static func dayQuestion(signals: JournalSignals, document: JournalDocument,
                                   previousQuestions: [String], language: JournalLanguage) -> String? {
        var candidates: [(id: String, quest: String)] = []
        if let epic = signals.epic, case .doneToday(let spare) = epic.progress, spare > 0 {
            candidates.append(("fact.early", epic.text))
        }
        candidates += signals.completed.filter(\.isAhead).map { ("fact.early", $0.subject.text) }
        candidates += signals.completed.filter { $0.difficulty == .hard }.map { ("fact.hard", $0.subject.text) }
        candidates += signals.skipped.map { ("skip.block", $0.text) }
        candidates += signals.leftOpen.map { ("fact.open", $0.text) }
        if let best = signals.bestRated { candidates.append(("good.moment", best.subject.text)) }
        candidates += signals.completed.reversed().map { ("fact.done", $0.subject.text) }

        let avoiding = document.questions + previousQuestions
        for candidate in candidates {
            guard let text = JournalPool.render(id: candidate.id, language: language, fills: [.quest: candidate.quest]),
                  JournalNovelty.isFresh(text, avoiding: avoiding, language: language)
            else { continue }
            return text
        }
        return nil
    }

    private struct Answer: Sendable {
        let text: String?
    }

    // MARK: insertion

    /// Puts the result into the entry at the cursor captured when the pill was tapped
    /// (`JournalDocument.insertingPrompt`): a question as an `llm` prompt, a fallback as the fixed
    /// prompt of its key. The user may have typed, or tapped the chip itself, while waiting, so a
    /// fallback whose key is in the entry by now takes the next missing one. Nil for a result that
    /// is not a question, and when nothing can be inserted.
    public static func insert(_ result: JournalAskResult, into document: JournalDocument, atBlock blockID: UUID?,
                              offset: Int, language: JournalLanguage,
                              makeID: () -> UUID = UUID.init) -> JournalEdit? {
        let seed: JournalPromptSeed
        switch result {
        case .question(let text):
            seed = JournalPromptSeed(question: text, source: .llm)
        case .fromDay(let text, _):
            seed = JournalPromptSeed(question: text, source: .fixed)
        case .fallback(let key, _):
            guard let free = document.containsFixedKey(key) ? JournalFixedKey.nextFallback(missingFrom: document) : key
            else { return nil }
            seed = .fixed(free, language: language)
        case .capped, .exhausted, .safety:
            return nil
        }
        return document.insertingPrompt(seed, atBlock: blockID, offset: offset, makeID: makeID)
    }

    // MARK: what the editor says

    /// What to show once `result` has met the entry. `inserted` is whether `insert` made an edit.
    /// A result that could not be inserted blames the cursor's block being gone, unless a fallback
    /// found every fixed prompt in the entry by now, which is `exhausted` by another road.
    public static func notice(for result: JournalAskResult, inserted: Bool, document: JournalDocument,
                              language: JournalLanguage) -> JournalAskNotice? {
        switch result {
        case .capped: return nil
        case .exhausted: return .toast(exhaustedToast(language: language))
        case .safety(let line): return .safety(line)
        case .question:
            return inserted ? nil : .toast(spotGoneToast(language: language))
        case .fromDay(_, let toast):
            return .toast(inserted ? toast : spotGoneToast(language: language))
        case .fallback(_, let toast):
            if inserted { return .toast(toast) }
            return .toast(JournalFixedKey.nextFallback(missingFrom: document) == nil
                          ? exhaustedToast(language: language) : spotGoneToast(language: language))
        }
    }

    /// The block the cursor was in was removed while the model was thinking.
    public static func spotGoneToast(language: JournalLanguage) -> String {
        language == .zhHans ? "你提问的位置已经不在了，所以没有加入问题"
                            : "The place you asked from is gone, so no question was added"
    }

    public static func dayFallbackToast(language: JournalLanguage) -> String {
        language == .zhHans ? "没能联系上向导，换一个关于今天的问题" : "Couldn't reach the guide, here's one about your day"
    }

    public static func fallbackToast(language: JournalLanguage) -> String {
        language == .zhHans ? "没能联系上向导，换一个常用的问题" : "Couldn't reach the guide, here's a standard one"
    }

    /// The dimmed pill's tooltip, for `JournalAskResult.capped`.
    public static func cappedTooltip(language: JournalLanguage) -> String {
        language == .zhHans ? "今晚问得够多了" : "Enough questions for one night"
    }

    /// For `JournalAskResult.exhausted`.
    public static func exhaustedToast(language: JournalLanguage) -> String {
        language == .zhHans ? "没能联系上向导，常用的问题也都已经在日记里了"
                            : "Couldn't reach the guide, and every standard question is already in your entry"
    }
}
