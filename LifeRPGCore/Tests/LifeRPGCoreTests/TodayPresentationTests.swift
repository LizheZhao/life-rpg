import Foundation
import Testing
@testable import LifeRPGCore

/// The Today page's card states are plain values built from the rows the views already hold.
/// Every number and note in them is another rule's output, so these assert literals: a refactor
/// that changed what the page says would fail here rather than on a device.
struct TodayPresentationTests {
    // 2026-10-02 is a Friday; the epic below was drawn on Monday 2026-09-28.
    private let friday = "2026-10-02"

    private func slot(_ text: String, _ difficulty: Difficulty = .medium) -> DailyQuest {
        let q = DailyQuest()
        q.dayKey = friday
        q.slot = difficulty
        q.textSnapshot = text
        return q
    }

    private func occurrence(_ text: String, base: Int = 20, due: String = "2026-10-02") -> RoutineOccurrence {
        let o = RoutineOccurrence()
        o.textSnapshot = text
        o.basePoints = base
        o.dueDayKey = due
        o.routineID = UUID()
        return o
    }

    private func row(_ o: RoutineOccurrence, _ placement: RoutineRowState.Placement = .today,
                     routine: RoutineTask? = nil, tier: Tier = .normal, level: Int = 1,
                     quests: [DailyQuest] = [], occurrences: [RoutineOccurrence] = []) -> RoutineRowState {
        RoutineRowState(o, placement: placement, routine: routine, flexible: routine?.flexibleWithinWeek ?? false,
                        today: friday, tier: tier, level: level, quests: quests, occurrences: occurrences)
    }

    // MARK: quest tiles

    @Test func openMediumTile() {
        let q = slot("Walk 8,000 steps")
        let s = QuestCardState(q, tier: .normal)
        #expect(s.layout == .tile)
        #expect(s.title == "Walk 8,000 steps")
        #expect(s.subtitle == nil)
        #expect(s.doodle == .sneaker)
        #expect(s.tint == .medium)
        #expect(s.rangeText == "12–30")
        #expect(s.pillText == "12–30")
        #expect(!s.isDone)
        #expect(s.accessibilityLabel == "Walk 8,000 steps, medium, 12 to 30 coins")
        #expect(s.accessibilityValue == "not done")
    }

    @Test func lowDayWidensTheRangeByTheEffortMultiplier() {
        let s = QuestCardState(slot("Sort the mail", .easy), tier: .low)
        #expect(s.rangeText == "7–20")
    }

    @Test func variantAndLaunchLinkComeFromTheSnapshots() {
        let q = slot("Read a paper", .easy)
        q.variantSnapshot = "A view I've recently changed"
        q.launchURLSnapshot = "https://example.com/p"
        let s = QuestCardState(q, tier: .normal)
        #expect(s.subtitle == "A view I've recently changed")
        #expect(s.launchURL == URL(string: "https://example.com/p"))
        #expect(s.accessibilityLabel == "Read a paper, A view I've recently changed, easy, 5 to 15 coins")

        q.variantSnapshot = ""
        q.launchURLSnapshot = nil
        let bare = QuestCardState(q, tier: .normal)
        #expect(bare.subtitle == nil)
        #expect(bare.launchURL == nil)
    }

    @Test func doneTileShowsThePaidAmount() {
        let q = slot("Drink 2L of water", .easy)
        q.points = 11
        let s = QuestCardState(q, tier: .normal)
        #expect(s.isDone)
        #expect(s.awardedPoints == 11)
        #expect(s.pillText == "+11")
        #expect(s.accessibilityValue == "done, 11 coins earned")
    }

    @Test func hiddenQuestPaysTheFlatBonusOnTop() {
        let q = slot("Write a thank-you note", .medium)
        q.isHiddenSlot = true
        let s = QuestCardState(q, tier: .normal)
        #expect(s.layout == .hidden)
        #expect(s.tint == .hidden)
        #expect(s.rangeText == "22–40")
        #expect(s.accessibilityLabel == "Write a thank-you note, hidden quest, 22 to 40 coins")
    }

