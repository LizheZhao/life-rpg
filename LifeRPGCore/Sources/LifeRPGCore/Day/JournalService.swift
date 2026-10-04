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
}
