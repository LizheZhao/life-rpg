import Foundation

/// Decides what the journal asks next.
///
/// A pure function of the day's signals and the turns recorded so far, so asking twice gives the
/// same answer and an app kill in the middle of a day's journal resumes where it stopped: there is
/// no cursor to lose. The model never chooses a question, only words a follow-up.
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
             score: { signals in signals.bestRated.map { 2 + 0.5 * Double(($0.rating ?? 1) - 1) } },
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
                 // With a drawn value the row that names it; without one, a row that needs none.
                 let variant = item.variant.flatMap { $0.isEmpty ? nil : $0 }
                 let id = variant == nil ? (item.isPhoto ? "choice.photo" : "choice.notice") : "choice.item"
                 return [Candidate(promptID: id, fills: variant.map { [.item: $0] } ?? [:], subject: item.subject)]
             }),
    ]

    public static func next(signals: JournalSignals,
                            habits: JournalHabits,
                            today turns: [JournalTurn],
                            language: JournalLanguage) -> JournalStep {
        let turns = turns.sorted { $0.index < $1.index }
        let answered = turns.filter { $0.outcome == .answered && $0.kind != .safety }

        // A hit comes before everything else, once; the safety turn recorded after it closes the case.
        let triggered = answered.contains { JournalSafety.needsSafetyLine(answer: $0.answer) }
        if triggered, !turns.contains(where: { $0.kind == .safety }) { return .safety }

        // Free writing is recorded as a closing turn, so it ends the day wherever it comes.
        if turns.contains(where: { $0.kind == .closing }) { return .done }
        guard turns.contains(where: { $0.kind == .opening }) else {
            return question(from: JournalPool.prompts(of: .opening), signals: signals, language: language) ?? .done
        }

        if !triggered, let request = followUpRequest(after: turns, language: language) {
            return .followUp(request)
        }

        let asked = Set(turns.map(\.kind))
        let supplemental = turns.filter { JournalPromptKind.supplemental.contains($0.kind) }.count
        if supplemental < maxSupplemental, let step = nextSupplemental(signals: signals, habits: habits,
                                                                       asked: asked, language: language) {
            return step
        }
        return question(from: JournalPool.prompts(of: .closing), signals: signals, language: language) ?? .done
    }

    /// The follow-up on the latest real turn, if one is allowed: it was answered, is neither a
    /// follow-up nor the closing, says enough to quote, and the day's allowance is not used up.
    private static func followUpRequest(after turns: [JournalTurn], language: JournalLanguage) -> JournalFollowUpRequest? {
        guard let last = turns.last(where: { $0.kind != .safety }),
              last.outcome == .answered,
              ![.followUp, .closing].contains(last.kind),
              last.answer.trimmingCharacters(in: .whitespacesAndNewlines).count >= minimumAnswerLengthForFollowUp,
              turns.filter({ $0.kind == .followUp }).count < maxFollowUpsPerDay,
              let fallback = JournalFollowUp.template(answer: last.answer, language: language)
        else { return nil }
        let subject = last.subjectKind.flatMap { kind in
            last.subjectID.map { JournalSubject(kind: kind, id: $0, text: last.subjectText) }
        }
        return JournalFollowUpRequest(question: last.questionText, answer: last.answer, subject: subject,
                                      language: language, fallback: fallback)
    }

    /// The best question about the day that has not been asked, ranked by base score times the
    /// habit weight of its kind; a tie goes to the kind listed first in `rules`.
    private static func nextSupplemental(signals: JournalSignals, habits: JournalHabits,
                                         asked: Set<JournalPromptKind>, language: JournalLanguage) -> JournalStep? {
        let ranked = rules
            .filter { !asked.contains($0.kind) }
            .compactMap { rule -> (rule: Rule, rank: Double)? in
                guard let score = rule.score(signals), !rule.candidates(signals).isEmpty else { return nil }
                return (rule, score * habits.weight(for: rule.kind))
            }
            .enumerated()
            .sorted { ($0.element.rank, -$0.offset) > ($1.element.rank, -$1.offset) }
            .map(\.element.rule)
        for rule in ranked {
            let pool = rule.candidates(signals)
            let pick = pool[Int(stableHash(signals.dayKey) % UInt64(pool.count))]
            if let text = JournalPool.render(id: pick.promptID, language: language, fills: pick.fills) {
                return .ask(JournalQuestion(promptID: pick.promptID, kind: rule.kind, text: text, subject: pick.subject))
            }
        }
        return nil
    }

    private static func question(from rows: [JournalPrompt], signals: JournalSignals,
                                 language: JournalLanguage) -> JournalStep? {
        guard !rows.isEmpty else { return nil }
        let row = rows[Int(stableHash(signals.dayKey) % UInt64(rows.count))]
        return JournalPool.render(id: row.id, language: language)
            .map { .ask(JournalQuestion(promptID: row.id, kind: row.kind, text: $0)) }
    }

    /// djb2 over the UTF-8 bytes. Swift's `hashValue` is seeded per process, so the same day would
    /// draw a different question after every launch.
    static func stableHash(_ text: String) -> UInt64 {
        text.utf8.reduce(5381 as UInt64) { ($0 &* 33) &+ UInt64($1) }
    }
}
