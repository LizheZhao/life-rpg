import Foundation

/// A flexible routine that can be done ahead today, as the row the Ahead section shows: the same
/// facts a routine row carries (what it pays, its strikes this week) and the day it is next due.
public struct AheadCandidateState: Equatable, Identifiable, Sendable {
    /// The routine's id, not an occurrence's: doing it now is what creates the occurrence.
    public let id: UUID
    public let title: String
    public let doodle: DoodleKey
    public let pills: [PillState]
    public let accessibilityLabel: String
    public let accessibilityValue: String

    /// - Parameters:
    ///   - routines: every routine the page's query holds, for the light versions on offer.
    ///   - tier: on a low day only a lighter version is drawn when it is done, so what it pays is
    ///     the span across those versions rather than a number the draw could contradict.
    public init(_ ahead: Schedule.Ahead, routines: [RoutineTask], today: String, tier: Tier,
                in timeZone: TimeZone = .current) {
        let routine = ahead.routine
        let versions = Degrade.versions(of: routine, in: routines).map(\.basePoints)
        let bases = tier.isLow && routine.canDegrade ? versions : [routine.basePoints]
        let points = bases.map { Scoring.routinePoints(basePoints: $0, tier: tier, late: false) }
        let pays = (points.min() ?? 0)...(points.max() ?? 0)
        let due = PresentationText.dueIn(ahead.nextDueDayKey, from: today, in: timeZone)
        // Nothing to say before the first one.
        let strikes = ahead.doneThisWeek > 0
            ? "\(ahead.doneThisWeek) strike\(ahead.doneThisWeek == 1 ? "" : "s") this week" : nil

        id = routine.id
        title = routine.text
        doodle = DoodleKey.forText(routine.text)
        pills = [PillState("+\(PresentationText.range(pays))", .payout)]
            + (strikes.map { [PillState($0, .plain)] } ?? []) + [PillState(due, .plain)]
        accessibilityLabel = "\(routine.text), pays \(PresentationText.spokenRange(pays)), \(due)"
        accessibilityValue = strikes.map { "\($0), not done" } ?? "not done"
    }
}

/// One row of the Ahead section. Done-ahead and still-open routines are ordinary routine rows.
public enum AheadItem: Equatable, Identifiable, Sendable {
    case routine(RoutineRowState)
    case candidate(AheadCandidateState)

    public var id: UUID {
        switch self {
        case .routine(let s): s.id
        case .candidate(let s): s.id
        }
    }
}

/// The rest of the week's flexible work: sessions from earlier days still open (full pay until
/// Sunday), what was pulled forward today, and what can be. Which is which is `Schedule`'s rule;
/// this gathers the rows and words the header.
public struct AheadState: Equatable, Sendable {
    public let items: [AheadItem]
    public let openCount: Int
    public let doneCount: Int
    /// What Sunday night's settlement charges if nothing more is done, e.g. `−13 Sun night`.
    public let billText: String?
    private let bill: Int

    public var isEmpty: Bool { items.isEmpty }
    /// `5 open`: the hand label beside the header. What is done ahead is not counted in it, so the
    /// header and Sunday's bill fit on one line; VoiceOver hears it.
    public var summary: String { "\(openCount) open" }
    public var accessibilityLabel: String {
        "Ahead this week, \(openCount) open" + (doneCount > 0 ? ", \(doneCount) done" : "")
            + (bill > 0 ? ", minus \(bill) coins Sunday night" : "")
    }

    /// - Parameters:
    ///   - flexible: the ids of the flexible routines, which the page already holds.
    ///   - routineState: the page's builder for a routine row.
    public init(routines: [RoutineTask], occurrences: [RoutineOccurrence], flexible: Set<UUID>,
                today: String, tier: Tier, in timeZone: TimeZone = .current,
                routineState: (RoutineOccurrence, RoutineRowState.Placement) -> RoutineRowState) {
        let open = Schedule.openThisWeek(occurrences, flexible: flexible, on: today, in: timeZone)
        let done = Schedule.doneAhead(occurrences, on: today)
        let candidates = Schedule.aheadCandidates(routines, occurrences: occurrences, on: today, in: timeZone)

        items = open.map { AheadItem.routine(routineState($0, .thisWeek)) }
            + done.map { AheadItem.routine(routineState($0, .thisWeek)) }
            + candidates.map { AheadItem.candidate(AheadCandidateState($0, routines: routines, today: today,
                                                                       tier: tier, in: timeZone)) }
        openCount = open.count + candidates.count
        doneCount = done.count
        bill = DayKey.weekKey(of: today, in: timeZone)
            .map { Overdue.weekly(routines, occurrences: occurrences, weekKey: $0).total } ?? 0
        billText = bill > 0 ? "−\(bill) Sun night" : nil
    }
}
