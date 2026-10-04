import Foundation
import SwiftData

/// Reading and writing the journal log.
///
/// A turn is inserted when the user responds and is written once. The only change afterwards is
/// `edit`, which rewrites the words of an answered turn and nothing else; nothing here deletes one.
/// Does not save, as `Feedback.rate` does not; the caller saves once.
public enum JournalService {
    /// Appends the next turn of `dayKey`. The index continues from the day's last, so a turn
    /// recorded after an app kill lands after the ones already stored.
    @discardableResult
    public static func record(_ context: ModelContext,
                              dayKey: String,
                              kind: JournalPromptKind,
                              promptID: String = "",
                              question: String,
                              subject: JournalSubject? = nil,
                              answer: String = "",
                              outcome: JournalOutcome = .answered,
                              source: JournalSource = .template,
                              language: JournalLanguage,
                              askedAt: Date,
                              answeredAt: Date) throws -> JournalTurn {
        let row = JournalTurn()
        row.dayKey = dayKey
        row.index = (try turns(on: dayKey, in: context).last?.index ?? -1) + 1
        row.kind = kind
        row.promptID = promptID
        row.questionText = question
        row.subjectKind = subject?.kind
        row.subjectID = subject?.id
        row.subjectText = subject?.text ?? ""
        row.answer = answer
        row.outcome = outcome
        row.source = source
        row.language = language
        row.askedAt = askedAt
        row.answeredAt = answeredAt
        context.insert(row)
        return row
    }

    /// Rewrites the words of an answered turn. The answer is trimmed; every other field stays, so the
    /// turn keeps its place, its question and the time it was first answered. Clearing an answer is
    /// not an edit (`.empty`), and the safety line was never the user's words (`.notEditable`, as is
    /// a skipped or misfit turn, which has no words to change). The same text is a no-op.
    @discardableResult
    public static func edit(_ turn: JournalTurn, answer: String) throws -> JournalTurn {
        guard turn.outcome == .answered, turn.kind != .safety else { throw JournalEditError.notEditable }
        let words = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { throw JournalEditError.empty }
        if words != turn.answer { turn.answer = words }
        return turn
    }

    /// The day's turns in the order they were asked.
    public static func turns(on dayKey: String, in context: ModelContext) throws -> [JournalTurn] {
        try context.fetch(FetchDescriptor<JournalTurn>(
            predicate: #Predicate { $0.dayKey == dayKey },
            sortBy: [SortDescriptor(\.index)]))
    }

    /// The day's facts, read from the history rows the same way `DayRecord` reads them.
    public static func signals(on dayKey: String, in context: ModelContext,
                               timeZone: TimeZone = .current) throws -> JournalSignals {
        let skipKind = Economy.Kind.skip.rawValue
        let flexible = Set(try context.fetch(FetchDescriptor<RoutineTask>()).filter(\.flexibleWithinWeek).map(\.id))
        return JournalSignals(
            dayKey: dayKey,
            quests: try DayService.quests(on: dayKey, in: context),
            occurrences: try context.fetch(FetchDescriptor<RoutineOccurrence>()),
            context: try DayService.dailyContext(for: dayKey, in: context),
            ratings: try context.fetch(FetchDescriptor<QuestRating>()),
            comments: try context.fetch(FetchDescriptor<QuestComment>(
                predicate: #Predicate { $0.dayKey == dayKey })),
            ledger: try context.fetch(FetchDescriptor<LedgerEntry>(
                predicate: #Predicate { $0.kind == skipKind && $0.dayKey == dayKey })),
            flexible: flexible,
            timeZone: timeZone)
    }

    /// What past turns say about how the user writes, as of the start of `dayKey`.
    public static func habits(asOf dayKey: String, in context: ModelContext,
                              timeZone: TimeZone = .current) throws -> JournalHabits {
        let since = DayKey.adding(-JournalHabits.windowDays, to: dayKey, in: timeZone) ?? dayKey
        let history = try context.fetch(FetchDescriptor<JournalTurn>(
            predicate: #Predicate { $0.dayKey >= since && $0.dayKey < dayKey }))
        return JournalHabits.derive(from: history, asOf: dayKey, timeZone: timeZone)
    }

    /// What to ask next on `dayKey`, from the store alone.
    public static func next(on dayKey: String, in context: ModelContext, language: JournalLanguage,
                            timeZone: TimeZone = .current) throws -> JournalStep {
        JournalPlanner.next(signals: try signals(on: dayKey, in: context, timeZone: timeZone),
                            habits: try habits(asOf: dayKey, in: context, timeZone: timeZone),
                            today: try turns(on: dayKey, in: context),
                            language: language)
    }
}

public enum JournalEditError: Error, Equatable, Sendable {
    /// The result has nothing in it.
    case empty
    /// A skipped or misfit turn, or the safety line.
    case notEditable
}
