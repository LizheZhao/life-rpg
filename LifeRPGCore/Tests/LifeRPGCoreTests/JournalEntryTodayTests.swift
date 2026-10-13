import Foundation
import Testing
@testable import LifeRPGCore

struct JournalEntryTodayTests {
    private typealias F = EntryFixtures
    private let tz = Fixtures.tokyo
    private let day = "2026-09-18"

    private func entry(_ text: String, done: Bool) -> JournalEntry {
        let row = JournalEntry()
        row.dayKey = day
        row.blocks = [F.text(1, text)]
        row.doneAt = done ? Date() : nil
        return row
    }

    // MARK: state, badge, copy

    @Test func noRowIsNoneAndShowsNothing() {
        let state = JournalEntryToday.state(of: nil)
        #expect(state == .none)
        #expect(JournalEntryToday.iconBadge(state) == .none)
        #expect(JournalEntryToday.cardCopy(state) == "Start writing")
    }

    @Test func aDraftWithWordsShowsADotAndKeepGoing() {
        let state = JournalEntryToday.state(of: entry("one two three", done: false))
        #expect(state == .draft(words: 3))
        #expect(JournalEntryToday.iconBadge(state) == .dot)
        #expect(JournalEntryToday.cardCopy(state) == "Keep going \u{00B7} 3 words")
    }

    @Test func aDraftWithNoWordsShowsNoDot() {
        let state = JournalEntryToday.state(of: entry("😀", done: false))
        #expect(state == .draft(words: 0))
        #expect(JournalEntryToday.iconBadge(state) == .none)
        #expect(JournalEntryToday.cardCopy(state) == "Keep going \u{00B7} 0 words")
    }

    @Test func aDoneEntryShowsACheckAndWritten() {
        let state = JournalEntryToday.state(of: entry("one two three four", done: true))
        #expect(state == .done(words: 4))
        #expect(JournalEntryToday.iconBadge(state) == .check)
        #expect(JournalEntryToday.cardCopy(state) == "Written \u{00B7} 4 words")
    }

    @Test func oneWordIsNotPlural() {
        #expect(JournalEntryToday.cardCopy(.draft(words: 1)) == "Keep going \u{00B7} 1 word")
        #expect(JournalEntryToday.cardCopy(.done(words: 1)) == "Written \u{00B7} 1 word")
    }

    // MARK: when the card shows

    private func visible(hour: Int, minute: Int = 0, allCleared: Bool = false, onDay: String = "2026-09-18") -> Bool {
        var c = DateComponents()
        let p = onDay.split(separator: "-").map { Int($0)! }
        c.year = p[0]; c.month = p[1]; c.day = p[2]; c.hour = hour; c.minute = minute
        return JournalEntryToday.cardVisible(now: LifeCalendar.gregorian(tz).date(from: c)!, timeZone: tz, allCleared: allCleared)
    }

    @Test func theCardAppearsAtTwentyAndNotBefore() {
        #expect(!visible(hour: 19, minute: 59))
        #expect(visible(hour: 20))
        #expect(visible(hour: 23, minute: 59))
    }

    @Test func theCardStaysThroughTheSmallHoursAndGoesAtTheFiveOClockRollover() {
        #expect(visible(hour: 0))
        #expect(visible(hour: 4, minute: 59))
        #expect(!visible(hour: 5))
        #expect(!visible(hour: 12))
    }

    @Test func aClearedDayShowsTheCardAtAnyHour() {
        #expect(visible(hour: 12, allCleared: true))
        #expect(visible(hour: 5, allCleared: true))
        #expect(visible(hour: 19, minute: 59, allCleared: true))
    }

    @Test func theHourFollowsTheGivenTimeZone() {
        // The same instant: 20:00 in Tokyo, 04:00 in Los Angeles, 21:00 in Sydney, 13:00 in Paris.
        let moment = Fixtures.date("2026-09-18", hour: 20, in: tz)
        #expect(JournalEntryToday.cardVisible(now: moment, timeZone: tz, allCleared: false))
        let la = TimeZone(identifier: "America/Los_Angeles")!
        #expect(JournalEntryToday.cardVisible(now: moment, timeZone: la, allCleared: false))
        let sydney = TimeZone(identifier: "Australia/Sydney")!
        #expect(JournalEntryToday.cardVisible(now: moment, timeZone: sydney, allCleared: false))
        let paris = TimeZone(identifier: "Europe/Paris")!
        #expect(!JournalEntryToday.cardVisible(now: moment, timeZone: paris, allCleared: false))
    }

    // MARK: the moment's word

    private func moment(hour: Int, minute: Int = 0) -> String {
        JournalEntryToday.moment(now: Fixtures.date("2026-09-18", hour: hour, in: tz).addingTimeInterval(Double(minute) * 60),
                                 timeZone: tz)
    }

    @Test func theDayIsNamedTonightFromTwentyUntilTheRollover() {
        #expect(moment(hour: 4, minute: 59) == "tonight")
        #expect(moment(hour: 5) == "today")
        #expect(moment(hour: 19, minute: 59) == "today")
        #expect(moment(hour: 20) == "tonight")
        #expect(moment(hour: 23, minute: 59) == "tonight")
    }

