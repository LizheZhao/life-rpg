import Foundation
import SwiftData

/// Turning a library row off, renaming it, deleting it, changing what a routine pays, and changing
/// when a routine comes due.
///
/// Everything here only reaches forward. What is already on the page keeps its own state: an open occurrence
/// still runs its ladder or its week, and keeps the points it was created with (an occurrence
/// snapshots `basePoints`). That is also what stops "turn it off, then on again" from being a free
/// cancel — a cancel costs coins (`Redemption.cancel`).
///
/// **Rename and delete leave the row's id alone.** History, ratings and notes point at a row by id
/// (and each holds a snapshot of the words it was made with), so a rename only changes what the
/// Library calls it, and a delete is an *archive*: the row stays, unlisted, and is always inactive
/// too, so every place that draws, schedules or offers rows (they all ask `isActive`) skips it
/// without a second test. Archived is not "off": an off row is still listed and can be turned back
/// on; an archived one is only brought back by `restore`.
public enum LibraryEdit {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notFound
        case belowMinimum(Int)
        /// A rename to nothing.
        case emptyText
        /// Another row of the same table, not archived, already has these words.
        case textTaken
        /// An archived row is brought back by `restore`, not by turning it on.
        case archived
        /// A routine is easy, medium or hard: those are the tiers with a middle to pay by.
        case notARoutineTier
        /// A weekly schedule with no day in it.
        case noWeekday
        /// A downgrade version follows the routine it belongs to, and a spec the form cannot show
        /// (every N days, every N weeks, the second Saturday) is not one it can write back.
        case notEditable
        /// A session of this routine is still open, and the change would move what it is billed.
        case sessionOpen

