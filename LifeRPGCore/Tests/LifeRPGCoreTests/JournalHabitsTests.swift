import Foundation
import Testing
@testable import LifeRPGCore

struct JournalHabitsTests {
    typealias F = JournalFixtures
    private let today = "2026-09-18"

    private func derive(_ turns: [JournalTurn]) -> JournalHabits {
        JournalHabits.derive(from: turns, asOf: today, timeZone: Fixtures.tokyo)
    }

    private func turn(_ kind: JournalPromptKind, _ answer: String = "fine", outcome: JournalOutcome = .answered,
                      day: String = "2026-09-10", hour: Int = 22) -> JournalTurn {
        F.turn(kind, answer, on: day, outcome: outcome, hour: hour)
    }

    @Test func noHistoryMeansNothingLearnedAndEveryWeightIsOne() {
        let habits = derive([])
        #expect(habits == .none)
        #expect(habits.medianAnswerLength == nil)
        #expect(habits.typicalHour == nil)
        #expect(!habits.usesEmoji)
        for kind in JournalPromptKind.allCases { #expect(habits.weight(for: kind) == 1.0) }
    }

    @Test func onlyTheWindowBeforeTodayIsRead() {
        let turns = [
            turn(.heavy, outcome: .misfit, day: today),         // today: excluded
            turn(.heavy, outcome: .misfit, day: "2026-09-19"),  // after: excluded
            turn(.heavy, outcome: .misfit, day: "2026-07-01"),  // 79 days back: outside the 60
            turn(.good, "kept", day: "2026-07-20"),             // 60 days back: in
            turn(.good, "kept", day: "2026-09-17"),
        ]
        let habits = derive(turns)
        #expect(habits.weight(for: .heavy) == 1.0)
        #expect(habits.weights.keys.sorted { $0.rawValue < $1.rawValue } == [.good])
        #expect(JournalHabits.windowDays == 60)
    }

    @Test func weightsAreTheSmoothedAnsweredRateWithMisfitCountingDouble() {
        var turns: [JournalTurn] = []
        turns += (0..<3).map { _ in turn(.heavy) } + [turn(.heavy, outcome: .skipped)]      // 3 answered, 1 skipped
        turns += [turn(.skip, outcome: .misfit)]                                           // 0 answered, 1 misfit
        turns += (0..<3).map { _ in turn(.good, outcome: .skipped) }                       // 0 answered, 3 skipped
        turns += (0..<5).map { _ in turn(.choice, outcome: .misfit) }                      // 0 answered, 5 misfit
        let habits = derive(turns)
        #expect(habits.weight(for: .heavy) == 0.8)             // (3 + 1) / (3 + 1 + 1)
        #expect(habits.weight(for: .skip) == 1.0 / 3.0)        // 1 / (0 + 2 + 1)
        #expect(habits.weight(for: .good) == 0.25)             // 1 / (0 + 3 + 1)
        #expect(habits.weight(for: .choice) == 0.25)           // 1 / 11, held at the floor
        #expect(habits.weight(for: .closing) == 1.0)           // never asked, never penalised
        #expect(JournalHabits.weightFloor == 0.25)
    }

    @Test func aKindAnsweredEveryTimeKeepsWeightOne() {
        #expect(derive((0..<4).map { _ in turn(.good) }).weight(for: .good) == 1.0)
    }

    @Test func medianAnswerLengthIgnoresSkipsAndBlanks() {
        let odd = derive([turn(.opening, "abcd"), turn(.good, "abcdefghij"), turn(.closing, String(repeating: "x", count: 20)),
                          turn(.heavy, "ignored because skipped", outcome: .skipped), turn(.skip, "   ")])
        #expect(odd.medianAnswerLength == 10)
        let even = derive([turn(.opening, "abcd"), turn(.good, "abcdefghij"), turn(.closing, String(repeating: "x", count: 20)),
                           turn(.heavy, String(repeating: "y", count: 40))])
        #expect(even.medianAnswerLength == 15)                 // (10 + 20) / 2
    }

    @Test func typicalHourNeedsFiveTurns() {
        let four = (0..<4).map { _ in turn(.opening, hour: 22) }
        #expect(derive(four).typicalHour == nil)
        let five = [21, 22, 22, 23, 23].map { turn(.opening, hour: $0) }
        #expect(derive(five).typicalHour == 22)
    }

    /// A night owl's 23:00 and 01:00 belong to the same evening; the median must not land at midday.
    @Test func typicalHourWrapsPastMidnightWithTheDayBoundary() {
        let hours = [23, 23, 0, 1, 1]
        #expect(derive(hours.map { turn(.opening, hour: $0) }).typicalHour == 0)
    }

    @Test func emojiAreDetectedInTheAnswersOnly() {
        #expect(derive([turn(.opening, "great day \u{1F600}")]).usesEmoji)
        #expect(derive([turn(.opening, "\u{2764}\u{FE0F} that")]).usesEmoji)
        #expect(!derive([turn(.opening, "plain 5 #1 (c) 100%")]).usesEmoji)
    }

    @Test func safetyTurnsAreNotHabits() {
        let habits = derive([turn(.safety, "", outcome: .answered)])
        #expect(habits == .none)
    }

    // MARK: recency

    private func asked(_ promptID: String, _ text: String = "question", day: String, index: Int = 0,
                       kind: JournalPromptKind = .opening) -> JournalTurn {
        let t = F.turn(kind, index: index, on: day)
        t.promptID = promptID
        t.questionText = text
        return t
    }

    @Test func aRowIsLastUsedOnTheNewestDayItWasAsked() {
        let habits = derive([
            asked("open.keep", day: "2026-09-10"),
            asked("open.keep", day: "2026-09-15"),
            asked("open.feel", day: "2026-09-12"),
            asked("heavy.body", day: today, kind: .heavy),         // today is not history
            asked("open.scale", day: "2026-07-01"),                // outside the 60 days
        ])
        #expect(habits.lastUsedDay == ["open.keep": "2026-09-15", "open.feel": "2026-09-12"])
    }

    @Test func aModelWordedTurnMarksItsFallbackRowAsUsedAndKeepsItsTextForNovelty() {
        let model = asked("open.keep", "What stayed with you this evening?", day: "2026-09-16")
        model.source = .model
        let habits = derive([model])
        #expect(habits.lastUsedDay == ["open.keep": "2026-09-16"])
        #expect(habits.recentQuestionTexts == ["What stayed with you this evening?"])
    }

    @Test func recentQuestionsAreTheLastFourteenDaysNewestFirstWithoutBlanks() {
        let habits = derive([
            asked("a", "oldest in window", day: "2026-09-04"),     // 14 days back: in
            asked("b", "too old", day: "2026-09-03"),              // 15 days back: out
            asked("c", "yesterday first", day: "2026-09-17", index: 0),
            asked("d", "yesterday second", day: "2026-09-17", index: 1),
            asked("e", "", day: "2026-09-17", index: 2),           // free writing has no question
            asked("f", "a week ago", day: "2026-09-11"),
            asked("g", "today", day: today),
        ])
        #expect(habits.recentQuestionTexts == ["yesterday second", "yesterday first", "a week ago", "oldest in window"])
        #expect(JournalHabits.recentQuestionDays == 14)
    }

    @Test func aSafetyLineIsNeverRecentOrUsed() {
        let line = asked("safety", "That sounds heavy.", day: "2026-09-17", kind: .safety)
        #expect(derive([line]) == .none)
    }

    // MARK: the style hint

    @Test func theHintFollowsTheMedianLengthAndRegister() {
        func hint(_ median: Int?, emoji: Bool = false, _ language: JournalLanguage = .en) -> String {
            JournalHabits(medianAnswerLength: median, typicalHour: nil, usesEmoji: emoji, weights: [:])
                .styleHint(language: language)
        }
        #expect(hint(10) == "The user writes short answers. Keep the question under 12 words. Use a plain, calm register.")
        #expect(hint(29) == hint(10))
        #expect(hint(30) == "Keep the question under 20 words. Use a plain, calm register.")
        #expect(hint(nil) == hint(50))
        #expect(hint(119) == hint(50))
        #expect(hint(120) == "The user writes at length. A question of up to 25 words is fine. Use a plain, calm register.")
        #expect(hint(50, emoji: true) == "Keep the question under 20 words. Use a light, casual register.")
        #expect(hint(10, .zhHans) == "用户的回答很短。问题控制在 20 个字以内。语气平静朴素。")
        #expect(hint(200, emoji: true, .zhHans) == "用户习惯写得较长。问题可以长到 40 个字。语气轻松随意。")
    }

    @Test func theHintComesFromDerivedHabits() {
        let habits = derive([turn(.opening, "ok"), turn(.good, "fine")])
        #expect(habits.styleHint(language: .en).hasPrefix("The user writes short answers."))
    }
}
