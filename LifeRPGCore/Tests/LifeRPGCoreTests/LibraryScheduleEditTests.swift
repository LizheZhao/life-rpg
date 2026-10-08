import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// Changing when a library routine comes due. Like points, a schedule change only reaches
/// forward: what is already on the page keeps the day it was due. The one thing a change must not
/// be is a way out of a bill — `Overdue.settle` reads `flexibleWithinWeek` and `weeklyTarget` off
/// the routine row *as it is now* — so those two are refused while a session of the routine is
/// still open.
struct LibraryScheduleEditTests {
    private let tz = Fixtures.tokyo
    private let monday = "2026-09-21"      // 2026-W39
    private let tuesday = "2026-09-22"
    private let thursday = "2026-09-24"
    private let week = "2026-W39"

    private func routine(_ ctx: ModelContext, _ text: String = "Piano",
                         kind: RecurrenceKind = .weekly, spec: String = "MON,THU",
                         flexible: Bool = false, target: Int? = nil) -> RoutineTask {
        let r = RoutineTask()
        r.text = text; r.kind = kind; r.spec = spec; r.flexibleWithinWeek = flexible
        r.weeklyTarget = target ?? (kind == .weekly ? spec.split(separator: ",").count : 1)
        ctx.insert(r)
        return r
    }

    private func draft(_ days: Set<Weekday>, flexible: Bool = false, times: Int = 1) -> LibrarySave.Draft {
        var d = LibrarySave.Draft()
        d.kind = .routine
        d.days = days
        d.flexible = flexible
        d.timesPerWeek = times
        return d
    }

    private func due(_ r: RoutineTask, _ day: String, _ occurrences: [RoutineOccurrence] = []) -> Bool {
        !Schedule.dueRoutines([r], occurrences: occurrences, on: day, in: tz).isEmpty
    }

    // MARK: the days

