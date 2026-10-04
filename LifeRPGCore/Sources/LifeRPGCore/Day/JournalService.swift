import Foundation
import SwiftData

/// Reading and writing the journal log.
///
/// Like the rating log it is append-only: a turn is inserted when the user responds and nothing
/// here edits or deletes one. Does not save, as `Feedback.rate` does not; the caller saves once.
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