    @Test func theTrendsButtonNamesTheSameMoment() {
        let day = Fixtures.date("2026-09-18", hour: 12, in: tz)
        let night = Fixtures.date("2026-09-18", hour: 21, in: tz)
        #expect(JournalEntryToday.writeButtonTitle(now: day, timeZone: tz) == "Write today's entry")
        #expect(JournalEntryToday.writeButtonTitle(now: night, timeZone: tz) == "Write tonight's entry")
    }

    // MARK: all cleared

    private func quest(done: Bool, replaced: Bool = false, hidden: Bool = false, slot: Difficulty = .easy,
                       on dayKey: String = "2026-09-18") -> DailyQuest {
        let q = JournalFixtures.quest("q", on: dayKey, done: done, replaced: replaced)
        q.isHiddenSlot = hidden
        q.slot = slot
        return q
    }

    @Test func aDayWithNothingToDoIsNotCleared() {
        #expect(!JournalEntryToday.allCleared(quests: [], occurrences: [], dayKey: day))
        #expect(!JournalEntryToday.allCleared(quests: [quest(done: false, replaced: true)], occurrences: [], dayKey: day))
    }

    @Test func allQuestsDoneAndAllRoutinesDoneOrSkippedClearsTheDay() {
        let occurrences = [JournalFixtures.occurrence("Trash", due: day, completed: day),
                           JournalFixtures.occurrence("Gym", due: day, skipped: true)]
        #expect(JournalEntryToday.allCleared(quests: [quest(done: true), quest(done: true)], occurrences: occurrences, dayKey: day))
        #expect(JournalEntryToday.allCleared(quests: [quest(done: true)], occurrences: [], dayKey: day))
        #expect(JournalEntryToday.allCleared(quests: [], occurrences: occurrences, dayKey: day))
    }

    @Test func anOpenQuestOrAnOpenRoutineKeepsTheDayOpen() {
        let done = JournalFixtures.occurrence("Trash", due: day, completed: day)
        let open = JournalFixtures.occurrence("Gym", due: day)
        #expect(!JournalEntryToday.allCleared(quests: [quest(done: true), quest(done: false)], occurrences: [done], dayKey: day))
        #expect(!JournalEntryToday.allCleared(quests: [quest(done: true)], occurrences: [done, open], dayKey: day))
    }

    @Test func replacedItemsAreNotTheDaysAsk() {
        let replacedRoutine = JournalFixtures.occurrence("Old", due: day)
        replacedRoutine.replacedByID = UUID()
        #expect(JournalEntryToday.allCleared(quests: [quest(done: true), quest(done: false, replaced: true)],
                                             occurrences: [replacedRoutine], dayKey: day))
    }

    @Test func otherDaysRowsDoNotCount() {
        let yesterdayOpen = JournalFixtures.occurrence("Overdue", due: "2026-09-17")
        #expect(JournalEntryToday.allCleared(quests: [quest(done: true), quest(done: false, on: "2026-09-17")],
                                             occurrences: [yesterdayOpen], dayKey: day))
    }

    @Test func theHiddenQuestDrawnAfterTheClearDoesNotReopenTheDay() {
        #expect(JournalEntryToday.allCleared(quests: [quest(done: true), quest(done: false, hidden: true)],
                                             occurrences: [], dayKey: day))
    }

    @Test func theWeeklyEpicAndNonGatingRoutinesDoNotHoldTheDayOpen() {
        let checkIn = JournalFixtures.occurrence("Check in", due: day)
        checkIn.countsForClear = false
        #expect(JournalEntryToday.allCleared(quests: [quest(done: true), quest(done: false, slot: .epic)],
                                             occurrences: [checkIn], dayKey: day))
        #expect(!JournalEntryToday.allCleared(quests: [quest(done: false, slot: .epic)], occurrences: [checkIn], dayKey: day))
    }

    // MARK: last night

    private func day(_ key: String, words: String) -> JournalEntryDay {
        JournalEntryDay(dayKey: key, document: F.doc(F.text(1, words)), isDone: false, writtenAt: Date())
    }

    @Test func lastNightIsTheNewestEntryBeforeToday() {
        let days = [day("2026-09-18", words: "today"), day("2026-09-16", words: "one two three"),
                    day("2026-09-10", words: "old")]
        let last = JournalEntryToday.lastNight(in: days, today: "2026-09-18")
        #expect(last == JournalEntryToday.LastNight(dayKey: "2026-09-16", words: 3))
        #expect(last?.text == "Last night \u{00B7} 3 words")
    }

    @Test func lastNightIsNilWithNothingBeforeToday() {
        #expect(JournalEntryToday.lastNight(in: [], today: "2026-09-18") == nil)
        #expect(JournalEntryToday.lastNight(in: [day("2026-09-18", words: "x"), day("2026-09-19", words: "y")],
                                            today: "2026-09-18") == nil)
    }

    /// "A blank page." only while the page is blank: under "Written · 7 words" it read wrong.
    @Test func theCardSubtitleIsOnlyForABlankPage() {
        #expect(JournalEntryToday.cardSubtitle(.none) == "A blank page.")
        #expect(JournalEntryToday.cardSubtitle(.draft(words: 0)) == "A blank page.")
        #expect(JournalEntryToday.cardSubtitle(.draft(words: 3)) == nil)
        #expect(JournalEntryToday.cardSubtitle(.done(words: 7)) == nil)
    }
}