        public var description: String {
            switch self {
            case .notFound: "that library row is gone"
            case .belowMinimum(let n): "a routine pays at least \(n)"
            case .emptyText: "it needs a name"
            case .textTaken: "the library already has one with these words"
            case .archived: "it was deleted: restore it first"
            case .notARoutineTier: "a routine is easy, medium or hard"
            case .noWeekday: "pick at least one day"
            case .notEditable: "this routine's schedule can't be changed here"
            case .sessionOpen: "a session of it is still open: finish or skip it first"
            }
        }
    }

    /// The least a routine can pay: a penalty is a share of it, so zero would charge nothing.
    public static let minimumPoints = 5
    /// What a step on the points control moves it by.
    public static let pointsStep = 5

    public static func setActive(_ active: Bool, _ target: FeedbackTarget, id: UUID,
                                 in context: ModelContext) throws {
        switch target {
        case .quest:
            guard let row = try context.fetch(FetchDescriptor<QuestTemplate>(predicate: #Predicate { $0.id == id })).first
            else { throw Failure.notFound }
            guard !(active && row.isArchived) else { throw Failure.archived }
            row.isActive = active
        case .routine:
            guard let row = try context.fetch(FetchDescriptor<RoutineTask>(predicate: #Predicate { $0.id == id })).first
            else { throw Failure.notFound }
            guard !(active && row.isArchived) else { throw Failure.archived }
            row.isActive = active
        }
        try context.save()
    }

    /// No ceiling (decided with the user: it is their own ledger); never under `minimumPoints`.
    public static func setBasePoints(_ points: Int, forRoutine id: UUID, in context: ModelContext) throws {
        guard points >= minimumPoints else { throw Failure.belowMinimum(minimumPoints) }
        guard let row = try context.fetch(FetchDescriptor<RoutineTask>(predicate: #Predicate { $0.id == id })).first
        else { throw Failure.notFound }
        row.basePoints = points
        try context.save()
    }

    /// Sets a routine's difficulty, and with it what it pays: the middle of the tier's range
    /// (`AdHoc.basePoints`), so nobody has to pick a number. Reaches forward only.
    public static func setDifficulty(_ difficulty: Difficulty, forRoutine id: UUID,
                                     in context: ModelContext) throws {
        guard let points = AdHoc.basePoints(for: difficulty) else { throw Failure.notARoutineTier }
        guard let row = try context.fetch(FetchDescriptor<RoutineTask>(predicate: #Predicate { $0.id == id })).first
        else { throw Failure.notFound }
        row.difficulty = difficulty
        row.basePoints = points
        try context.save()
    }

    // MARK: when a routine comes due

    /// Whether a session of the routine is still open: due, not done, not skipped, not swapped for
    /// something else. Takes the rows a view already holds.
    public static func sessionIsOpen(routineID: UUID, occurrences: [RoutineOccurrence]) -> Bool {
        occurrences.contains { $0.routineID == routineID && Schedule.isOpen($0) && !$0.isReplaced }
    }

    /// The schedule form's starting point, from what the row says now. Nil when the row is not
    /// one the form can write back: a downgrade version (it follows its routine), or a spec other
    /// than weekly days or the first / last given weekday of the month.
    public static func scheduleDraft(of routine: RoutineTask, in routines: [RoutineTask]) -> LibrarySave.Draft? {
        guard !Degrade.versionIDs(in: routines).contains(routine.id), let spec = routine.frequency else { return nil }
        var draft = LibrarySave.Draft()
        draft.kind = .routine
        draft.flexible = routine.flexibleWithinWeek
        switch spec {
        case .weekly(let days):
            draft.frequency = .weekly
            draft.days = Set(days)
            draft.timesPerWeek = min(max(routine.weeklyTarget, 1), max(days.count, 1))
        case .nthWeekdayOfMonth(let n, let weekday) where n == 1 || n == -1:
            draft.frequency = .monthly
            draft.position = n == 1 ? .first : .last
            draft.monthlyWeekday = weekday
        default:
            return nil
        }
        return draft
    }

    /// Changes when a routine comes due. Days reach forward only: a session already on the page
    /// keeps its due day, and `Schedule.dueRoutines` reads the new days from tomorrow on.
    ///
    /// Refused while a session of the routine is open when it would switch fixed / flexible or
    /// lower a flexible week's target: `Overdue.settle` reads both off the row as it is now, so
    /// either would be a way out of a bill the open session is already running. Raising the target
    /// is fine, since the bill is capped by the sessions that actually came due.
    public static func setSchedule(_ draft: LibrarySave.Draft, forRoutine id: UUID,
                                   in context: ModelContext) throws {
        let routines = try context.fetch(FetchDescriptor<RoutineTask>())
        guard let row = routines.first(where: { $0.id == id }) else { throw Failure.notFound }
        guard scheduleDraft(of: row, in: routines) != nil else { throw Failure.notEditable }
        guard draft.kind == .routine else { throw Failure.notEditable }

        let resolved: LibrarySave.Resolved
        do {
            resolved = try LibrarySave.resolve(draft.cadence, flexible: draft.flexible, timesPerWeek: draft.timesToSave)
        } catch LibrarySave.Failure.noWeekday {
            throw Failure.noWeekday
        }

        let switches = draft.flexible != row.flexibleWithinWeek
        let lowers = row.flexibleWithinWeek && draft.flexible && resolved.weeklyTarget < row.weeklyTarget
        if switches || lowers,
           sessionIsOpen(routineID: id, occurrences: try context.fetch(FetchDescriptor<RoutineOccurrence>())) {
            throw Failure.sessionOpen
        }

        row.kind = resolved.kind
        row.spec = resolved.spec
        row.weeklyTarget = resolved.weeklyTarget
        row.flexibleWithinWeek = draft.flexible
        try context.save()
    }

    // MARK: rename, delete, restore

    /// Renames in place: same id, so every reference keeps resolving, and the history keeps the
    /// words it was made with. Words are unique within a table among the rows that are listed.
    public static func rename(_ text: String, _ target: FeedbackTarget, id: UUID,
                              in context: ModelContext) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure.emptyText }
        func taken(_ others: [(id: UUID, text: String, archived: Bool)]) -> Bool {
            others.contains { $0.id != id && !$0.archived
                && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(text) == .orderedSame }
        }
        switch target {
        case .quest:
            let rows = try context.fetch(FetchDescriptor<QuestTemplate>())
            guard let row = rows.first(where: { $0.id == id }) else { throw Failure.notFound }
            guard !taken(rows.map { ($0.id, $0.text, $0.isArchived) }) else { throw Failure.textTaken }
            row.text = text
        case .routine:
            let rows = try context.fetch(FetchDescriptor<RoutineTask>())
            guard let row = rows.first(where: { $0.id == id }) else { throw Failure.notFound }
            guard !taken(rows.map { ($0.id, $0.text, $0.isArchived) }) else { throw Failure.textTaken }
            row.text = text
        }
        try context.save()
    }

    /// Deletes a row as far as the Library is concerned (see the type's note). A routine takes with
    /// it the lighter versions nothing else still offers, since a lighter version is only ever
    /// reached through a routine.
    public static func archive(_ target: FeedbackTarget, id: UUID, in context: ModelContext) throws {
        switch target {
        case .quest:
            guard let row = try context.fetch(FetchDescriptor<QuestTemplate>(predicate: #Predicate { $0.id == id })).first
            else { throw Failure.notFound }
            row.isArchived = true
            row.isActive = false
        case .routine:
            let rows = try context.fetch(FetchDescriptor<RoutineTask>())
            guard let row = rows.first(where: { $0.id == id }) else { throw Failure.notFound }
            row.isArchived = true
            row.isActive = false
            for versionID in row.downgradeIDs {
                guard let version = rows.first(where: { $0.id == versionID }), !version.isArchived,
                      !rows.contains(where: { $0.id != row.id && !$0.isArchived && $0.downgradeIDs.contains(versionID) })
                else { continue }
                version.isArchived = true
                version.isActive = false
            }
        }
        try context.save()
    }

    /// Brings an archived row back, listed and on. A routine brings back its archived lighter
    /// versions too. A row that was never archived is left as it is: this is not a way to turn a
    /// row back on.
    public static func restore(_ target: FeedbackTarget, id: UUID, in context: ModelContext) throws {
        switch target {
        case .quest:
            guard let row = try context.fetch(FetchDescriptor<QuestTemplate>(predicate: #Predicate { $0.id == id })).first
            else { throw Failure.notFound }
            if row.isArchived { row.isArchived = false; row.isActive = true }
        case .routine:
            let rows = try context.fetch(FetchDescriptor<RoutineTask>())
            guard let row = rows.first(where: { $0.id == id }) else { throw Failure.notFound }
            if row.isArchived {
                row.isArchived = false
                row.isActive = true
                for version in rows where row.downgradeIDs.contains(version.id) && version.isArchived {
                    version.isArchived = false
                    version.isActive = true
                }
            }
        }
        try context.save()
    }

    /// The rows the Library lists, and the ones it keeps under "Archived".
    public static func listed<Row: LibraryRow>(_ rows: [Row]) -> [Row] { rows.filter { !$0.isArchived } }
    public static func archived<Row: LibraryRow>(_ rows: [Row]) -> [Row] { rows.filter(\.isArchived) }
}

public protocol LibraryRow { var isArchived: Bool { get } }
extension QuestTemplate: LibraryRow {}
extension RoutineTask: LibraryRow {}
