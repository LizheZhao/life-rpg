import Foundation
import Testing
@testable import LifeRPGCore

/// The Completed stack gathers what is done from rows the Today page already holds. Which rows
/// qualify, in what order and for how many coins are asserted as literals, so the page cannot
/// drift from them without a failure here.
struct CompletedStackTests {
    // 2026-10-02 is a Friday; the epic below was drawn on Monday 2026-09-28.
    private let friday = "2026-10-02"
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    private func at(_ minutes: Int) -> Date { base.addingTimeInterval(Double(minutes) * 60) }

    private func quest(_ text: String, _ slot: Difficulty = .medium, points: Int? = nil,
                       minute: Int? = nil, day: String? = nil) -> DailyQuest {
        let q = DailyQuest()
        q.dayKey = day ?? friday
        q.slot = slot
        q.textSnapshot = text
        q.points = points
        q.completedAt = minute.map(at)
        return q
    }

    private func occurrence(_ text: String, due: String? = nil, points: Int? = nil, minute: Int? = nil,
                            doneOn: String? = nil) -> RoutineOccurrence {
        let o = RoutineOccurrence()
        o.textSnapshot = text
        o.basePoints = 20
        o.dueDayKey = due ?? friday
        o.weekKey = "2026-W40"
        o.routineID = UUID()
        o.awardedPoints = points
        o.completedAt = minute.map(at)
        o.completedDayKey = points == nil ? nil : (doneOn ?? friday)
        return o
    }

    private func epic(points: Int? = nil, minute: Int? = nil, day: String = "2026-09-28") -> DailyQuest {
        quest("Ship the MCP eval set v1", .epic, points: points, minute: minute, day: day)
    }

    private func stack(quests: [DailyQuest] = [], occurrences: [RoutineOccurrence] = [],
                       holding: Set<UUID> = []) -> CompletedStackState {
        CompletedStackState(quests: quests, occurrences: occurrences, today: friday, tier: .normal, level: 1,
                            holding: holding) { o in
            RoutineRowState(o, placement: .today, routine: nil, flexible: false, today: friday,
                            tier: .normal, level: 1, quests: quests, occurrences: occurrences)
        }
    }

    private func titles(_ state: CompletedStackState) -> [String] {
        state.items.map {
            switch $0 {
            case .quest(let s): s.title
            case .routine(let s): s.title
            case .epic(let s): s.title
            }
        }
    }

    // MARK: ordering and totals

