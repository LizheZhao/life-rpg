import Foundation

/// The day's facts as plain values, so a request can be handed to the model, logged and compared
/// without carrying the quests and ratings behind them.
public struct JournalFacts: Equatable, Sendable {
    /// Where the day's mean rating falls. Coarse on purpose: the model words a question about a
    /// heavy or an easy day and has no use for one decimal.
    public enum RatingBucket: String, Sendable {
        case negative, mixed, positive
    }

    public let tier: Tier
    public let completedCount: Int
    /// Nil when nothing was rated.
    public let ratingBucket: RatingBucket?
    public let hasChoiceItem: Bool
    public let hasPhotoItem: Bool
    public let hasSkippedItem: Bool

    public init(tier: Tier, completedCount: Int, ratingBucket: RatingBucket?,
                hasChoiceItem: Bool, hasPhotoItem: Bool, hasSkippedItem: Bool) {
        self.tier = tier
        self.completedCount = completedCount
        self.ratingBucket = ratingBucket
        self.hasChoiceItem = hasChoiceItem
        self.hasPhotoItem = hasPhotoItem
        self.hasSkippedItem = hasSkippedItem
    }

    /// Mean at or below -0.5 reads negative and at or above 0.5 positive, the same cut the planner
    /// uses for a heavy day.
    public init(_ signals: JournalSignals) {
        let bucket = signals.averageRating.map { average -> RatingBucket in
            average <= -0.5 ? .negative : (average >= 0.5 ? .positive : .mixed)
        }
        self.init(tier: signals.tier, completedCount: signals.completedCount, ratingBucket: bucket,
                  hasChoiceItem: signals.choiceItem != nil,
                  hasPhotoItem: signals.completed.contains(where: \.isPhoto),
                  hasSkippedItem: !signals.skipped.isEmpty)
    }
}

/// A pool row shown to the model as a tone anchor, with its placeholders filled where the day
/// has the value (left as written where it does not).
public struct JournalExample: Equatable, Sendable {
    public let id: String
    public let text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

/// What the model needs to word a fresh question, and what its wording is held against. The
/// planner decides what to ask; the model only phrases it, using `examples` for tone.
public struct JournalQuestionBrief: Equatable, Sendable {
    public let language: JournalLanguage
    public let facts: JournalFacts
    public let approach: JournalApproach
    /// Up to `maxExamples` pool rows of the same kind, the least recently used first.
    public let examples: [JournalExample]
    /// Question texts of the last `JournalHabits.recentQuestionDays` days, newest first, the
    /// model's own included.
    public let avoid: [String]

    public static let maxExamples = 3

    /// Everything a new question must not resemble: the examples it was shown and what was asked lately.
    public var avoiding: [String] { examples.map(\.text) + avoid }

    public init(language: JournalLanguage, facts: JournalFacts, approach: JournalApproach,
                examples: [JournalExample], avoid: [String]) {
        self.language = language
        self.facts = facts
        self.approach = approach
        self.examples = examples
        self.avoid = avoid
    }
}

/// A question ready to show: the pool row it came from and its text with the placeholders filled.
/// `text` is the fallback; `brief` is what the model needs to word something fresher, and is nil
/// for a template follow-up, whose request carries its own examples.
public struct JournalQuestion: Equatable, Sendable {
    public let promptID: String
    public let kind: JournalPromptKind
    public let text: String
    public let subject: JournalSubject?
    public let brief: JournalQuestionBrief?

    public init(promptID: String, kind: JournalPromptKind, text: String, subject: JournalSubject? = nil,
                brief: JournalQuestionBrief? = nil) {
        self.promptID = promptID
        self.kind = kind
        self.text = text
        self.subject = subject
        self.brief = brief
    }
}

/// What the app needs to ask the model for a follow-up, and what to show if it can't or the
/// answer fails `JournalTextCheck.accept`. Only the turn being followed up is in it, so nothing
/// the user wrote earlier can reach the model by accident.
public struct JournalFollowUpRequest: Equatable, Sendable {
    /// What the user was asked.
    public let question: String
    /// What they wrote.
    public let answer: String
    public let subject: JournalSubject?
    public let language: JournalLanguage
    /// The first of `examples` as a question: a follow-up row filled with a quote of the answer,
    /// always valid.
    public let fallback: JournalQuestion
    /// The follow-up rows, least recently used first, as tone anchors.
    public let examples: [JournalExample]
    /// Follow-up texts of the last `JournalHabits.recentQuestionDays` days, newest first.
    public let avoid: [String]

    /// Everything the model's follow-up must not resemble.
    public var avoiding: [String] { examples.map(\.text) + avoid }

    public init(question: String, answer: String, subject: JournalSubject?,
                language: JournalLanguage, fallback: JournalQuestion,
                examples: [JournalExample] = [], avoid: [String] = []) {
        self.question = question
        self.answer = answer
        self.subject = subject
        self.language = language
        self.fallback = fallback
        self.examples = examples
        self.avoid = avoid
    }
}

/// What to do next in a day's journal.
public enum JournalStep: Equatable, Sendable {
    case ask(JournalQuestion)
    /// Offer a follow-up of the last answer: the model's wording if it passes the check, else
    /// `fallback`.
    case followUp(JournalFollowUpRequest)
    /// Show the safety line (`JournalSafety.line`) and record it as a `.safety` turn.
    case safety
    case done
}
