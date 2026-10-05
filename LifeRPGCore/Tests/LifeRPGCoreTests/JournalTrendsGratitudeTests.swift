import Foundation
import Testing
@testable import LifeRPGCore

struct JournalTrendsGratitudeTests {
    typealias Gratitude = JournalTrends.Gratitude

    private func phrases(_ texts: [(String, String)], limit: Int = 7) -> [String] {
        Gratitude.phrases(in: TrendsFixtures.entryDays(texts: texts), limit: limit).map { "\($0.text) \($0.count)" }
    }

    // Equal counts on one day tie on recency too, so they list alphabetically.
    @Test func anEnglishSentenceSplitsIntoItsItems() {
        #expect(phrases([("2026-09-01", "Grateful for the walk, the cat, and a good 1:1.")])
                == ["a good 1:1 1", "the cat 1", "the walk 1"])
    }

    @Test func aChineseSentenceSplitsOnTheEnumerationMarkAndHe() {
        #expect(phrases([("2026-09-01", "今天感恩的是散步、小猫和一顿好饭。")])
                == ["一顿好饭 1", "小猫 1", "散步 1"])
    }

    @Test func theStarterIsMatchedWithoutCaseAndWithAColonEitherWidth() {
        #expect(phrases([("2026-09-01", "GRATEFUL FOR: tea!"), ("2026-09-02", "今天感恩的是：茶")]) == ["茶 1", "tea 1"])
    }

    @Test func onlyTheFirstSentenceIsRead() {
        #expect(phrases([("2026-09-01", "Grateful for rain. Also the sun, the wind"),
                         ("2026-09-02", "Grateful for sleep? Maybe not tea")]) == ["sleep 1", "rain 1"])
    }

    @Test func aDecimalPointIsNotASentenceEnd() {
        #expect(phrases([("2026-09-01", "Grateful for 3.5 hours of sleep.")]) == ["3.5 hours of sleep 1"])
    }

    @Test func aParagraphThatMerelyStartsWithTheLettersIsNotAGratitudeLine() {
        #expect(phrases([("2026-09-01", "Grateful forever, honestly, the tea")]).isEmpty)
        #expect(phrases([("2026-09-01", "I am grateful for tea")]).isEmpty)
    }

    @Test func eachParagraphOfAnEntryIsReadOnItsOwn() {
        let text = "Slept badly, the bed\nGrateful for tea\n\nGrateful for the cat, tea"
        #expect(phrases([("2026-09-01", text)]) == ["tea 2", "the cat 1"])
    }

    @Test func anItemOfMoreThanFortyCharactersOrNothingIsIgnored() {
        let forty = String(repeating: "a", count: 40)
        let over = String(repeating: "a", count: 41)
        #expect(phrases([("2026-09-01", "Grateful for \(over), \(forty), , ,tea")]) == ["\(forty) 1", "tea 1"])
    }

    @Test func aWordWithAndInsideItIsNotSplit() {
        #expect(phrases([("2026-09-01", "Grateful for sand, band")]) == ["band 1", "sand 1"])
    }

    @Test func itemsAreCountedAcrossDaysIgnoringCaseAndShowTheCommonestCasing() {
        let result = Gratitude.phrases(in: TrendsFixtures.entryDays(texts: [
            ("2026-09-01", "Grateful for coffee."),
            ("2026-09-02", "Grateful for Coffee."),
            ("2026-09-03", "Grateful for Coffee, the cat."),
        ]))
        #expect(result.map(\.text) == ["Coffee", "the cat"])
        #expect(result.map(\.count) == [3, 1])
    }

    @Test func equalCountsRankByRecencyAndTheLimitCuts() {
        #expect(phrases([("2026-09-01", "Grateful for old"), ("2026-09-03", "Grateful for new"),
                         ("2026-09-02", "Grateful for middle")], limit: 2) == ["new 1", "middle 1"])
        #expect(phrases([("2026-09-01", "Grateful for a")], limit: 0).isEmpty)
    }

    @Test func gratitudeInAQuestionedAnswerCountsToo() throws {
        let answered = EntryFixtures.prompt(1, "What went well?", answer: "Grateful for the walk")
        let days = [TrendsFixtures.day("2026-09-01", [answered])]
        #expect(Gratitude.phrases(in: days).map(\.text) == ["the walk"])
    }
}
