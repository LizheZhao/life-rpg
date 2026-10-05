import Foundation
import SwiftData

/// What a journal question is for. The kind is what the planner ranks and what the habit weights
/// are learned per, so it is stored with every turn.
public enum JournalPromptKind: String, Codable, CaseIterable, Sendable {
    case opening, heavy, good, choice, skip, followUp, closing
    /// The safety line. Recorded when it has been shown, so that "shown once" survives an app kill
    /// without the planner needing any state beyond the day's turns.
    case safety

    /// The kinds that ask about one specific thing from the day, as opposed to the day as a whole.
    public static let supplemental: [JournalPromptKind] = [.skip, .heavy, .good, .choice]
}

/// How the user answered a question. A skipped or misfit turn is still a response: the question
/// has been asked, and the habit weights read the difference.
public enum JournalOutcome: String, Codable, CaseIterable, Sendable {
    case answered, skipped
    /// "This question doesn't fit."
    case misfit
}

/// Who wrote the question text: a pool row, or the on-device model (validated by `JournalTextCheck`).
public enum JournalSource: String, Codable, CaseIterable, Sendable {
    case template, model
}

/// What a question is about: the `DailyQuest` or `RoutineOccurrence` of that day, with its text as
/// it was shown.
public struct JournalSubject: Equatable, Sendable {
    public let kind: FeedbackTarget
    public let id: UUID
    public let text: String

    public init(kind: FeedbackTarget, id: UUID, text: String) {
        self.kind = kind
        self.id = id
        self.text = text
    }
}

/// One question and the user's response to it, on one day.
///
/// A row was inserted when the user responded, and was written once, apart from the free-writing
/// turn the old page autosaved into. The app no longer writes turns: the journal is one
/// `JournalEntry` per day, and `JournalMigration` copies these rows into entries once. The rows stay
/// untouched, and in the export, until a later release drops them. A day's journal was the ordered
/// list of its turns; there is deliberately no parent entry for them.
///
/// Like every history row the question and subject text are snapshots. `subjectID` is the
/// `DailyQuest` or `RoutineOccurrence` the question was about; those rows keep their ids through
/// export and import, so it needs no re-pointing, and if the row is gone the snapshot still reads.
@Model public final class JournalTurn {
    public var id: UUID = UUID()
    public var dayKey: String = ""
    public var index: Int = 0                     // order within the day
    public var kindRaw: String = JournalPromptKind.opening.rawValue
    /// The pool row the question came from or, for a model-worded question, the fallback row it
    /// stands in for (`source` says who wrote the text), so recency and anchor rotation work the
    /// same either way. "" only for free writing, which has no question.
    public var promptID: String = ""
    public var questionText: String = ""
    public var subjectKindRaw: String?            // `FeedbackTarget`
    public var subjectID: UUID?
    public var subjectText: String = ""
    public var answer: String = ""
    public var outcomeRaw: String = JournalOutcome.answered.rawValue
    public var sourceRaw: String = JournalSource.template.rawValue
    public var languageRaw: String = JournalLanguage.en.rawValue
    public var askedAt: Date = Date()
    public var answeredAt: Date = Date()
    /// Seconds spent actively writing this turn's words (`JournalWritingClock`), the running total
    /// of the free-writing page. Only free writing sets it; a questioned turn stays 0.
    ///
    /// Impact on existing data: a new attribute with a default value, which lightweight migration
    /// infers (`SchemaV7`), so every stored turn reads 0 ("no time recorded") and nothing is
    /// rewritten. CloudKit-ready: defaulted, not unique.
    public var writingSeconds: Int = 0

    public init() {}

    /// Free writing: a closing turn with no question and no pool row. One rule for what the free
    /// page owned, so the migration, `JournalProgress` and the planner agree on it.
    public var isFreeWriting: Bool {
        kindRaw == JournalPromptKind.closing.rawValue && questionText.isEmpty && promptID.isEmpty
    }

    /// A free-writing turn whose page was cleared. It stays as a row so the autosave has somewhere
    /// to write, but it is not writing: it composes to nothing and does not close the day.
    public var isBlankFreeWriting: Bool {
        isFreeWriting && answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var kind: JournalPromptKind {
        get { JournalPromptKind(rawValue: kindRaw) ?? .opening }
        set { kindRaw = newValue.rawValue }
    }

    public var subjectKind: FeedbackTarget? {
        get { subjectKindRaw.flatMap(FeedbackTarget.init(rawValue:)) }
        set { subjectKindRaw = newValue?.rawValue }
    }

    public var outcome: JournalOutcome {
        get { JournalOutcome(rawValue: outcomeRaw) ?? .answered }
        set { outcomeRaw = newValue.rawValue }
    }

    public var source: JournalSource {
        get { JournalSource(rawValue: sourceRaw) ?? .template }
        set { sourceRaw = newValue.rawValue }
    }

    public var language: JournalLanguage {
        get { JournalLanguage(rawValue: languageRaw) ?? .en }
        set { languageRaw = newValue.rawValue }
    }
}
