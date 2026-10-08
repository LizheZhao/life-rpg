import Foundation

/// The on-device model as Core sees it. The app supplies the Foundation Models implementation;
/// Core only knows this protocol, so the one rule about when the model's wording is trusted lives
/// in `JournalAsk` and is tested with a fake. A `nil` return means the model is unavailable,
/// failed, or has nothing to say, and is never an error to report.
public protocol JournalWording: Sendable {
    /// A fresh question from `JournalAsk.request`.
    func word(instructions: String, prompt: String) async -> String?
    /// Loads what the model needs ahead of the first `word`, so that call fits the timeout.
    func prewarm()
}

extension JournalWording {
    public func prewarm() {}
}

/// Waiting for the model without being held by it.
public enum JournalConversation {
    /// `work`'s result, or nil once `timeout` has passed. The two run as separate tasks that race
    /// to resume one continuation, so a model that ignores cancellation cannot hold the caller
    /// past the timeout the way a task group (which waits for every child) would.
    static func raced<T: Sendable>(_ timeout: Duration,
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