    @Test func mostRecentlyCompletedComesFirstAcrossKinds() {
        let state = stack(
            quests: [quest("Browse a supermarket", .medium, points: 17, minute: 30),
                     quest("Listen to a stand-up clip", .easy, points: 6, minute: 10),
                     epic(points: 112, minute: 5)],
            occurrences: [occurrence("Workout: running", points: 25, minute: 60)])
        #expect(titles(state) == ["Workout: running", "Browse a supermarket", "Listen to a stand-up clip",
                                  "Ship the MCP eval set v1"])
        #expect(state.count == 4)
        #expect(state.totalPoints == 160)
        #expect(state.summary == "4 done · +160")
        #expect(state.accessibilityLabel == "Completed, 4 done, 160 coins")
    }

    @Test func totalIsWhatTheRowsWerePaidNotWhatTheyWouldPay() {
        // Base 20, paid 7 (a late make-up): the sum reads the paid figure.
        let state = stack(occurrences: [occurrence("Cat grooming", due: "2026-10-01", points: 7, minute: 1)])
        #expect(state.totalPoints == 7)
        #expect(state.summary == "1 done · +7")
        #expect(state.accessibilityLabel == "Completed, 1 done, 7 coins")
    }

    @Test func equalTimesFallBackToTitleAndAMissingTimeGoesLast() {
        let state = stack(
            quests: [quest("Banana", .easy, points: 5, minute: 10),
                     quest("Apple", .easy, points: 5, minute: 10),
                     quest("Undated", .easy, points: 5)])
        #expect(titles(state) == ["Apple", "Banana", "Undated"])
    }

    // MARK: which rows

    @Test func onlyDoneRowsOfTheLiveDayJoin() {
        let rerolled = quest("Rerolled away", .easy, points: 9, minute: 3)
        rerolled.replaced = true
        rerolled.replacedReason = .rerolled
        let swapped = occurrence("Swapped routine", points: 12, minute: 4)
        swapped.replacedByID = UUID()
        let skipped = occurrence("Skipped routine")
        skipped.skipped = true
        let ahead = occurrence("Strength tomorrow", due: "2026-10-03", points: 20, minute: 5)
        let state = stack(
            quests: [quest("Open quest"),
                     quest("Yesterday's quest", .easy, points: 8, minute: 2, day: "2026-10-01"),
                     rerolled,
                     epic(),
                     epic(points: 99, minute: 1, day: "2026-09-21"),
                     quest("Done today", .easy, points: 11, minute: 20)],
            occurrences: [occurrence("Open routine"), swapped, skipped, ahead,
                          occurrence("Done yesterday", due: "2026-10-01", points: 20, minute: 6,
                                     doneOn: "2026-10-01")])
        #expect(titles(state) == ["Done today"])
        #expect(state.totalPoints == 11)
    }

    @Test func routinesDueTodayOrFinishedLateTodayJoinButAheadOnesStay() {
        let doneEarly = occurrence("Pulled forward", due: friday, points: 20, minute: 15, doneOn: "2026-10-01")
        let late = occurrence("Cat grooming", due: "2026-10-01", points: 10, minute: 25)
        let state = stack(occurrences: [doneEarly, late,
                                        occurrence("Strength tomorrow", due: "2026-10-03", points: 20, minute: 40)])
        #expect(titles(state) == ["Cat grooming", "Pulled forward"])
        #expect(state.totalPoints == 30)
    }

    @Test func aMicroGroupAndTheRevealedHiddenQuestJoinWhenDone() {
        let group = quest("", .trivial, points: 12, minute: 7)
        group.trivialGroup = ["Floss", "Make the bed", "Water the plant"]
        group.trivialDone = [true, true, true]
        let hidden = quest("Write a thank-you note", .medium, points: 40, minute: 9)
        hidden.isHiddenSlot = true
        let state = stack(quests: [group, hidden])
        #expect(titles(state) == ["Write a thank-you note", "Micro-actions"])
        #expect(state.totalPoints == 52)
    }

    @Test func aGroupWithTicksLeftStaysOut() {
        let group = quest("", .trivial, minute: nil)
        group.trivialGroup = ["Floss", "Make the bed", "Water the plant"]
        group.trivialDone = [true, true, false]
        #expect(stack(quests: [group]).isEmpty)
    }

    @Test func nothingDoneIsEmpty() {
        let state = stack(quests: [quest("Open quest"), epic()], occurrences: [occurrence("Open routine")])
        #expect(state.isEmpty)
        #expect(state.count == 0)
        #expect(state.totalPoints == 0)
        #expect(state.summary == "0 done · +0")
    }

    @Test func aDoneEpicAloneMakesAStackOfOne() {
        // Drawn Monday, done Tuesday: it is still the week's epic on Friday.
        let state = stack(quests: [epic(points: 112, minute: 2)])
        #expect(titles(state) == ["Ship the MCP eval set v1"])
        #expect(state.count == 1)
        #expect(state.totalPoints == 112)
        #expect(state.summary == "1 done · +112")
    }

    @Test func aRowStillShowingItsCompletionIsHeldBack() {
        let fresh = quest("Just done", .easy, points: 6, minute: 50)
        let state = stack(quests: [fresh, quest("Older", .easy, points: 5, minute: 10)], holding: [fresh.id])
        #expect(titles(state) == ["Older"])
        #expect(state.totalPoints == 5)
    }

    // MARK: sections

    @Test func sectionLabelsReadClearedOnlyWhenEveryItemIs() {
        #expect(SectionProgress(done: 1, total: 3).handLabel == "1 / 3 done")
        #expect(SectionProgress(done: 0, total: 2).handLabel == "0 / 2 done")
        #expect(SectionProgress(done: 3, total: 3).handLabel == "cleared")
        #expect(SectionProgress(done: 0, total: 0).handLabel == nil)
    }

    @Test func theEpicHeaderSaysClearedOnceItIsDone() {
        #expect(EpicCardState(epic(), today: friday, tier: .normal, level: 1).sectionLabel == "this week")
        #expect(EpicCardState(epic(points: 112, minute: 1), today: friday, tier: .normal, level: 1).sectionLabel
                == "cleared")
    }
}