    @Test func newDaysApplyFromNowOn() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx)
        try ctx.save()
        #expect(due(r, monday) && due(r, thursday) && !due(r, tuesday))

        try LibraryEdit.setSchedule(draft([.tuesday, .saturday]), forRoutine: r.id, in: ctx)
        #expect(r.kind == .weekly && r.spec == "TUE,SAT" && r.weeklyTarget == 2 && !r.flexibleWithinWeek)
        #expect(!due(r, monday) && !due(r, thursday))
        #expect(due(r, tuesday) && due(r, "2026-09-26"))
    }

    /// An occurrence is a row with its own due day, so what is open keeps it.
    @Test func whatIsAlreadyOnThePageKeepsItsDueDay() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx)
        let o = RoutineOccurrence(routine: r, dueDayKey: monday, weekKey: week)
        ctx.insert(o)
        try ctx.save()

        try LibraryEdit.setSchedule(draft([.friday]), forRoutine: r.id, in: ctx)
        #expect(o.dueDayKey == monday && Schedule.isOpen(o) && o.penaltyApplied == 0)
        #expect(o.weekKey == week && !o.skipped)
    }

    @Test func changingTheDaysIsAllowedWhileASessionIsOpen() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx)
        ctx.insert(RoutineOccurrence(routine: r, dueDayKey: monday, weekKey: week))
        try ctx.save()
        try LibraryEdit.setSchedule(draft([.monday, .wednesday, .friday]), forRoutine: r.id, in: ctx)
        #expect(r.spec == "MON,WED,FRI")
    }

    @Test func weeklyNeedsAtLeastOneDayAndTheRowIsLeftAsItWas() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx)
        try ctx.save()
        #expect(throws: LibraryEdit.Failure.noWeekday) {
            try LibraryEdit.setSchedule(draft([]), forRoutine: r.id, in: ctx)
        }
        #expect(r.spec == "MON,THU" && r.weeklyTarget == 2)
    }

    // MARK: weekly and monthly, in both directions

    @Test func aRoutineCanMoveBetweenWeeklyAndMonthly() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx)
        try ctx.save()

        var monthly = LibrarySave.Draft()
        monthly.kind = .routine
        monthly.frequency = .monthly
        monthly.position = .last
        monthly.monthlyWeekday = .saturday
        try LibraryEdit.setSchedule(monthly, forRoutine: r.id, in: ctx)
        #expect(r.kind == .nthWeekdayOfMonth && r.spec == "-1:SAT" && r.weeklyTarget == 1 && !r.flexibleWithinWeek)
        #expect(due(r, "2026-09-26") && !due(r, "2026-09-19"))

        try LibraryEdit.setSchedule(draft([.sunday]), forRoutine: r.id, in: ctx)
        #expect(r.kind == .weekly && r.spec == "SUN" && r.weeklyTarget == 1)
    }

    @Test func flexibleTimesAreClampedToTheDaysChosen() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx)
        try ctx.save()
        try LibraryEdit.setSchedule(draft([.monday, .wednesday, .friday], flexible: true, times: 2),
                                    forRoutine: r.id, in: ctx)
        #expect(r.flexibleWithinWeek && r.weeklyTarget == 2)
        try LibraryEdit.setSchedule(draft([.monday, .wednesday, .friday], flexible: true, times: 9),
                                    forRoutine: r.id, in: ctx)
        #expect(r.weeklyTarget == 3)
    }

    // MARK: what is not editable

    @Test func aDowngradeVersionAndOtherKindsAreNotEditable() throws {
        let ctx = try Fixtures.context()
        let parent = routine(ctx, "Walk")
        let light = routine(ctx, "Short walk", kind: .weekly, spec: "", target: 1)
        parent.downgradeIDs = [light.id]
        let everyThree = routine(ctx, "Water the plants", kind: .everyNDays, spec: "3", target: 1)
        let secondSaturday = routine(ctx, "Review", kind: .nthWeekdayOfMonth, spec: "2:SAT", target: 1)
        try ctx.save()
        let all = [parent, light, everyThree, secondSaturday]

        for r in [light, everyThree, secondSaturday] {
            #expect(LibraryEdit.scheduleDraft(of: r, in: all) == nil)
            #expect(throws: LibraryEdit.Failure.notEditable) {
                try LibraryEdit.setSchedule(draft([.monday]), forRoutine: r.id, in: ctx)
            }
        }
        #expect(everyThree.spec == "3" && secondSaturday.spec == "2:SAT")
        #expect(LibraryEdit.scheduleDraft(of: parent, in: all) != nil)
    }

    @Test func aRowThatIsGoneIsAnError() throws {
        let ctx = try Fixtures.context()
        #expect(throws: LibraryEdit.Failure.notFound) {
            try LibraryEdit.setSchedule(draft([.monday]), forRoutine: UUID(), in: ctx)
        }
    }

    // MARK: what the form starts from

    @Test func theFormStartsFromWhatTheRowSays() throws {
        let ctx = try Fixtures.context()
        let weekly = routine(ctx, "A", spec: "MON,WED,FRI", flexible: true, target: 2)
        let first = routine(ctx, "B", kind: .nthWeekdayOfMonth, spec: "1:MON", flexible: true, target: 1)
        let last = routine(ctx, "C", kind: .nthWeekdayOfMonth, spec: "-1:SAT", target: 1)
        try ctx.save()
        let all = [weekly, first, last]

        let w = try #require(LibraryEdit.scheduleDraft(of: weekly, in: all))
        #expect(w.kind == .routine && w.frequency == .weekly && w.days == [.monday, .wednesday, .friday])
        #expect(w.flexible && w.timesPerWeek == 2)
        let f = try #require(LibraryEdit.scheduleDraft(of: first, in: all))
        #expect(f.frequency == .monthly && f.position == .first && f.monthlyWeekday == .monday && f.flexible)
        let l = try #require(LibraryEdit.scheduleDraft(of: last, in: all))
        #expect(l.frequency == .monthly && l.position == .last && l.monthlyWeekday == .saturday && !l.flexible)
    }

    /// Saving the form untouched changes nothing.
    @Test func savingTheFormAsItIsChangesNothing() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx, spec: "MON,WED,FRI", flexible: true, target: 2)
        try ctx.save()
        let form = try #require(LibraryEdit.scheduleDraft(of: r, in: [r]))
        try LibraryEdit.setSchedule(form, forRoutine: r.id, in: ctx)
        #expect(r.spec == "MON,WED,FRI" && r.weeklyTarget == 2 && r.flexibleWithinWeek && r.kind == .weekly)
    }

    // MARK: not a way out of a bill

    @Test func switchingFixedAndFlexibleIsRefusedWhileASessionIsOpen() throws {
        let ctx = try Fixtures.context()
        let fixed = routine(ctx, "Fixed", spec: "MON")
        let flexible = routine(ctx, "Flexible", spec: "MON,WED,FRI", flexible: true, target: 3)
        ctx.insert(RoutineOccurrence(routine: fixed, dueDayKey: monday, weekKey: week))
        ctx.insert(RoutineOccurrence(routine: flexible, dueDayKey: monday, weekKey: week))
        try ctx.save()

        #expect(throws: LibraryEdit.Failure.sessionOpen) {
            try LibraryEdit.setSchedule(draft([.monday], flexible: true), forRoutine: fixed.id, in: ctx)
        }
        #expect(throws: LibraryEdit.Failure.sessionOpen) {
            try LibraryEdit.setSchedule(draft([.monday, .wednesday, .friday], flexible: false),
                                        forRoutine: flexible.id, in: ctx)
        }
        #expect(!fixed.flexibleWithinWeek && flexible.flexibleWithinWeek && flexible.weeklyTarget == 3)
    }

    @Test func loweringAFlexibleTargetIsRefusedWhileASessionIsOpenButRaisingIsNot() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx, spec: "MON,WED,FRI", flexible: true, target: 2)
        ctx.insert(RoutineOccurrence(routine: r, dueDayKey: monday, weekKey: week))
        try ctx.save()

        #expect(throws: LibraryEdit.Failure.sessionOpen) {
            try LibraryEdit.setSchedule(draft([.monday, .wednesday, .friday], flexible: true, times: 1),
                                        forRoutine: r.id, in: ctx)
        }
        #expect(r.weeklyTarget == 2)
        try LibraryEdit.setSchedule(draft([.monday, .wednesday, .friday], flexible: true, times: 3),
                                    forRoutine: r.id, in: ctx)
        #expect(r.weeklyTarget == 3)
    }

    /// Done, skipped and swapped-away sessions are not open, so they hold nothing back.
    @Test func theLockLiftsWhenNothingOfTheRoutineIsOpen() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx, spec: "MON,THU")
        let done = RoutineOccurrence(routine: r, dueDayKey: monday, weekKey: week)
        done.completedDayKey = monday
        let skipped = RoutineOccurrence(routine: r, dueDayKey: "2026-09-14", weekKey: "2026-W38")
        skipped.skipped = true
        let swapped = RoutineOccurrence(routine: r, dueDayKey: "2026-09-15", weekKey: "2026-W38")
        swapped.replacedByID = UUID()
        [done, skipped, swapped].forEach(ctx.insert)
        try ctx.save()

        #expect(!LibraryEdit.sessionIsOpen(routineID: r.id, occurrences: [done, skipped, swapped]))
        try LibraryEdit.setSchedule(draft([.monday, .thursday], flexible: true, times: 1), forRoutine: r.id, in: ctx)
        #expect(r.flexibleWithinWeek && r.weeklyTarget == 1)
    }

    /// Another routine's open session is not this one's.
    @Test func onlyTheRoutinesOwnOpenSessionsCount() throws {
        let ctx = try Fixtures.context()
        let a = routine(ctx, "A", spec: "MON")
        let b = routine(ctx, "B", spec: "MON")
        let open = RoutineOccurrence(routine: b, dueDayKey: monday, weekKey: week)
        ctx.insert(open)
        try ctx.save()
        #expect(!LibraryEdit.sessionIsOpen(routineID: a.id, occurrences: [open]))
        #expect(LibraryEdit.sessionIsOpen(routineID: b.id, occurrences: [open]))
        try LibraryEdit.setSchedule(draft([.monday], flexible: true), forRoutine: a.id, in: ctx)
        #expect(a.flexibleWithinWeek)
    }

    /// Why a mid-week target change is safe once a session is open: the bill is capped by the
    /// sessions that actually came due, so a higher target cannot charge for a day that never came.
    @Test func aRaisedTargetCannotBillMoreThanTheSessionsThatCameDue() throws {
        let ctx = try Fixtures.context()
        let r = routine(ctx, spec: "MON,WED,FRI", flexible: true, target: 1)
        r.basePoints = 20
        let o = RoutineOccurrence(routine: r, dueDayKey: monday, weekKey: week)
        ctx.insert(o)
        try ctx.save()
        try LibraryEdit.setSchedule(draft([.monday, .wednesday, .friday], flexible: true, times: 3),
                                    forRoutine: r.id, in: ctx)
        let bill = Overdue.weekly([r], occurrences: [o], weekKey: week)
        #expect(bill.charges.count == 1)                       // one session came due, one shortfall at most
    }

    // MARK: the seed does not undo it

    private let sideCSV = """
    text,difficulty,hidden_eligible,weekend_only,cooldown_days,auto_verify,launch_url,variants,is_active
    Seed quest,E,FALSE,FALSE,,,,,TRUE
    """
    private let routineCSV = """
    text,frequency_kind,frequency_spec,weekly_target,base_points,difficulty,flexible_within_week,counts_for_clear,is_active,downgrade_of,auto_verify,launch_url,notes
    Seed routine,weekly,SAT,1,25,E,FALSE,TRUE,TRUE,,,,
    """

    private func seeded() throws -> ModelContext {
        let ctx = try Fixtures.context()
        try SeedImporter.seedIfEmpty(ctx, sideQuestsCSV: sideCSV, routinesCSV: routineCSV)
        return ctx
    }

    @Test func aSecondSeedCallAfterAnEditLeavesTheEditAlone() throws {
        let ctx = try seeded()
        let r = try #require(try ctx.fetch(FetchDescriptor<RoutineTask>()).first)
        try LibraryEdit.setSchedule(draft([.monday, .friday]), forRoutine: r.id, in: ctx)
        try SeedImporter.seedIfEmpty(ctx, sideQuestsCSV: sideCSV, routinesCSV: routineCSV)
        #expect(r.spec == "MON,FRI" && r.weeklyTarget == 2)
    }

    // MARK: the backup

    @Test func aChangedScheduleIsRestored() throws {
        let source = try seeded()
        let r = try #require(try source.fetch(FetchDescriptor<RoutineTask>()).first)
        try LibraryEdit.setSchedule(draft([.monday, .wednesday, .friday], flexible: true, times: 2),
                                    forRoutine: r.id, in: source)

        let target = try seeded()                                             // a fresh install: Saturdays
        let plan = try JSONImport.plan(try JSONExport.data(source), against: target)
        try JSONImport.apply(plan, to: target)
        let back = try #require(try target.fetch(FetchDescriptor<RoutineTask>()).first)
        #expect(back.spec == "MON,WED,FRI" && back.weeklyTarget == 2 && back.flexibleWithinWeek)
        #expect(due(back, monday) && !due(back, "2026-09-26"))
    }

    /// What the restore writes must be something the schedule can read: a spec that does not parse
    /// is refused by the audit (it would be a routine that is never due) and nothing changes.
    @Test func aScheduleTheCalendarCannotReadIsRefused() throws {
        let ctx = try seeded()
        var s = try JSONExport.snapshot(ctx)
        s.fullLibrary?.routines[0].spec = "TUES"
        let plan = try JSONImport.plan(try JSONExport.encode(s), against: ctx)
        #expect(throws: JSONImport.Failure.self) { try JSONImport.apply(plan, to: ctx) }
        let r = try #require(try ctx.fetch(FetchDescriptor<RoutineTask>()).first)
        #expect(r.spec == "SAT")
        #expect(try StoreAudit.issues(ctx).isEmpty)
    }

    @Test func aScheduleEditedOnTheUsersOwnRoutineTravelsWithIt() throws {
        let source = try Fixtures.context()
        let mine = try LibrarySave.saveRoutine(text: "Piano", .init(difficulty: .easy, every: .weekly([.monday])), in: source)
        try LibraryEdit.setSchedule(draft([.tuesday, .thursday], flexible: true, times: 1), forRoutine: mine.id, in: source)

        let target = try Fixtures.context()
        let plan = try JSONImport.plan(try JSONExport.data(source), against: target)
        try JSONImport.apply(plan, to: target)
        let back = try #require(try target.fetch(FetchDescriptor<RoutineTask>()).first { $0.text == "Piano" })
        #expect(back.spec == "TUE,THU" && back.flexibleWithinWeek && back.weeklyTarget == 1)
    }
}
