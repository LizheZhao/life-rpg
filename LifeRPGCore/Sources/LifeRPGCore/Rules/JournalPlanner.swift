import Foundation

/// Decides what the journal asks next.
///
/// A pure function of the day's signals and the turns recorded so far, so asking twice gives the
/// same answer and an app kill in the middle of a day's journal resumes where it stopped: there is
/// no cursor to lose. The planner decides what to ask (the kind, the subject, the facts); the model
/// only words it, so a question step carries a brief (`JournalQuestionBrief`) for that.
///
/// The pool rows are examples and direction for the model, not what the user is meant to read
/// every day. A row is shown as it stands only as the fallback when the model is unavailable or
/// its wording fails `JournalTextCheck`, and that fallback is the least recently used row of the
/// kind so the same few sentences do not come back day after day.
///
/// The sequence is the opening, then an optional follow-up of the opening answer, then up to
/// `maxSupplemental` questions about specific things from the day (each with its own optional
/// follow-up), then the closing. A question the user skipped or called a misfit is a response and
/// counts as asked.
public enum JournalPlanner {
    public static let maxSupplemental = 2
    public static let maxFollowUpsPerDay = 2
    /// A shorter answer has nothing to quote back.
    public static let minimumAnswerLengthForFollowUp = 15

    /// A supplemental kind, the base score it ranks by, and the pool rows it may draw, each with
    /// the condition that makes it fit the day. One table instead of a branch per kind.
    private struct Rule {
        let kind: JournalPromptKind
        let score: (JournalSignals) -> Double?
        let candidates: (JournalSignals) -> [Candidate]
    }

    private struct Candidate {
        let promptID: String
        var fills: [JournalPlaceholder: String] = [:]
        var subject: JournalSubject?
    }

    private static let rules: [Rule] = [
        Rule(kind: .skip,
             score: { $0.skipped.isEmpty ? nil : 3 },
             candidates: { signals in
                 guard let subject = signals.skipped.first else { return [] }
                 return JournalPool.prompts(of: .skip).map {
                     Candidate(promptID: $0.id, fills: [.quest: subject.text], subject: subject)
                 }
             }),
        Rule(kind: .heavy,
             score: { _ in 4 },
             candidates: { signals in
                 let average = signals.averageRating
                 let fits: [(String, Bool)] = [
                     ("heavy.done", signals.completedCount >= 3 && (average ?? 0) <= -0.5),
                     ("heavy.weight", (average ?? 0) <= -1),
                     ("heavy.friend", (average ?? 0) <= -1),
                     ("heavy.body", signals.tier.isLow),
                 ]
                 // Pool order, so the stable draw below indexes the same list every time.
                 return JournalPool.prompts(of: .heavy)
                     .filter { row in fits.contains { $0.0 == row.id && $0.1 } }
                     .map { Candidate(promptID: $0.id) }
             }),
        Rule(kind: .good,
             score: { signals in signals.bestRated?.rating.map { 2 + 0.5 * Double($0 - 1) } },
             candidates: { signals in
                 guard let item = signals.bestRated else { return [] }
                 return JournalPool.prompts(of: .good).map {
                     Candidate(promptID: $0.id, fills: [.quest: item.subject.text], subject: item.subject)
                 }
             }),
        Rule(kind: .choice,
             score: { $0.choiceItem == nil ? nil : 2 },
             candidates: { signals in
                 guard let item = signals.choiceItem else { return [] }
                 // A variant is drawn by the app, not picked by the user, so no row may say "you picked" it.
                 let id = item.isPhoto ? "choice.photo" : "choice.notice"
                 return [Candidate(promptID: id, subject: item.subject)]
             }),
    ]

