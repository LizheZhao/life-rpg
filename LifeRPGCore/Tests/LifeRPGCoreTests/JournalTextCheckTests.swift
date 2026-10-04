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

    @Test func aQuestionThatOpensWithWhyIsCaught() {
        #expect(found("Why did you skip it?") == [.startsWithWhy])
        #expect(found("You skipped it. Why was that?") == [.startsWithWhy])
        #expect(found("为什么没去？", .zhHans) == [.startsWithWhy])
        // "why" inside a sentence is fine.
        #expect(found("Tell me what you think about why it mattered.") == [])
    }

    @Test func aWallOfTextIsCaughtAtTheNamedCap() {
        #expect(JournalTextCheck.maxLength(.en) == 200)
        #expect(JournalTextCheck.maxLength(.zhHans) == 100)
        #expect(found(String(repeating: "x", count: 200)) == [])
        #expect(found(String(repeating: "x", count: 201)) == [.tooLong])
        #expect(found(String(repeating: "字", count: 100), .zhHans) == [])
        #expect(found(String(repeating: "字", count: 101), .zhHans) == [.tooLong])
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

    /// The check can't be allowed to reject the app's own questions. Three hand-written rows are
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
        let twoPart = ["open.scale", "choice.photo", "skip.exception"]
        #expect(Set(failing.keys) == Set(twoPart.flatMap { ["\($0).en", "\($0).zh-Hans"] }))
        #expect(failing.values.allSatisfy { $0 == [.manyQuestions] })
    }

    @Test func aRenderedFollowUpPasses() throws {
        for language in JournalLanguage.allCases {
            let question = try #require(JournalFollowUp.template(
                answer: "I walked home in the rain and it felt good, mostly.", language: language))
            #expect(found(question.text, language) == [], "\(question.text)")
        }
    }

    // MARK: accept

    @Test func aCleanReflectionBuiltFromTheirWordsIsAccepted() {
        let answer = "I walked home and it was quiet and nice"
        #expect(JournalTextCheck.accept(reflection: "You said it was quiet.",
                                        question: "What stands out about the quiet?",
                                        answer: answer, language: .en))
        #expect(JournalTextCheck.accept(reflection: "你说走路回家很安静。",
                                        question: "安静让你想到什么？",
                                        answer: "今天走路回家，很安静", language: .zhHans))
    }

    @Test func aParaphraseIsRejectedEvenWhenItIsClean() {
        let answer = "I walked home and it was quiet and nice"
        #expect(!JournalTextCheck.accept(reflection: "Sounds like a peaceful evening.",
                                         question: "What stands out about that?",
                                         answer: answer, language: .en))
        // One shared word is not a run of two.
        #expect(!JournalTextCheck.accept(reflection: "Quiet evenings matter.",
                                         question: "What stands out?", answer: answer, language: .en))
        #expect(!JournalTextCheck.accept(reflection: "听起来是个平静的夜晚。", question: "最在意什么？",
                                         answer: "今天走路回家，很安静", language: .zhHans))
    }

    @Test func aReflectionThatBreaksARuleIsRejectedEvenWhenItQuotes() {
        let answer = "I walked home and it was quiet and nice"
        #expect(!JournalTextCheck.accept(reflection: "It's not just that it was quiet, but that you walked home.",
                                         question: "What stands out?", answer: answer, language: .en))
        #expect(!JournalTextCheck.accept(reflection: "You said it was quiet.",
                                         question: "What stands out? What else?", answer: answer, language: .en))
        #expect(!JournalTextCheck.accept(reflection: "You said it was quiet.",
                                         question: "Why was it quiet?", answer: answer, language: .en))
    }

    @Test func aQuestionWithoutAQuestionMarkIsRejected() {
        #expect(!JournalTextCheck.accept(reflection: "You said it was quiet.",
                                         question: "Tell me more about the quiet.",
                                         answer: "I walked home and it was quiet and nice", language: .en))
    }
}