    @Test func trivialGroupIsOneTileWithThreeTickableItems() {
        let q = slot("", .trivial)
        q.trivialGroup = ["Floss", "Make bed", "Water plant"]
        q.trivialDone = [true, false, false]
        q.trivialVariants = ["", "", "the fern"]
        let s = QuestCardState(q, tier: .normal)
        #expect(s.layout == .trivialGroup)
        #expect(s.tint == .trivial)
        #expect(s.title == "Micro-actions")
        #expect(s.rangeText == "12")
        #expect(s.subtitle == "1 of 3 done")
        #expect(s.items == [
            .init(text: "Floss", variant: nil, isDone: true),
            .init(text: "Make bed", variant: nil, isDone: false),
            .init(text: "Water plant", variant: "the fern", isDone: false),
        ])
        #expect(!s.isDone)
        #expect(s.accessibilityLabel == "Micro-actions: Floss, Make bed, Water plant, 12 coins")
        #expect(s.accessibilityValue == "1 of 3 done")
    }

    @Test func tintFollowsDifficulty() {
        // An epic is never a tile (it is its own routine-style card), so it has no tint of its own.
        let tints = Difficulty.allCases.filter { $0 != .epic }
            .map { QuestCardState(slot("x", $0), tier: .normal).tint }
        #expect(tints == [.trivial, .easy, .medium, .hard])
    }

    @Test func replacedRowKeepsItsRecordNote() {
        let q = slot("Sort the mail", .easy)
        q.replaced = true
        q.replacedReason = .cancelled
        let s = ReplacedRowState(q)
        #expect(s.code == "E")
        #expect(s.title == "Sort the mail")
        #expect(s.note == "Cancelled")

        let trio = slot("", .trivial)
        trio.trivialGroup = ["Floss", "Make bed", "Water plant"]
        trio.replaced = true
        trio.replacedReason = .replan
        let t = ReplacedRowState(trio)
        #expect(t.code == "T×3")
        #expect(t.title == "Floss · Make bed · Water plant")
        #expect(t.note == "Dropped — the day was re-planned")
    }

    @Test func everyReplacedReasonHasANote() {
        let notes = ReplacedReason.allCases.map { reason -> String in
            let q = slot("x"); q.replaced = true; q.replacedReason = reason
            return ReplacedRowState(q).note
        }
        #expect(notes == ["Replaced", "Dropped — the day was re-planned", "Rerolled away", "Swapped", "Cancelled"])
    }

    // MARK: routine rows

    @Test func openRoutineShowsWhatItPaysToday() {
        let s = row(occurrence("Incline walk 30 min"))
        #expect(s.title == "Incline walk 30 min")
        #expect(s.doodle == .sneaker)
        #expect(s.pills == [.init("+20", .payout), .init("0 strikes this week", .plain)])
        #expect(s.notes.isEmpty)
        #expect(!s.isDone && !s.isSkipped && s.overdueDay == nil)
        #expect(s.accessibilityLabel == "Incline walk 30 min, pays 20 coins")
        #expect(s.accessibilityValue == "not done")
    }

    @Test func overdueRoutineShowsDayAndTheReducedPayout() {
        let o = occurrence("Cat grooming", base: 20, due: "2026-10-01")
        let s = row(o, .overdue)
        #expect(s.overdueDay == 2)
        #expect(s.pills == [.init("+10", .payout), .init("0 strikes this week", .plain), .init("overdue · day 2", .clay)])
        #expect(s.accessibilityLabel == "Cat grooming, overdue day 2, pays 10 coins")
    }

    @Test func theLateMakeUpPerkShowsInTheOverduePill() {
        let s = row(occurrence("Cat grooming", base: 20, due: "2026-10-01"), .overdue, level: 8)
        #expect(s.pills.first == .init("+12", .payout))
    }

    @Test func doneRoutineShowsWhatWasPaid() {
        let o = occurrence("Take out the trash", base: 5)
        o.completedDayKey = friday
        o.awardedPoints = 5
        let s = row(o)
        #expect(s.isDone)
        #expect(s.awardedPoints == 5)
        #expect(s.pills == [.init("+5", .payout), .init("0 strikes this week", .plain)])
        #expect(s.accessibilityValue == "done, 5 coins earned")
    }

    @Test func skippedRoutineHasNoPayout() {
        let o = occurrence("Water the plants")
        o.skipped = true
        let s = row(o)
        #expect(s.isSkipped)
        #expect(s.pills == [.init("Skipped", .plain), .init("0 strikes this week", .plain)])
        #expect(s.accessibilityValue == "skipped")
    }

    @Test func thisWeekRowSaysWhenItWasDue() {
        let o = occurrence("Strength session", due: "2026-09-30")
        let s = row(o, .thisWeek)
        #expect(s.notes == ["Not done · due Wed Sep 30"])
    }

    @Test func aRoutineDoneAheadSaysWhichDayItCountsFor() {
        let o = occurrence("Strength session", due: "2026-10-03")
        o.completedDayKey = friday
        o.awardedPoints = 30
        #expect(row(o, .thisWeek).notes == ["Done ahead · counts for Sat Oct 3"])
        o.dueDayKey = friday
        #expect(row(o, .today).notes == [])
    }

    @Test func strikesCountTheRoutinesCompletionsThisWeek() {
        let routineID = UUID()
        func done(_ week: String, source: UUID? = nil, adHocFrom: UUID? = nil) -> RoutineOccurrence {
            let o = occurrence("Strength")
            o.routineID = source
            o.adHocSourceRoutineID = adHocFrom
            o.weekKey = week
            o.completedDayKey = "2026-09-30"
            o.awardedPoints = 20
            return o
        }
        let open = occurrence("Strength")
        open.routineID = routineID
        open.weekKey = "2026-W40"

        func strikes(_ others: [RoutineOccurrence]) -> String? {
            row(open, occurrences: [open] + others).pills.first { $0.text.contains("strike") }?.text
        }
        #expect(strikes([]) == "0 strikes this week")
        #expect(strikes([done("2026-W40", source: routineID)]) == "1 strike this week")
        // Last week's session does not count, this week's library pick of the same routine does.
        #expect(strikes([done("2026-W39", source: routineID), done("2026-W40", source: routineID),
                         done("2026-W40", adHocFrom: routineID)]) == "2 strikes this week")
        // Somebody else's routine does not.
        #expect(strikes([done("2026-W40", source: UUID())]) == "0 strikes this week")
    }

    @Test func anAdHocRowHasNoStrikes() {
        let extra = occurrence("Water plants")
        extra.routineID = nil
        #expect(row(extra).pills == [.init("+20", .payout)])
    }

    @Test func autoVerifiedIsSpokenNotShown() {
        let walk = RoutineTask()
        walk.autoVerifyRule = "calendar:workout"
        let s = row(occurrence("Incline walk"), routine: walk)
        #expect(s.pills == [.init("+20", .payout), .init("0 strikes this week", .plain)])
        #expect(s.accessibilityLabel == "Incline walk, pays 20 coins, auto-verified")
        #expect(row(occurrence("Incline walk")).accessibilityLabel == "Incline walk, pays 20 coins")
    }

    @Test func lightVersionNoteAndSwitch() {
        let o = occurrence("Strength session")
        o.degradedTextSnapshot = "Stretch 15 min"
        o.degradedBasePoints = 10
        o.usedDegraded = true
        let light = row(o, tier: .low)
        #expect(light.title == "Stretch 15 min")
        #expect(light.version == .init(note: "Light version · Strength session", switchLabel: "Do original"))
        #expect(light.pills == [.init("+13", .payout), .init("0 strikes this week", .plain), .init("light version", .plain)])

        o.usedDegraded = false
        let original = row(o, tier: .low)
        #expect(original.title == "Strength session")
        #expect(original.version == .init(note: "Original · light version available", switchLabel: "Use light"))
        #expect(original.pills == [.init("+26", .payout), .init("0 strikes this week", .plain)])

        o.completedDayKey = friday
        o.awardedPoints = 26
        #expect(row(o, tier: .low).version?.switchLabel == nil)
    }

    @Test func addedAndReplacementNotes() {
        let slotQuest = slot("Walk 8,000 steps")
        let adHoc = occurrence("Call mum")
        adHoc.routineID = nil
        adHoc.replacesQuestID = slotQuest.id
        #expect(row(adHoc, quests: [slotQuest]).notes == ["Added today · replaces Walk 8,000 steps"])
        #expect(row(adHoc).notes == ["Added today · replaces a random slot"])

        adHoc.dueDayKey = "2026-10-01"
        #expect(row(adHoc, .overdue, quests: [slotQuest]).notes
                == ["Added 2026-10-01 · replaces Walk 8,000 steps"])

        let extra = occurrence("Water plants")
        extra.routineID = nil
        #expect(row(extra).notes == ["Added today · extra, no penalty"])

        let swapped = occurrence("Strength session")
        let taker = occurrence("Heavy lifting")
        taker.routineID = nil
        swapped.replacedByID = taker.id
        #expect(row(taker, occurrences: [swapped, taker]).notes == ["Replaces Strength session"])
    }

    @Test func anExtraNeverRepeatsThatItDoesNotGateTheHiddenQuest() {
        // `+` adds an extra that never gates (the add sheet says so); "extra, no penalty" is the whole note.
        let extra = occurrence("Water plants")
        extra.routineID = nil
        extra.countsForClear = false
        #expect(row(extra).notes == ["Added today · extra, no penalty"])
        #expect(row(extra).noteLine == "Added today · extra, no penalty")

        // A slot taken over, or a routine from the library, keeps the note when it really doesn't gate.
        let slotQuest = slot("Walk 8,000 steps")
        let taker = occurrence("Call mum")
        taker.routineID = nil
        taker.replacesQuestID = slotQuest.id
        taker.countsForClear = false
        #expect(row(taker, quests: [slotQuest]).notes
                == ["Added today · replaces Walk 8,000 steps", "Doesn't gate the hidden quest"])
    }

    @Test func notesShareOneCaptionLine() {
        let o = occurrence("Strength session", due: "2026-09-30")
        o.countsForClear = false
        let s = row(o, .thisWeek)
        #expect(s.notes == ["Not done · due Wed Sep 30", "Doesn't gate the hidden quest"])
        #expect(s.noteLine == "Not done · due Wed Sep 30 · Doesn't gate the hidden quest")
        #expect(row(occurrence("Take out the trash")).noteLine == nil)
    }

    @Test func aRoutineThatDoesNotGateTheHiddenQuestSaysSo() {
        let o = occurrence("Check-in")
        o.countsForClear = false
        #expect(row(o).notes == ["Doesn't gate the hidden quest"])
    }

    // MARK: epic

    private func epic(extensions: Int = 0) -> DailyQuest {
        let e = slot("Ship the MCP eval set v1", .epic)
        e.dayKey = "2026-09-28"
        e.weekKey = "2026-W40"
        e.extensionCount = extensions
        return e
    }

    @Test func openEpicCountsTheWeekdaysElapsed() {
        let s = EpicCardState(epic(), today: friday, tier: .normal, level: 1)
        #expect(s.title == "Ship the MCP eval set v1")
        #expect(s.segmentsFilled == 5)
        #expect(s.segmentsTotal == 7)
        #expect(s.lastDayKey == "2026-10-04")
        #expect(s.pills == [.init("60–150", .payout), .init("2 days left", .plain)])
        #expect(s.detailLines == ["Day 5 of 7 · due Sun Oct 4", "Extended 0 of 2"])
        #expect(!s.isDone)
        #expect(s.accessibilityLabel == "Weekly epic: Ship the MCP eval set v1, 60 to 150 coins")
        #expect(s.accessibilityValue == "not done, day 5 of 7, 2 days left")
    }

    @Test func segmentsRunFromMondayToSunday() {
        func filled(_ day: String) -> Int {
            EpicCardState(epic(), today: day, tier: .normal, level: 1).segmentsFilled
        }
        #expect(filled("2026-09-28") == 1)    // Monday
        #expect(filled("2026-10-03") == 6)    // Saturday
        #expect(filled("2026-10-04") == 7)    // Sunday
    }

    @Test func extendedEpicShowsTheCountAndRunsIntoNextWeek() {
        let e = epic(extensions: 1)
        let s = EpicCardState(e, today: "2026-10-06", tier: .normal, level: 1)
        #expect(s.segmentsFilled == 2)
        #expect(s.lastDayKey == "2026-10-11")
        #expect(s.pills == [.init("60–150", .payout), .init("5 days left", .plain), .init("extended 1/2", .plain)])
        #expect(s.detailLines == ["Day 2 of 7 · due Sun Oct 11", "Extended 1 of 2"])
        #expect(s.accessibilityValue == "not done, day 2 of 7, 5 days left, extended 1/2")
        // The third extension is a level 5 perk: the denominator follows the level.
        let perk = EpicCardState(e, today: "2026-10-06", tier: .normal, level: 5)
        #expect(perk.pills.last == .init("extended 1/3", .plain))
        #expect(perk.detailLines.last == "Extended 1 of 3")
    }

    @Test func epicKeepsTheDrawnVariantInItsTitleAndDetail() {
        let e = epic()
        e.variantSnapshot = "v2"
        e.launchURLSnapshot = "https://example.com/e"
        let s = EpicCardState(e, today: friday, tier: .normal, level: 1)
        #expect(s.title == "Ship the MCP eval set v1 — v2")
        #expect(s.launchURL == URL(string: "https://example.com/e"))
        #expect(s.detailLines == ["Day 5 of 7 · due Sun Oct 4", "Extended 0 of 2", "Drawn: v2"])
        #expect(s.accessibilityLabel == "Weekly epic: Ship the MCP eval set v1 — v2, 60 to 150 coins")
    }

    @Test func daysLeftCountsDownToTheLastDay() {
        func pill(_ day: String) -> String? {
            EpicCardState(epic(), today: day, tier: .normal, level: 1).pills.dropFirst().first?.text
        }
        #expect(pill("2026-09-28") == "6 days left")    // Monday
        #expect(pill("2026-10-03") == "1 day left")     // Saturday
        #expect(pill("2026-10-04") == "last day")       // Sunday
        // A malformed or past day says nothing rather than a wrong number.
        #expect(pill("2026-10-05") == nil)
    }

    @Test func doneEpicFillsEveryDay() {
        let e = epic()
        e.points = 112
        let s = EpicCardState(e, today: friday, tier: .normal, level: 1)
        #expect(s.isDone)
        #expect(s.awardedPoints == 112)
        #expect(s.segmentsFilled == 7)
        #expect(s.pills.first == .init("+112", .payout))
        #expect(s.accessibilityValue == "done, 112 coins earned")
    }

    // MARK: level card

    @Test func levelCardNumbers() {
        // Level 8 starts at 2940 earned and level 9 at 3840: 3528 earned leaves 312 to go.
        let s = LevelCardState(totalEarned: 3528, balance: 1240, streak: 12, tier: .normal,
                               randomSlots: 4, goal: nil)
        #expect(s.level == 8)
        #expect(s.pointsToNext == 312)
        #expect(s.filledDots == 13)
        #expect(s.dotCount == 20)
        #expect(s.balance == 1240)
        #expect(!s.isNegative)
        #expect(s.streakText == "12 day streak")
        #expect(s.tierText == "normal day")
        #expect(s.slotsText == "4 random slots")
        #expect(s.goal == nil)
        #expect(s.accessibilityLabel == "Level 8, 312 coins to level 9")
        #expect(s.accessibilityValue == "1240 coins, 12 day streak, normal day, 4 random slots")
    }

    @Test func levelCardEdgeCases() {
        let s = LevelCardState(totalEarned: 0, balance: -12, streak: 0, tier: .veryLow, randomSlots: 1, goal: nil)
        #expect(s.level == 1)
        #expect(s.isNegative)
        #expect(s.streakText == nil)
        #expect(s.tierText == "very low day")
        #expect(s.slotsText == "1 random slot")
        #expect(s.accessibilityValue == "-12 coins, very low day, 1 random slot")
        let streak1 = LevelCardState(totalEarned: 0, balance: 0, streak: 1, tier: .high, randomSlots: 0, goal: nil)
        #expect(streak1.streakText == "1 day streak")
        #expect(streak1.tierText == "high day")
        #expect(streak1.slotsText == "0 random slots")
    }

    @Test func savingsGoalLine() {
        let open = SavingsGoal.Progress(name: "AirPods Pro", price: 900, balance: 640,
                                        fraction: 640.0 / 900.0, weeksLeft: 3)
        let a = LevelCardState(totalEarned: 640, balance: 640, streak: 0, tier: .normal, randomSlots: 3, goal: open)
        #expect(a.goal == .init(name: "AirPods Pro", text: "640 / 900 · ~3 wk", fraction: 640.0 / 900.0, ready: false))

        let noPace = SavingsGoal.Progress(name: "AirPods Pro", price: 900, balance: -30, fraction: 0, weeksLeft: nil)
        let b = LevelCardState(totalEarned: 0, balance: -30, streak: 0, tier: .normal, randomSlots: 3, goal: noPace)
        #expect(b.goal?.text == "0 / 900")

        let ready = SavingsGoal.Progress(name: "AirPods Pro", price: 900, balance: 950, fraction: 1, weeksLeft: 0)
        let c = LevelCardState(totalEarned: 950, balance: 950, streak: 0, tier: .normal, randomSlots: 3, goal: ready)
        #expect(c.goal == .init(name: "AirPods Pro", text: "ready to redeem", fraction: 1, ready: true))
        #expect(c.accessibilityValue.hasSuffix("AirPods Pro, ready to redeem"))
    }

    // MARK: greeting

    @Test func greetingHandLine() {
        #expect(TodayGreeting(dayKey: friday, hour: 9, streak: 12).handLine == "Fri · Oct 2 · 12 day streak")
        #expect(TodayGreeting(dayKey: friday, hour: 9, streak: 1).handLine == "Fri · Oct 2 · 1 day streak")
        #expect(TodayGreeting(dayKey: friday, hour: 9, streak: 0).handLine == "Fri · Oct 2")
        #expect(TodayGreeting(dayKey: "2026-12-25", hour: 9, streak: 0).handLine == "Fri · Dec 25")
    }

    @Test func greetingFollowsTheClockHourNotTheDayBoundary() {
        func line(_ hour: Int) -> String { TodayGreeting(dayKey: friday, hour: hour, streak: 0).salutation }
        #expect(line(0) == "Good morning,")
        #expect(line(4) == "Good morning,")
        #expect(line(11) == "Good morning,")
        #expect(line(12) == "Good afternoon,")
        #expect(line(17) == "Good afternoon,")
        #expect(line(18) == "Good evening,")
        #expect(line(23) == "Good evening,")
    }

    @Test func shortDateNamesTheWeekday() {
        #expect(PresentationText.shortDate("2026-10-04") == "Sun Oct 4")
        #expect(PresentationText.shortDate("2026-10-05") == "Mon Oct 5")
        #expect(PresentationText.shortDate("garbage") == "garbage")
    }

    @Test func rangeText() {
        #expect(PresentationText.range(5...15) == "5–15")
        #expect(PresentationText.range(12...12) == "12")
        #expect(PresentationText.spokenRange(5...15) == "5 to 15 coins")
        #expect(PresentationText.spokenRange(12...12) == "12 coins")
    }

    @Test func dueInCountsDaysFromToday() {
        #expect(PresentationText.dueIn("2026-10-02", from: friday) == "due today")
        #expect(PresentationText.dueIn("2026-10-03", from: friday) == "due tomorrow")
        #expect(PresentationText.dueIn("2026-10-04", from: friday) == "due in 2 days")
        #expect(PresentationText.dueIn("2026-10-12", from: friday) == "due in 10 days")
        // Past, or not a day key: the date itself, never a negative count.
        #expect(PresentationText.dueIn("2026-10-01", from: friday) == "due Thu Oct 1")
        #expect(PresentationText.dueIn("garbage", from: friday) == "due garbage")
    }
}
