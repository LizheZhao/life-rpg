import Foundation
import Testing
@testable import LifeRPGCore

/// `JournalConversation` is the one place that decides whether the model's wording is shown, so the
/// tests play it against a fake wording. 2026-09-18 draws `open.keep` first (2 mod 3), which is the
/// literal fallback below.
struct JournalConversationTests {
    typealias F = JournalFixtures

    /// A model that is stuck until the test lets go of it, so "still stalled" is a fact the test
    /// controls instead of a wall-clock bound that parallel test load can overrun.
    private final class Stall: @unchecked Sendable {
        private let lock = NSLock()
        private var open = false
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            await withCheckedContinuation { c in
                lock.lock()
                if open { lock.unlock(); c.resume() } else { waiting.append(c); lock.unlock() }
            }
        }

        func release() {
            lock.lock()
            open = true
            let all = waiting
            waiting = []
            lock.unlock()
            all.forEach { $0.resume() }
        }
    }

    /// Replies as scripted, counts its calls, and can stall on `stall` without honouring cancellation.
    private final class FakeWording: JournalWording, @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        let question: String?
        let followUp: (reflection: String, question: String)?
        let stall: Stall?
        private(set) var instructions: [String] = []
        private(set) var prompts: [String] = []

        init(question: String? = nil, followUp: (reflection: String, question: String)? = nil, stall: Stall? = nil) {
            self.question = question
            self.followUp = followUp
            self.stall = stall
        }

        var callCount: Int { lock.withLock { calls } }

        private func record(_ instructions: String, _ prompt: String) async {
            lock.withLock {
                calls += 1
                self.instructions.append(instructions)
                prompts.append(prompt)
            }
            await stall?.wait()
        }

        func word(instructions: String, prompt: String) async -> String? {
            await record(instructions, prompt)
            return question
        }

        func wordFollowUp(instructions: String, prompt: String) async -> (reflection: String, question: String)? {
            await record(instructions, prompt)
            return followUp
        }
    }

    /// `work`'s result, or nil if it has not returned after `ceiling`. Only a regression reaches the
    /// ceiling (a `present` that waits for the stalled model never returns), so it turns that hang
    /// into a failed expectation; a passing run returns as soon as `work` does.
    private func returns<T: Sendable>(within ceiling: Duration, _ work: @escaping @Sendable () async -> T) async -> T? {
        let (results, out) = AsyncStream<T?>.makeStream()
        Task { out.yield(await work()) }
        let timer = Task {
            try? await Task.sleep(for: ceiling)
            out.yield(nil)
        }
        defer { timer.cancel() }
        for await first in results { return first }
        return nil
    }

    private func opening() throws -> JournalQuestion {
        guard case .ask(let q) = JournalPlanner.next(signals: F.signals(), habits: .none, today: [], language: .en)
        else { throw Failure.noQuestion }
        return q
    }

    private func followUpRequest() throws -> JournalFollowUpRequest {
        let opening = F.turn(.opening, "That one went better than I expected.", index: 0)
        guard case .followUp(let request) = JournalPlanner.next(signals: F.signals(), habits: .none,
                                                                today: [opening], language: .en)
        else { throw Failure.noQuestion }
        return request
    }

    private enum Failure: Error { case noQuestion }

    private func present(_ q: JournalQuestion, _ wording: (any JournalWording)?,
                         timeout: Duration = .seconds(5)) async -> JournalPresented {
        await JournalConversation.present(q, signals: F.signals(), habits: .none, wording: wording, timeout: timeout)
    }

    private func present(_ r: JournalFollowUpRequest, _ wording: (any JournalWording)?,
                         timeout: Duration = .seconds(5)) async -> JournalPresented {
        await JournalConversation.present(r, signals: F.signals(), habits: .none, wording: wording, timeout: timeout)
    }

    // MARK: a plain question

    @Test func aCleanFreshQuestionFromTheModelIsShownAndKeepsTheFallbackRowsId() async throws {
        let q = try opening()
        #expect(q.promptID == "open.keep")
        let wording = FakeWording(question: "What from this evening would you like to hold onto?")
        let shown = await present(q, wording)
        #expect(shown == JournalPresented(text: "What from this evening would you like to hold onto?",
                                          source: .model, promptID: "open.keep"))
        #expect(wording.callCount == 1)
    }

    @Test func theModelIsHandedTheQuestionInstructionsAndTheBriefsPrompt() async throws {
        let q = try opening()
        let wording = FakeWording(question: "What from this evening would you like to hold onto?")
        _ = await present(q, wording)
        #expect(wording.instructions == [JournalPromptBuilder.questionInstructions(language: .en)])
        #expect(wording.prompts == [JournalPromptBuilder.questionPrompt(q, signals: F.signals(), habits: .none)])
    }

    @Test func wordingThatCopiesAnAnchorFallsBackToTheRowItCameFrom() async throws {
        let q = try opening()
        let anchor = try #require(q.brief?.examples.last?.text)
        let wording = FakeWording(question: anchor)
        let shown = await present(q, wording)
        #expect(shown == JournalPresented(text: "What from today do you want to remember?",
                                          source: .template, promptID: "open.keep"))
        #expect(wording.callCount == 1)
    }

    @Test func wordingThatBreaksAVoiceRuleFallsBackAndIsNotRetried() async throws {
        let q = try opening()
        let wording = FakeWording(question: "Why did today feel so long?")
        let shown = await present(q, wording)
        #expect(shown.source == .template)
        #expect(shown.text == q.text)
        #expect(wording.callCount == 1)
    }

    @Test func aNilWordingMeansTheFallback() async throws {
        let q = try opening()
        let shown = await present(q, FakeWording(question: nil))
        #expect(shown == JournalPresented(text: q.text, source: .template, promptID: "open.keep"))
    }

    @Test func noModelAtAllMeansTheFallbackWithoutAsking() async throws {
        let q = try opening()
        let shown = await present(q, nil)
        #expect(shown == JournalPresented(text: q.text, source: .template, promptID: "open.keep"))
    }

    /// The model is released only after `present` has returned, so a `present` that waited for it
    /// would never return.
    @Test func aModelThatHangsPastTheTimeoutFallsBackWithoutWaitingForIt() async throws {
        let q = try opening()
        let stall = Stall()
        let wording = FakeWording(question: "What from this evening would you like to hold onto?", stall: stall)
        let shown = await returns(within: .seconds(30)) { await present(q, wording, timeout: .milliseconds(100)) }
        stall.release()
        #expect(shown == JournalPresented(text: q.text, source: .template, promptID: "open.keep"))
        #expect(wording.callCount == 1)
    }

    @Test func aQuestionWithoutABriefIsNeverSentToTheModel() async throws {
        let template = JournalQuestion(promptID: "follow.stand", kind: .followUp, text: "Say more about \"it\".")
        let wording = FakeWording(question: "What from this evening would you like to hold onto?")
        let shown = await present(template, wording)
        #expect(shown == JournalPresented(text: template.text, source: .template, promptID: "follow.stand"))
        #expect(wording.callCount == 0)
    }

    @Test func theChineseQuestionIsCheckedAndInstructedInChinese() async throws {
        guard case .ask(let q) = JournalPlanner.next(signals: F.signals(), habits: .none, today: [], language: .zhHans)
        else { throw Failure.noQuestion }
        let wording = FakeWording(question: "今晚有哪一刻你想多留一会儿？")
        let shown = await present(q, wording)
        #expect(shown == JournalPresented(text: "今晚有哪一刻你想多留一会儿？", source: .model, promptID: q.promptID))
        #expect(wording.instructions == [JournalPromptBuilder.questionInstructions(language: .zhHans)])
    }

    // MARK: a follow-up

    @Test func aFollowUpTheModelWordsWellIsStoredAsReflectionThenQuestion() async throws {
        let request = try followUpRequest()
        let wording = FakeWording(followUp: ("It went better than you hoped.", "What made the difference?"))
        let shown = await present(request, wording)
        #expect(shown == JournalPresented(text: "It went better than you hoped. What made the difference?",
                                          source: .model, promptID: "follow.stand"))
        #expect(wording.callCount == 1)
        #expect(wording.instructions == [JournalPromptBuilder.instructions(language: .en)])
    }

    @Test func aFollowUpThatDoesNotReuseTheUsersWordsFallsBackToTheTemplate() async throws {
        let request = try followUpRequest()
        let wording = FakeWording(followUp: ("Good to hear.", "What made the difference?"))
        let shown = await present(request, wording)
        #expect(shown == JournalPresented(text: request.fallback.text, source: .template, promptID: "follow.stand"))
        #expect(wording.callCount == 1)
    }

    @Test func aFollowUpThatCopiesAnAnchorFallsBack() async throws {
        let request = try followUpRequest()
        let anchor = try #require(request.examples.first?.text)
        let wording = FakeWording(followUp: ("It went better than you hoped.", anchor))
        let shown = await present(request, wording)
        #expect(shown.source == .template)
    }

    @Test func aFollowUpTheModelDoesNotAnswerFallsBack() async throws {
        let request = try followUpRequest()
        let shown = await present(request, FakeWording(followUp: nil))
        #expect(shown == JournalPresented(text: request.fallback.text, source: .template, promptID: "follow.stand"))
    }

    @Test func aFollowUpModelThatHangsFallsBack() async throws {
        let request = try followUpRequest()
        let stall = Stall()
        let wording = FakeWording(followUp: ("It went better than you hoped.", "What made the difference?"), stall: stall)
        let shown = await returns(within: .seconds(30)) { await present(request, wording, timeout: .milliseconds(100)) }
        stall.release()
        #expect(shown?.source == .template)
        #expect(wording.callCount == 1)
    }

    @Test func aFollowUpWithNoModelIsTheTemplate() async throws {
        let request = try followUpRequest()
        let shown = await present(request, nil)
        #expect(shown == JournalPresented(text: request.fallback.text, source: .template, promptID: "follow.stand"))
    }
}
