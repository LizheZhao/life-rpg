import Foundation
import Testing
@testable import LifeRPGCore

struct JournalTrendsQuestsTests {
    typealias Quests = JournalTrends.Quests
    private let september = JournalTrends.DayRange(first: "2026-09-01", last: "2026-09-30")

    private func quest(_ text: String, template: UUID?, on dayKey: String, done: Bool = true,
                       replaced: Bool = false) -> DailyQuest {
        let q = JournalFixtures.quest(text, on: dayKey, done: done, replaced: replaced)
        q.templateID = template
        return q
    }

    private func routine(_ text: String, id: UUID?, on dayKey: String, light: Bool = false,
                         offeredLight: Bool = false, replaced: Bool = false) -> RoutineOccurrence {
        let o = JournalFixtures.routineDone(text, on: dayKey)
        o.routineID = id
        if light || offeredLight { o.degradedRoutineID = UUID() }
        o.usedDegraded = light
        if replaced { o.replacedByID = UUID() }
        return o
    }

    private func rating(_ id: UUID, _ value: Int, on dayKey: String = "2026-09-10") -> QuestRating {
        let r = JournalFixtures.rating(of: UUID(), value, on: dayKey)
        r.targetID = id
        return r
    }

    private func favorites(quests: [DailyQuest] = [], occurrences: [RoutineOccurrence] = [],
                           ratings: [QuestRating] = [], limit: Int = 3) -> [Quests.Favorite] {
        Quests.favorites(quests: quests, occurrences: occurrences, ratings: ratings, in: september, limit: limit)
    }

    @Test func aDailyRepeatedRoutineIsOneRowCountedByCompletionsInTheRange() {
        let walk = UUID()
        let result = favorites(occurrences: [
            routine("Walk", id: walk, on: "2026-09-01"), routine("Walk", id: walk, on: "2026-09-02"),
            routine("Walk", id: walk, on: "2026-09-30"), routine("Walk", id: walk, on: "2026-10-01"),
            routine("Walk", id: walk, on: "2026-08-31"),
        ])
        #expect(result == [Quests.Favorite(text: "Walk", times: 3, lightCount: 0, stars: nil)])
    }

    @Test func randomQuestsAreGroupedByTemplateAndShowTheNewestWording() {
        let tea = UUID()
        let result = favorites(quests: [
            quest("Make tea", template: tea, on: "2026-09-02"), quest("Make green tea", template: tea, on: "2026-09-09"),
            quest("Make tea", template: UUID(), on: "2026-09-05"),
        ])
        #expect(result == [Quests.Favorite(text: "Make green tea", times: 2, lightCount: 0, stars: nil),
                           Quests.Favorite(text: "Make tea", times: 1, lightCount: 0, stars: nil)])
    }

    @Test func anUnfinishedOrReplacedQuestAndAReplacedOccurrenceAreIgnored() {
        let id = UUID()
        let result = favorites(
            quests: [quest("Read", template: id, on: "2026-09-02"),
                     quest("Read", template: id, on: "2026-09-03", done: false),
                     quest("Read", template: id, on: "2026-09-04", replaced: true)],
            occurrences: [routine("Run", id: id, on: "2026-09-02", replaced: true),
                          JournalFixtures.occurrence("Skipped", due: "2026-09-02", skipped: true, routineID: UUID())])
        #expect(result.map(\.text) == ["Read"])
        #expect(result.map(\.times) == [1])
    }

    @Test func aLightVersionIsCountedAsATimeAndAsALightOne() {
        let run = UUID()
        let result = favorites(occurrences: [
            routine("Run", id: run, on: "2026-09-01", light: true),
            routine("Run", id: run, on: "2026-09-02", light: true),
            routine("Run", id: run, on: "2026-09-03"),
            // Offered a light version but did the original: not light.
            routine("Run", id: run, on: "2026-09-04", offeredLight: true),
        ])
        #expect(result.map(\.times) == [4])
        #expect(result.map(\.lightCount) == [2])
    }

    @Test func starsAreTheMeanRatingOfTheRangeShiftedToOneToFive() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()
        let result = favorites(
            quests: [("A", a), ("B", b), ("C", c), ("D", d), ("E", e)].map { quest($0.0, template: $0.1, on: "2026-09-02") },
            ratings: [rating(a, 2), rating(a, 2), rating(b, 0), rating(b, 1), rating(c, -2), rating(c, -2),
                      rating(d, -1), rating(d, 1)],
            limit: 10)
        func stars(_ text: String) -> Int? { result.first { $0.text == text }?.stars }
        #expect(stars("A") == 5)
        #expect(stars("B") == 4)      // 0.5 + 3 = 3.5 rounds up
        #expect(stars("C") == 1)
        #expect(stars("D") == 3)
        #expect(result.contains { $0.text == "E" } && stars("E") == nil)
    }

    @Test func ratingsFiledOutsideTheRangeDoNotCount() {
        let a = UUID()
        let result = favorites(quests: [quest("A", template: a, on: "2026-09-02")],
                               ratings: [rating(a, -2, on: "2026-08-31"), rating(a, 2, on: "2026-09-05"),
                                         rating(a, -2, on: "2026-10-01")])
        #expect(result.first?.stars == 5)
    }

    @Test func rankingIsTimesThenMeanRatingThenText() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let result = favorites(
            quests: [quest("D", template: d, on: "2026-09-01"), quest("C", template: c, on: "2026-09-01"),
                     quest("B", template: b, on: "2026-09-01"), quest("B", template: b, on: "2026-09-02"),
                     quest("A", template: a, on: "2026-09-01"), quest("A", template: a, on: "2026-09-02"),
                     quest("Z", template: UUID(), on: "2026-09-01")],
            ratings: [rating(a, 1), rating(b, 2)],
            limit: 10)
        // A and B both twice, B rated higher; C and D once, unrated, so by text; Z once, same.
        #expect(result.map(\.text) == ["B", "A", "C", "D", "Z"])
    }

    @Test func aRatedThingOutranksAnUnratedOneOfTheSameCount() {
        let rated = UUID()
        let result = favorites(quests: [quest("Zed", template: rated, on: "2026-09-01"),
                                        quest("Alpha", template: UUID(), on: "2026-09-01")],
                               ratings: [rating(rated, -2)])
        #expect(result.map(\.text) == ["Zed", "Alpha"])
    }

    @Test func theLimitCutsTheList() {
        let quests = (1...5).map { quest("Q\($0)", template: UUID(), on: "2026-09-01") }
        #expect(favorites(quests: quests).count == 3)
        #expect(favorites(quests: quests, limit: 0).isEmpty)
    }
}
