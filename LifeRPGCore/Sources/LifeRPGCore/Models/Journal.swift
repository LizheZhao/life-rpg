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
/// A row is inserted when the user responds and is never edited afterwards, so a day's journal is
/// the ordered list of its turns; the question in flight lives in the UI. There is deliberately no
/// parent entry: the entry would only ever be a cache of "which turns share a `dayKey`".
///
/// Like every history row the question and subject text are snapshots. `subjectID` is the
/// `DailyQuest` or `RoutineOccurrence` the question was about; those rows keep their ids through
/// export and import, so it needs no re-pointing, and if the row is gone the snapshot still reads.
@Model public final class JournalTurn {
    public var id: UUID = UUID()
    public var dayKey: String = ""
    public var index: Int = 0                     // order within the day
    public var kindRaw: String = JournalPromptKind.opening.rawValue
    /// The pool row, or "" for model-written text and free writing.
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

    public init() {}

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
