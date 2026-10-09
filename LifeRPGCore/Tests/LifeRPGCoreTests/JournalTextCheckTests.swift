import Foundation
import Testing
@testable import LifeRPGCore

struct JournalTextCheckTests {
    private func found(_ text: String, _ language: JournalLanguage = .en) -> [JournalTextCheck.Violation] {
        JournalTextCheck.violations(of: text, language: language)
    }

    // MARK: each tell is caught

    @Test func contrastStagingIsCaughtInEnglish() {
        #expect(found("It's not just about the workout, but about how you feel.") == [.contrastStaging])
        #expect(found("It\u{2019}s not the workout, it\u{2019}s the way you feel.") == [.contrastStaging])
        #expect(found("This does not mean you failed. It means you were tired.") == [.contrastStaging])
    }

    @Test func stagedOpenersAndClosersAreCaught() {
        #expect(found("Honestly? That sounds hard.") == [.stagedOpener])
        #expect(found("Let's dive into your evening.") == [.stagedOpener])
        #expect(found("Here's the thing about rest.") == [.stagedOpener])
        #expect(found("Real talk: you did enough.") == [.stagedOpener])
        #expect(found("That is the real win.") == [.stagedCloser])
        #expect(found("Read that again.") == [.stagedCloser])
        #expect(found("Let that sink in.") == [.stagedCloser])
    }

    @Test func aLongDashIsCaughtInBothLanguages() {
        #expect(found("You did the walk \u{2014} that counts.") == [.emDash])
        #expect(found("你做到了——很好。", .zhHans) == [.emDash])
    }

    @Test func chineseTellsAreCaught() {
        #expect(found("这不是失败，而是休息。", .zhHans) == [.contrastStaging])
        #expect(found("这不只是运动，更是照顾自己。", .zhHans) == [.contrastStaging])
        #expect(found("说实话，你已经很努力了。", .zhHans) == [.stagedOpener])
        #expect(found("这正是你需要的。", .zhHans) == [.stagedCloser])
    }

    @Test func moreThanOneQuestionIsCaught() {
        #expect(found("What happened? How did it feel?") == [.manyQuestions])
        #expect(found("你累吗？想休息吗？", .zhHans) == [.manyQuestions])
        #expect(found("What happened?") == [])
    }

    @Test func aQuestionThatAsksWhyIsCaught() {
        #expect(found("Why did you skip it?") == [.asksWhy])
        #expect(found("You skipped it. Why was that?") == [.asksWhy])
        #expect(found("为什么没去？", .zhHans) == [.asksWhy])
        // Anywhere in the question, not only at its start: the model wrote this one.
        #expect(found("What did you think of today, and why did you skip piano practice?") == [.asksWhy])
        #expect(found("今天怎么样，为什么没练琴？", .zhHans) == [.asksWhy])
        #expect(found("What was the walk like?") == [])
        // Inside a sentence it still asks for a reason.
        #expect(found("Tell me what you think about why it mattered.") == [.asksWhy])
    }

    @Test func markdownMarkersAreCaught() {
        #expect(found("**Great** day") == [.markdown])
        #expect(found("# A heading") == [.markdown])
        #expect(found("- first thing") == [.markdown])
        #expect(found("Use `this`.") == [.markdown])
    }

    @Test func aTellOfAnotherLanguageIsNotApplied() {
        // The English tells are not run on Chinese text and the other way round.
        #expect(found("Let's dive in", .zhHans) == [])
        #expect(found("这不是失败，而是休息。") == [])
    }

    // MARK: the pool must pass

    /// The check can't be allowed to reject the app's own questions. Two hand-written rows are
    /// deliberate two-part questions, so the one-question rule is the only thing that fires on them,
    /// and on nothing else: any other violation in the pool fails here.
    @Test func thePoolPassesTheCheck() {
        var failing: [String: [JournalTextCheck.Violation]] = [:]
        for row in JournalPool.all {
            for language in JournalLanguage.allCases {
                let violations = found(row.text(in: language), language)
                if !violations.isEmpty { failing["\(row.id).\(language.rawValue)"] = violations }
            }
        }
        let twoPart = ["open.scale", "skip.exception"]
        #expect(Set(failing.keys) == Set(twoPart.flatMap { ["\($0).en", "\($0).zh-Hans"] }))
        #expect(failing.values.allSatisfy { $0 == [.manyQuestions] })
    }
}
