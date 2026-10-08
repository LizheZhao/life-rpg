import Foundation
import Testing
@testable import LifeRPGCore

/// Which local notifications to queue. Pure rules: the app turns each planned item into a
/// `UNNotificationRequest`, and re-plans whenever it comes forward or leaves, which is how
/// "don't remind me, I already wrote" works (a local notification cannot look at the store when it fires).
struct NotificationPlanTests {
    private let tz = Fixtures.tokyo
    private let wednesday = "2026-10-07"

    private func at(_ day: String, hour: Int, minute: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let parts = day.split(separator: "-").compactMap { Int($0) }
        return cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: hour, minute: minute))!
    }

    private func plan(now: Date, journal: Bool = true, morning: Bool = true, morningMinute: Int = 8 * 60,
                      eveningMinute: Int = 20 * 60,
                      written: Bool = false, counts: [String: Int] = [:], days: Int = 14) -> [PlannedNotification] {
        NotificationPlan.plan(now: now, timeZone: tz,
                              settings: .init(journal: journal, morning: morning,
                                              morningMinute: morningMinute, eveningMinute: eveningMinute),
                              todayWritten: written, routineCounts: counts, days: days)
    }

    // MARK: what is planned

    @Test func aMorningDayPlansTodaysMorningAndEveryEveningAfterIt() {
        let items = plan(now: at(wednesday, hour: 6), days: 3)
        #expect(items.map(\.id) == ["morning-2026-10-07", "journal-2026-10-07", "morning-2026-10-08", "journal-2026-10-08",
                                    "morning-2026-10-09", "journal-2026-10-09"])
    }

    @Test func nothingInThePastIsPlanned() {
        // 09:00: today's 08:00 is gone, today's 20:00 is not.
        let items = plan(now: at(wednesday, hour: 9), days: 2)
        #expect(items.map(\.id) == ["journal-2026-10-07", "morning-2026-10-08", "journal-2026-10-08"])
        // 21:00: today has nothing left.
        #expect(plan(now: at(wednesday, hour: 21), days: 2).map(\.id) == ["morning-2026-10-08", "journal-2026-10-08"])
    }

    @Test func theFireTimesAreTheConfiguredTimes() {
        let items = plan(now: at(wednesday, hour: 6), morningMinute: 7 * 60 + 30, eveningMinute: 21 * 60 + 45, days: 1)
        let fires = Dictionary(uniqueKeysWithValues: items.map { ($0.kind, $0.fireDate) })
        #expect(fires[.morning] == at(wednesday, hour: 7, minute: 30))
        #expect(fires[.journal] == at(wednesday, hour: 21, minute: 45))
    }

    @Test func theDefaultsAreEightAndTwenty() {
        let settings = NotificationPlan.Settings()
        #expect(settings.morningMinute == 480)
        #expect(settings.eveningMinute == 1200)
    }

    /// Morning from 05:00 to 11:59, evening from 12:00 to 23:59; anything outside is held to the edge.
    @Test func timesOutsideTheirRangeAreHeldToTheEdge() {
        #expect(NotificationPlan.Settings(morningMinute: 60).morningMinute == 300)
        #expect(NotificationPlan.Settings(morningMinute: 13 * 60).morningMinute == 719)
        #expect(NotificationPlan.Settings(eveningMinute: 9 * 60).eveningMinute == 720)
        #expect(NotificationPlan.Settings(eveningMinute: 25 * 60).eveningMinute == 1439)
    }

    @Test func eachKindCanBeTurnedOff() {
        let now = at(wednesday, hour: 6)
        #expect(plan(now: now, journal: false, days: 2).allSatisfy { $0.kind == .morning })
        #expect(plan(now: now, morning: false, days: 2).allSatisfy { $0.kind == .journal })
        #expect(plan(now: now, journal: false, morning: false).isEmpty)
    }

    @Test func idsAreUniqueAndTheQueueStaysUnderTheSystemCap() {
        let items = plan(now: at(wednesday, hour: 6))
        #expect(Set(items.map(\.id)).count == items.count)
        #expect(items.count == 28 && items.count < 64)             // iOS keeps at most 64 pending
        #expect(NotificationPlan.horizonDays == 14)
    }

    // MARK: already written

    /// Today's evening reminder is dropped once today has writing in it; tomorrow's stays.
    @Test func todaysEveningIsDroppedWhenTodayIsWritten() {
        let items = plan(now: at(wednesday, hour: 15), written: true, days: 2)
        #expect(!items.contains { $0.id == "journal-2026-10-07" })
        #expect(items.contains { $0.id == "journal-2026-10-08" })
    }

    /// Between midnight and 05:00 the app day is still yesterday: what was written counts for
    /// yesterday, so the calendar date's own evening reminder is still wanted.
    @Test func afterMidnightTheWritingBelongsToYesterday() {
        let items = plan(now: at("2026-10-08", hour: 2), written: true, days: 2)
        #expect(items.contains { $0.id == "journal-2026-10-08" })
    }

    // MARK: copy

    @Test func theMorningNamesHowManyRoutinesAreDue() {
        let items = plan(now: at(wednesday, hour: 6), counts: ["2026-10-07": 3, "2026-10-08": 1, "2026-10-09": 0], days: 3)
        let body = { (day: String) in items.first { $0.id == "morning-\(day)" }!.body }
        #expect(body("2026-10-07").contains("3 routines"))
        #expect(body("2026-10-08").contains("1 routine") && !body("2026-10-08").contains("1 routines"))
        #expect(!body("2026-10-09").contains("0 routine"))
    }

    /// Quests are drawn when the app opens, not before, so the notification must not promise them yet.
    @Test func theMorningDoesNotClaimQuestsAreAlreadyDrawn() {
        for item in plan(now: at(wednesday, hour: 6), counts: ["2026-10-07": 2], days: 1) where item.kind == .morning {
            #expect(!item.body.lowercased().contains("generated") && !item.body.lowercased().contains("ready"), "\(item.body)")
        }
    }

    @Test func theEveningInvitesWithoutPressure() {
        let item = plan(now: at(wednesday, hour: 6), morning: false, days: 1)[0]
        #expect(item.title == "Write about today")
        #expect(!item.body.isEmpty && item.body.count < 100)
    }

    // MARK: counting routines

    @Test func routineCountsComeFromTheSchedule() {
        let monThu = RoutineTask(); monThu.text = "A"; monThu.kind = .weekly; monThu.spec = "MON,THU"
        let sat = RoutineTask(); sat.text = "B"; sat.kind = .weekly; sat.spec = "SAT"
        let off = RoutineTask(); off.text = "C"; off.kind = .weekly; off.spec = "THU"; off.isActive = false
        let gone = RoutineTask(); gone.text = "D"; gone.kind = .weekly; gone.spec = "THU"; gone.isActive = false; gone.isArchived = true
        let counts = NotificationPlan.routineCounts(routines: [monThu, sat, off, gone], occurrences: [],
                                                    from: "2026-10-05", days: 7, in: tz)
        #expect(counts["2026-10-05"] == 1)       // Monday
        #expect(counts["2026-10-08"] == 1)       // Thursday: the inactive and the archived ones don't count
        #expect(counts["2026-10-10"] == 1)       // Saturday
        #expect(counts["2026-10-06"] == nil || counts["2026-10-06"] == 0)
    }

    @Test func aWrittenDayIsAnEntryWithText() {
        #expect(NotificationPlan.isWritten(nil) == false)
        let entry = JournalEntry(); entry.dayKey = wednesday
        #expect(NotificationPlan.isWritten(entry) == false)          // a row with nothing in it
        entry.blocks = [.text(id: UUID(), text: "hello")]
        #expect(NotificationPlan.isWritten(entry))
    }
}