    public static func next(signals: JournalSignals,
                            habits: JournalHabits,
                            today turns: [JournalTurn],
                            language: JournalLanguage) -> JournalStep {
        // A cleared free-writing page is a row for the autosave, not something that happened today.
        let turns = turns.filter { !$0.isBlankFreeWriting }.sorted { $0.index < $1.index }
        let recency = Recency(habits: habits, today: turns)
        let answered = turns.filter { $0.outcome == .answered && $0.kind != .safety }

        // A hit comes before everything else, once; the safety turn recorded after it closes the case.
        let triggered = answered.contains { JournalSafety.needsSafetyLine(answer: $0.answer) }
        if triggered, !turns.contains(where: { $0.kind == .safety }) { return .safety }

        // Free writing is recorded as a closing turn, so it ends the day wherever it comes.
        if JournalProgress.isClosed(turns) { return .done }
        guard turns.contains(where: { $0.kind == .opening }) else {
            return question(of: .opening, signals: signals, recency: recency, language: language) ?? .done
        }

        if !triggered, let request = followUpRequest(after: turns, recency: recency, language: language) {
            return .followUp(request)
        }

        let asked = Set(turns.map(\.kind))
        let supplemental = turns.filter { JournalPromptKind.supplemental.contains($0.kind) }.count
        if supplemental < maxSupplemental, let step = nextSupplemental(signals: signals, habits: habits, recency: recency,
                                                                       asked: asked, language: language) {
            return step
        }
        return question(of: .closing, signals: signals, recency: recency, language: language) ?? .done
    }

    /// The follow-up on the latest real turn, if one is allowed: it was answered, is neither a
    /// follow-up nor the closing, says enough to quote, and the day's allowance is not used up.
    private static func followUpRequest(after turns: [JournalTurn], recency: Recency,
                                        language: JournalLanguage) -> JournalFollowUpRequest? {
        guard let last = turns.last(where: { $0.kind != .safety }),
              last.outcome == .answered,
              ![.followUp, .closing].contains(last.kind),
              last.answer.trimmingCharacters(in: .whitespacesAndNewlines).count >= minimumAnswerLengthForFollowUp,
              turns.filter({ $0.kind == .followUp }).count < maxFollowUpsPerDay,
              let phrase = JournalFollowUp.phrase(in: last.answer, language: language)
        else { return nil }
        // Pool order breaks a tie here, not the day's hash: with no history the stand row stays the
        // default, and the rows then take turns in the order they are written.
        let examples = drawOrder(JournalPool.prompts(of: .followUp), recency: recency, dayKey: nil)
            .compactMap { row in
                JournalPool.render(id: row.id, language: language, fills: [.phrase: phrase])
                    .map { JournalExample(id: row.id, text: $0) }
            }
        guard let first = examples.first else { return nil }
        let fallback = JournalQuestion(promptID: first.id, kind: .followUp, text: first.text)
        let subject = last.subjectKind.flatMap { kind in
            last.subjectID.map { JournalSubject(kind: kind, id: $0, text: last.subjectText) }
        }
        return JournalFollowUpRequest(question: last.questionText, answer: last.answer, subject: subject,
                                      language: language, fallback: fallback,
                                      examples: Array(examples.prefix(JournalQuestionBrief.maxExamples)),
                                      avoid: recency.texts)
    }

    /// The best question about the day that has not been asked, ranked by base score times the
    /// habit weight of its kind; a tie goes to the kind listed first in `rules`.
    private static func nextSupplemental(signals: JournalSignals, habits: JournalHabits, recency: Recency,
                                         asked: Set<JournalPromptKind>, language: JournalLanguage) -> JournalStep? {
        let ranked = rules
            .filter { !asked.contains($0.kind) }
            .compactMap { rule -> (rule: Rule, candidates: [Candidate], rank: Double)? in
                guard let score = rule.score(signals) else { return nil }
                let candidates = rule.candidates(signals)
                guard !candidates.isEmpty else { return nil }
                return (rule, candidates, score * habits.weight(for: rule.kind))
            }
            .enumerated()
            .sorted { ($0.element.rank, -$0.offset) > ($1.element.rank, -$1.offset) }
            .map(\.element)
        for (rule, candidates, _) in ranked {
            let rows = candidates.compactMap { JournalPool.prompt(id: $0.promptID) }
            for row in drawOrder(rows, recency: recency, dayKey: signals.dayKey) {
                guard let pick = candidates.first(where: { $0.promptID == row.id }),
                      let text = JournalPool.render(id: row.id, language: language, fills: pick.fills)
                else { continue }
                let brief = brief(for: rule.kind, fallback: row, fills: pick.fills, signals: signals,
                                  recency: recency, language: language)
                return .ask(JournalQuestion(promptID: row.id, kind: rule.kind, text: text,
                                            subject: pick.subject, brief: brief))
            }
        }
        return nil
    }

