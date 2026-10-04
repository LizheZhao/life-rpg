import Foundation
import Testing
@testable import LifeRPGCore

struct JournalTrendsEnergyTests {
    typealias Energy = JournalTrends.Energy
    private let week = JournalTrends.DayRange(first: "2026-09-14", last: "2026-09-20")

    private func days(_ tiers: [(String, Tier)], quests: [(String, Int)] = [], routines: [(String, Int)] = [],
                      range: JournalTrends.DayRange? = nil) -> [Energy.Day] {
        let questRows = quests.flatMap { key, n in (0..<n).map { _ in JournalFixtures.quest("Q", on: key) } }
        let routineRows = routines.flatMap { key, n in (0..<n).map { _ in JournalFixtures.routineDone("R", on: key) } }
        return Energy.days(in: range ?? week, quests: questRows, occurrences: routineRows,
                           contexts: tiers.map { JournalFixtures.context(tier: $0.1, on: $0.0) })
    }

    @Test func eachDayWithAContextHasItsDoneCountAndWhetherItWasLow() {
        let result = days([("2026-09-15", .normal), ("2026-09-16", .veryLow), ("2026-09-17", .low)],
                          quests: [("2026-09-15", 3), ("2026-09-16", 1)],
                          routines: [("2026-09-15", 2), ("2026-09-16", 1)])
        #expect(result == [Energy.Day(dayKey: "2026-09-15", done: 5, isLow: false),
                           Energy.Day(dayKey: "2026-09-16", done: 2, isLow: true),
                           Energy.Day(dayKey: "2026-09-17", done: 0, isLow: true)])
    }

    @Test func onlyTheRangeCountsAndTheDaysAreInOrder() {
        let result = days([("2026-09-20", .normal), ("2026-09-13", .normal), ("2026-09-14", .high)],
                          quests: [("2026-09-13", 4), ("2026-09-14", 1), ("2026-09-20", 2)])
        #expect(result.map(\.dayKey) == ["2026-09-14", "2026-09-20"])
        #expect(result.map(\.done) == [1, 2])
    }

    @Test func aReplacedOrUnfinishedRowIsNotDone() {
        let quests = [JournalFixtures.quest("a", on: "2026-09-15"),
                      JournalFixtures.quest("b", on: "2026-09-15", replaced: true),
                      JournalFixtures.quest("c", on: "2026-09-15", done: false)]
        let swapped = JournalFixtures.routineDone("r", on: "2026-09-15")
        swapped.replacedByID = UUID()
        let skipped = JournalFixtures.occurrence("s", due: "2026-09-15", skipped: true)
        let result = Energy.days(in: week, quests: quests, occurrences: [swapped, skipped],
                                 contexts: [JournalFixtures.context(tier: .normal, on: "2026-09-15")])
        #expect(result.map(\.done) == [1])
    }

    private func ratio(low: [Int], normal: [Int]) -> Int? {
        let lows = low.map { Energy.Day(dayKey: "x", done: $0, isLow: true) }
        let others = normal.map { Energy.Day(dayKey: "y", done: $0, isLow: false) }
        return Energy.lowDayRatio(lows + others)
    }

    @Test func lowDaysFinishSeventyOnePercentOfWhatANormalDayDoesWhenTheyAverageFiveToSeven() {
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
        let result = days(tiers, quests: [("2026-09-14", 5), ("2026-09-15", 5), ("2026-09-16", 5),
                                          ("2026-09-17", 7), ("2026-09-18", 7), ("2026-09-19", 7)])
        #expect(Energy.lowDayRatio(result) == 71)
    }
}
