import Foundation

/// The on-device model as Core sees it. The app supplies the Foundation Models implementation;
/// Core only knows this protocol, so the one rule about when the model's wording is trusted lives
/// here and is tested with a fake. A `nil` return means the model is unavailable, failed, or has
/// nothing to say, and is never an error to report.
public protocol JournalWording: Sendable {
    /// A fresh question from `JournalPromptBuilder.questionPrompt`.
    func word(instructions: String, prompt: String) async -> String?
    /// A reflection and a question from `JournalPromptBuilder.followUpPrompt`.
    func wordFollowUp(instructions: String, prompt: String) async -> (reflection: String, question: String)?
}

/// What the user is shown, and what to record with it.
public struct JournalPresented: Equatable, Sendable {
    /// For a follow-up the model's reflection and question joined with a space, so the stored text
    /// is exactly what was on screen.
    public let text: String
    public let source: JournalSource
    /// Always the pool row the fallback came from, even when the model wrote `text`: recency and
    /// the choice of anchors rotate by row, and `source` already says who wrote the words.
    public let promptID: String

    public init(text: String, source: JournalSource, promptID: String) {
        self.text = text
        self.source = source
        self.promptID = promptID
    }
}

/// Decides, for one question, whether to show the model's wording or the pool fallback, so the
/// view never makes that call.
///
/// The model is asked once. It may be absent, slow, fail, or write something `JournalTextCheck`
/// rejects; every one of those shows the fallback, and nothing is retried: a second attempt costs
/// the user another wait for wording that is only ever a nicety over a row that is always valid.
public enum JournalConversation {
    /// A slower model is treated as unavailable: the user is waiting on a screen for the question.
    public static let defaultTimeout: Duration = .seconds(8)

    public static func present(_ question: JournalQuestion,
                               signals: JournalSignals,
                               habits: JournalHabits,
                               wording: (any JournalWording)?,
                               timeout: Duration = defaultTimeout) async -> JournalPresented {
        let fallback = JournalPresented(text: question.text, source: .template, promptID: question.promptID)
        guard let wording, let brief = question.brief,
              let prompt = JournalPromptBuilder.questionPrompt(question, signals: signals, habits: habits)
        else { return fallback }

        let instructions = JournalPromptBuilder.questionInstructions(language: brief.language)
        guard let raw = await raced(timeout, { await wording.word(instructions: instructions, prompt: prompt) })
        else { return fallback }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard JournalTextCheck.acceptQuestion(text, language: brief.language, avoiding: brief.avoiding)
        else { return fallback }
        return JournalPresented(text: text, source: .model, promptID: question.promptID)
    }

    public static func present(_ request: JournalFollowUpRequest,
                               signals: JournalSignals,
                               habits: JournalHabits,
                               wording: (any JournalWording)?,
                               timeout: Duration = defaultTimeout) async -> JournalPresented {
        let fallback = JournalPresented(text: request.fallback.text, source: .template,
                                        promptID: request.fallback.promptID)
        guard let wording else { return fallback }

        let language = request.language
        let instructions = JournalPromptBuilder.instructions(language: language)
        let prompt = JournalPromptBuilder.followUpPrompt(request, signals: signals, habits: habits)
        guard let worded = await raced(timeout, { await wording.wordFollowUp(instructions: instructions, prompt: prompt) })
        else { return fallback }
        let reflection = worded.reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        let question = worded.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard JournalTextCheck.accept(reflection: reflection, question: question, answer: request.answer,
                                      language: language, avoiding: request.avoiding)
        else { return fallback }
        return JournalPresented(text: reflection + " " + question, source: .model,
                                promptID: request.fallback.promptID)
    }

    /// `work`'s result, or nil once `timeout` has passed. The two run as separate tasks that race
    /// to resume one continuation, so a model that ignores cancellation cannot hold the caller
    /// past the timeout the way a task group (which waits for every child) would.
    private static func raced<T: Sendable>(_ timeout: Duration,
                                           _ work: @escaping @Sendable () async -> T?) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let gate = Gate(continuation)
            let worker = Task { gate.finish(await work()) }
            let timer = Task {
                try? await Task.sleep(for: timeout)
                gate.finish(nil)
            }
            gate.attach([worker, timer])
        }
    }

    /// Resumes its continuation once, then cancels both tasks; later calls are ignored.
    private final class Gate<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T?, Never>?
        private var tasks: [Task<Void, Never>] = []

        init(_ continuation: CheckedContinuation<T?, Never>) {
            self.continuation = continuation
        }

        /// Tasks start before they can be attached, so one may already have finished the race.
        func attach(_ tasks: [Task<Void, Never>]) {
            lock.lock()
            let done = continuation == nil
            if !done { self.tasks = tasks }
            lock.unlock()
            if done { tasks.forEach { $0.cancel() } }
        }

        func finish(_ value: T?) {
            lock.lock()
            let pending = continuation
            continuation = nil
            let running = tasks
            lock.unlock()
            guard let pending else { return }
            pending.resume(returning: value)
            running.forEach { $0.cancel() }
        }
    }
}
