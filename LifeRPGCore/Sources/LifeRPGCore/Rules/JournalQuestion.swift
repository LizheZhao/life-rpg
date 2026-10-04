import Foundation

/// A question ready to show: the pool row it came from and its text with the placeholders filled.
public struct JournalQuestion: Equatable, Sendable {
    public let promptID: String
    public let kind: JournalPromptKind
    public let text: String
    public let subject: JournalSubject?

    public init(promptID: String, kind: JournalPromptKind, text: String, subject: JournalSubject? = nil) {
        self.promptID = promptID
        self.kind = kind
        self.text = text
        self.subject = subject
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
    /// The template follow-up built from the same answer: always valid.
    public let fallback: JournalQuestion

    public init(question: String, answer: String, subject: JournalSubject?,
                language: JournalLanguage, fallback: JournalQuestion) {
        self.question = question
        self.answer = answer
        self.subject = subject
        self.language = language
        self.fallback = fallback
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
