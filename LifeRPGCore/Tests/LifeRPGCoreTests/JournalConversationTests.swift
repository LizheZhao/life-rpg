import Foundation
import Testing
@testable import LifeRPGCore

/// `JournalConversation` is the one place that decides whether the model's wording is shown, so the
/// tests play it against a fake wording. 2026-09-18 draws `open.keep` first (2 mod 3), which is the
/// literal fallback below.
struct JournalConversationTests {
    typealias F = JournalFixtures

    /// Replies as scripted, counts its calls, and can stall for `delay` without honouring cancellation.
    private final class FakeWording: JournalWording, @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        let question: String?
        let followUp: (reflection: String, question: String)?
        let delay: TimeInterval
        private(set) var instructions: [String] = []
        private(set) var prompts: [String] = []

        init(question: String? = nil, followUp: (reflection: String, question: String)? = nil, delay: TimeInterval = 0) {
            self.question = question
            self.followUp = followUp
            self.delay = delay
        }

        var callCount: Int { lock.withLock { calls } }

        private func record(_ instructions: String, _ prompt: String) async {
            lock.withLock {
                calls += 1
                self.instructions.append(instructions)
                prompts.append(prompt)
            }
            if delay > 0 {
                await withCheckedContinuation { c in
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) { c.resume() }
                }
            }
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

    @Test func aModelThatHangsPastTheTimeoutFallsBackWithoutWaitingForIt() async throws {
        let q = try opening()
        let wording = FakeWording(question: "What from this evening would you like to hold onto?", delay: 2)
        let started = Date()
        let shown = await present(q, wording, timeout: .milliseconds(100))
        #expect(shown == JournalPresented(text: q.text, source: .template, promptID: "open.keep"))
        #expect(Date().timeIntervalSince(started) < 1.5, "returned only after the stalled model finished")
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
        let wording = FakeWording(followUp: ("It went better than you hoped.", "What made the difference?"), delay: 2)
        let shown = await present(request, wording, timeout: .milliseconds(100))
        #expect(shown.source == .template)
        #expect(wording.callCount == 1)
    }

    @Test func aFollowUpWithNoModelIsTheTemplate() async throws {
        let request = try followUpRequest()
        let shown = await present(request, nil)
        #expect(shown == JournalPresented(text: request.fallback.text, source: .template, promptID: "follow.stand"))
    }
}
