import Foundation
import Testing
@testable import LifeRPGCore

struct JournalTrendsGratitudeTests {
    typealias Gratitude = JournalTrends.Gratitude
    typealias F = EntryFixtures

    private func grateful(_ answer: String, question: String = "What are you grateful for today?") -> JournalBlock {
        F.prompt(1, question, answer: answer, key: .gratefulFor)
    }

    /// One day per answer, each answering the Grateful for chip.
    private func phrases(_ answers: [(String, String)], limit: Int = 7) -> [String] {
        let days = answers.map { TrendsFixtures.day($0.0, [grateful($0.1)]) }
        return Gratitude.phrases(in: days, limit: limit).map { "\($0.text) \($0.count)" }
    }

    // Equal counts on one day tie on recency too, so they list alphabetically.
    @Test func anEnglishAnswerSplitsIntoItsItems() {
        #expect(phrases([("2026-09-01", "the walk, the cat and a good 1:1")])
                == ["a good 1:1 1", "the cat 1", "the walk 1"])
    }

    @Test func aChineseAnswerSplitsOnTheEnumerationMarkAndHe() {
        #expect(phrases([("2026-09-01", "散步、小猫和一顿好饭")]) == ["一顿好饭 1", "小猫 1", "散步 1"])
    }

    @Test func semicolonsBothCommasAndAnOxfordAndSplitToo() {
        #expect(phrases([("2026-09-01", "tea; coffee，rain, and sun")]) == ["coffee 1", "rain 1", "sun 1", "tea 1"])
    }

    @Test func anAnswerToAnLLMPromptIsIgnoredEvenWhenItAsksTheSameThing() {
        let llm = F.prompt(1, "What are you grateful for today?", answer: "the walk, the cat", source: .llm)
        let days = [TrendsFixtures.day("2026-09-01", [llm])]
        #expect(Gratitude.phrases(in: days).isEmpty)
    }

    @Test func aFreeTextLineThatStartsWithGratefulForIsIgnored() {
        let days = [TrendsFixtures.day("2026-09-01", text: "Grateful for the walk, the cat")]
        #expect(Gratitude.phrases(in: days).isEmpty)
    }

    @Test func anAnswerToAnotherFixedPromptIsIgnored() {
        let other = F.prompt(1, "What was your favorite moment today?", answer: "the walk", key: .favoriteMoment)
        #expect(Gratitude.phrases(in: [TrendsFixtures.day("2026-09-01", [other])]).isEmpty)
    }

    @Test func onlyTheGratefulForPromptOfAMixedDayIsRead() {
        let blocks = [F.text(1, "Slept badly, the bed"), F.prompt(2, "Why?", answer: "the rain", source: .llm),
                      grateful("tea")]
        #expect(Gratitude.phrases(in: [TrendsFixtures.day("2026-09-01", blocks)]).map(\.text) == ["tea"])
    }

    @Test func theQuestionsOwnWordingDoesNotMatter() {
        #expect(phrases([("2026-09-01", "茶")]) == ["茶 1"])
        let chinese = grateful("茶", question: "今天你感恩什么？")
        #expect(Gratitude.phrases(in: [TrendsFixtures.day("2026-09-01", [chinese])]).map(\.text) == ["茶"])
    }

    @Test func everySentenceAndEveryLineOfAnAnswerIsRead() {
        #expect(phrases([("2026-09-01", "Rain. Sun, wind!\nthe cat")]) == ["Rain 1", "Sun 1", "the cat 1", "wind 1"])
    }

    @Test func aDecimalPointIsNotASentenceEnd() {
        #expect(phrases([("2026-09-01", "3.5 hours of sleep.")]) == ["3.5 hours of sleep 1"])
    }

    @Test func anItemOfMoreThanFortyCharactersOrNothingIsIgnored() {
        let forty = String(repeating: "a", count: 40)
        let over = String(repeating: "a", count: 41)
        #expect(phrases([("2026-09-01", "\(over), \(forty), , ,tea")]) == ["\(forty) 1", "tea 1"])
    }

    @Test func aWordWithAndInsideItIsNotSplit() {
        #expect(phrases([("2026-09-01", "sand, band")]) == ["band 1", "sand 1"])
    }

    @Test func anUnansweredPromptContributesNothing() {
        #expect(phrases([("2026-09-01", ""), ("2026-09-02", "  \n ")]).isEmpty)
    }

    @Test func itemsAreCountedAcrossDaysIgnoringCaseAndShowTheCommonestCasing() {
        let result = Gratitude.phrases(in: [
            TrendsFixtures.day("2026-09-01", [grateful("coffee.")]),
            TrendsFixtures.day("2026-09-02", [grateful("Coffee.")]),
            TrendsFixtures.day("2026-09-03", [grateful("Coffee, the cat.")]),
        ])
        #expect(result.map(\.text) == ["Coffee", "the cat"])
        #expect(result.map(\.count) == [3, 1])
    }

    @Test func equalCountsRankByRecencyAndTheLimitCuts() {
        #expect(phrases([("2026-09-01", "old"), ("2026-09-03", "new"), ("2026-09-02", "middle")], limit: 2)
                == ["new 1", "middle 1"])
        #expect(phrases([("2026-09-01", "a")], limit: 0).isEmpty)
    }

    @Test func theTopSevenAreKept() {
        let answer = "a1, b2, c3, d4, e5, f6, g7, h8, i9"
        #expect(phrases([("2026-09-01", answer)]).count == 7)
    }
}
