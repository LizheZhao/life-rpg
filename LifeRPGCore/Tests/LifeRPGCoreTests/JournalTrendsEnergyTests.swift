import Foundation
import Testing
@testable import LifeRPGCore

struct JournalTrendsEnergyTests {
    typealias Energy = JournalTrends.Energy
    private let week = JournalTrends.DayRange(first: "2026-09-14", last: "2026-09-20")

    /// One quest or routine per `(day, points)` pair, each worth that many points.
    private func days(_ tiers: [(String, Tier)], quests: [(String, Int)] = [], routines: [(String, Int)] = [],
                      range: JournalTrends.DayRange? = nil) -> [Energy.Day] {
        let questRows = quests.map { key, points -> DailyQuest in
            let quest = JournalFixtures.quest("Q", on: key)
            quest.points = points
            return quest
        }
        let routineRows = routines.map { key, points -> RoutineOccurrence in
            let occurrence = JournalFixtures.routineDone("R", on: key)
            occurrence.awardedPoints = points
            return occurrence
        }
        return Energy.days(in: range ?? week, quests: questRows, occurrences: routineRows,
                           contexts: tiers.map { JournalFixtures.context(tier: $0.1, on: $0.0) })
    }

    @Test func eachDayWithAContextHasThePointsEarnedAndWhetherItWasLow() {
        let result = days([("2026-09-15", .normal), ("2026-09-16", .veryLow), ("2026-09-17", .low)],
                          quests: [("2026-09-15", 12), ("2026-09-15", 30), ("2026-09-15", 8), ("2026-09-16", 15)],
                          routines: [("2026-09-15", 5), ("2026-09-15", 2), ("2026-09-16", 3)])
        // Quest points and routine awarded points add: 50 + 7, and 15 + 3. A day with nothing done earned 0.
        #expect(result == [Energy.Day(dayKey: "2026-09-15", points: 57, isLow: false),
                           Energy.Day(dayKey: "2026-09-16", points: 18, isLow: true),
                           Energy.Day(dayKey: "2026-09-17", points: 0, isLow: true)])
    }

    @Test func aFewBigQuestsOutweighManySmallOnes() {
        let result = days([("2026-09-15", .normal), ("2026-09-16", .normal)],
                          quests: [("2026-09-15", 40), ("2026-09-16", 5), ("2026-09-16", 5), ("2026-09-16", 5)])
        #expect(result.map(\.points) == [40, 15])
    }

    @Test func aRoutineCountsOnTheDayItWasCompletedNotTheDayItWasDue() {
        let late = JournalFixtures.routineDone("R", on: "2026-09-16")
        late.dueDayKey = "2026-09-14"
        late.awardedPoints = 6
        let result = Energy.days(in: week, quests: [], occurrences: [late],
                                 contexts: [JournalFixtures.context(tier: .normal, on: "2026-09-14"),
                                            JournalFixtures.context(tier: .normal, on: "2026-09-16")])
        #expect(result.map(\.points) == [0, 6])
    }

    @Test func onlyTheRangeCountsAndTheDaysAreInOrder() {
        let result = days([("2026-09-20", .normal), ("2026-09-13", .normal), ("2026-09-14", .high)],
                          quests: [("2026-09-13", 40), ("2026-09-14", 10), ("2026-09-20", 20)])
        #expect(result.map(\.dayKey) == ["2026-09-14", "2026-09-20"])
        #expect(result.map(\.points) == [10, 20])
    }

    @Test func aReplacedOrUnfinishedRowEarnsNothing() {
        let quests = [JournalFixtures.quest("a", on: "2026-09-15"),
                      JournalFixtures.quest("b", on: "2026-09-15", replaced: true),
                      JournalFixtures.quest("c", on: "2026-09-15", done: false)]
        let swapped = JournalFixtures.routineDone("r", on: "2026-09-15")
        swapped.awardedPoints = 9
        swapped.replacedByID = UUID()
        let skipped = JournalFixtures.occurrence("s", due: "2026-09-15", skipped: true)
        skipped.awardedPoints = 9
        let result = Energy.days(in: week, quests: quests, occurrences: [swapped, skipped],
                                 contexts: [JournalFixtures.context(tier: .normal, on: "2026-09-15")])
        // Only quest "a", worth the fixture's 10.
        #expect(result.map(\.points) == [10])
    }

    private func ratio(low: [Int], normal: [Int]) -> Int? {
        let lows = low.map { Energy.Day(dayKey: "x", points: $0, isLow: true) }
        let others = normal.map { Energy.Day(dayKey: "y", points: $0, isLow: false) }
        return Energy.lowDayRatio(lows + others)
    }

    @Test func lowDaysEarnSeventyOnePercentOfWhatANormalDayDoesWhenTheyAverageFiveToSevenPoints() {
        #expect(ratio(low: [4, 5, 6], normal: [6, 7, 8]) == 71)
        #expect(ratio(low: [5, 5, 5], normal: [7, 7, 7]) == 71)
    }

    @Test func theRatioRoundsToTheNearestPercentAndCanPassOneHundred() {
        #expect(ratio(low: [1, 1, 1], normal: [3, 3, 3]) == 33)
        #expect(ratio(low: [2, 2, 2], normal: [3, 3, 3]) == 67)
        #expect(ratio(low: [8, 8, 8], normal: [4, 4, 4]) == 200)
    }

    @Test func itNeedsThreeLowAndThreeOtherDaysAndSomethingDoneOnThem() {
        #expect(ratio(low: [5, 5], normal: [7, 7, 7]) == nil)
        #expect(ratio(low: [5, 5, 5], normal: [7, 7]) == nil)
        #expect(ratio(low: [5, 5, 5], normal: [0, 0, 0]) == nil)
        #expect(ratio(low: [0, 0, 0], normal: [4, 4, 4]) == 0)
    }

    @Test func theRatioReadsTheDaysTheWayTheyAreBuilt() {
        let tiers: [(String, Tier)] = [("2026-09-14", .low), ("2026-09-15", .veryLow), ("2026-09-16", .low),
                                       ("2026-09-17", .normal), ("2026-09-18", .high), ("2026-09-19", .normal)]
        let result = days(tiers, quests: [("2026-09-14", 50), ("2026-09-15", 50), ("2026-09-16", 50),
                                          ("2026-09-17", 70), ("2026-09-18", 70), ("2026-09-19", 70)])
        #expect(Energy.lowDayRatio(result) == 71)
    }
}