    private static func question(of kind: JournalPromptKind, signals: JournalSignals, recency: Recency,
                                 language: JournalLanguage) -> JournalStep? {
        for row in drawOrder(JournalPool.prompts(of: kind), recency: recency, dayKey: signals.dayKey) {
            guard let text = JournalPool.render(id: row.id, language: language) else { continue }
            let brief = brief(for: kind, fallback: row, fills: [:], signals: signals,
                              recency: recency, language: language)
            return .ask(JournalQuestion(promptID: row.id, kind: kind, text: text, brief: brief))
        }
        return nil
    }

    /// What the model needs to word the question `fallback` stands in for. The approach is the
    /// fallback row's, so the shapes rotate with the rows. The examples are every row of the kind
    /// the day can fill in, least recently used first, which is also the order the fallback was drawn in.
    private static func brief(for kind: JournalPromptKind, fallback: JournalPrompt,
                              fills: [JournalPlaceholder: String], signals: JournalSignals,
                              recency: Recency, language: JournalLanguage) -> JournalQuestionBrief {
        let examples = drawOrder(JournalPool.prompts(of: kind), recency: recency, dayKey: signals.dayKey)
            .compactMap { row in
                JournalPool.render(id: row.id, language: language, fills: fills)
                    .map { JournalExample(id: row.id, text: $0) }
            }
        return JournalQuestionBrief(language: language, facts: JournalFacts(signals), approach: fallback.approach,
                                    examples: Array(examples.prefix(JournalQuestionBrief.maxExamples)),
                                    avoid: recency.texts)
    }

    /// When each row was last asked and what was asked lately: the habits' history plus today's
    /// turns, so two follow-ups in one day do not draw the same row or repeat a sentence.
    private struct Recency {
        let lastUsed: [String: String]
        let texts: [String]

        init(habits: JournalHabits, today: [JournalTurn]) {
            var lastUsed = habits.lastUsedDay
            for turn in today where !turn.promptID.isEmpty {
                lastUsed[turn.promptID] = max(lastUsed[turn.promptID] ?? "", turn.dayKey)
            }
            self.lastUsed = lastUsed
            self.texts = today.sorted { $0.index > $1.index }.map(\.questionText).filter { !$0.isEmpty }
                + habits.recentQuestionTexts
        }
    }

    /// `rows` from the one to draw first to the one to draw last: the least recently used first, a
    /// row never used counting as the oldest, and rows that tie starting at a place the hash of
    /// `dayKey` picks and wrapping round (or, with no `dayKey`, at the first in pool order). With no
    /// history that makes the first row `rows[hash % count]`. A row used most recently is last unless
    /// every row ties, so the row asked yesterday is never asked again while another is available.
    private static func drawOrder(_ rows: [JournalPrompt], recency: Recency, dayKey: String?) -> [JournalPrompt] {
        let groups = Dictionary(grouping: rows) { recency.lastUsed[$0.id] ?? "" }
        return groups.keys.sorted().flatMap { key -> [JournalPrompt] in
            let group = groups[key] ?? []
            let start = dayKey.map { Int(stableHash($0) % UInt64(group.count)) } ?? 0
            return Array(group[start...] + group[..<start])
        }
    }

    /// djb2 over the UTF-8 bytes. Swift's `hashValue` is seeded per process, so the same day would
    /// draw a different question after every launch.
    static func stableHash(_ text: String) -> UInt64 {
        text.utf8.reduce(5381 as UInt64) { ($0 &* 33) &+ UInt64($1) }
    }
}
