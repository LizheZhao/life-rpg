import Foundation
import SwiftData

@Model public final class RoutineOccurrence {
    public var id: UUID = UUID()
    public var routineID: UUID?
    public var dueDayKey: String = ""
    public var weekKey: String = ""
    public var completedDayKey: String?
    public var textSnapshot: String = ""
    // Which version is (or was) done: set on a low day when the routine has a light version, and
    // switchable back to the original until the occurrence is closed (`Degrade.choose`).
    public var usedDegraded: Bool = false
    // The downgrade version drawn for this occurrence, snapshotted beside the original in
    // `textSnapshot` — like `DailyQuest.variantSnapshot`. Nil = no light version was on offer.
    public var degradedTextSnapshot: String?
    // Which `RoutineTask` that downgrade version is. History keeps the text above; this is read
    // back only for the light version's own auto-verify rule (a 30-minute walk, not the
    // 40-minute rule of the strength routine it replaces).
    public var degradedRoutineID: UUID?
    // The downgrade version's own `basePoints`. The light version pays its own points, so the
    // number has to be snapshotted too — switching back to the original returns to `basePoints`.
    public var degradedBasePoints: Int?
    public var basePoints: Int = 0
    // Snapshotted from the routine, not read back off it: whether this occurrence gates the
    // day's full-clear (and therefore the hidden quest). PLAN.md §3.
    public var countsForClear: Bool = true
    public var awardedPoints: Int?                // late make-up = half of base × m
    public var penaltyApplied: Int = 0            // running total of escalating deductions
    public var skipped: Bool = false              // user skip, or auto on day 4
    public var completedAt: Date?
    // `SourceType` raw value, as on `DailyQuest`. Added after V1 shipped: a defaulted field, so
    // lightweight migration fills "manual" — which every earlier completion was.
    public var sourceTypeRaw: String = "manual"
    // Ad-hoc (`PLAN.md` §3): the random slot this occurrence took over. Non-nil = ad-hoc, and
    // then `routineID` is nil on purpose, so scheduling, flexible settlement and the weekly
    // target never see it. Added after V1 shipped: optional, so lightweight migration fills nil.
    public var replacesQuestID: UUID?
    // Ad-hoc from the library: which routine it was picked from. History only — nothing reads
    // it back as a schedule link.
    public var adHocSourceRoutineID: UUID?
    // Swapped by hand for an ad-hoc occurrence (`AdHoc.replaceRoutine`): the id of the one that
    // took over. The row is also `skipped`, which closes it everywhere; this is what tells "swapped
    // for something at least as heavy" apart from "gave up" (backlog, day detail, calendar).
    // Added after V2 shipped: optional, so lightweight migration fills nil.
    public var replacedByID: UUID?
    // The doodle picked for a custom ad-hoc routine (`DoodleKey.rawValue`). Nil = none chosen, so
    // the text decides (`DoodleKey.forText`) — which is every row from before `SchemaV4`. Read
    // only through `doodle`, which also survives a key this build doesn't know.
    public var iconKey: String?

    public init() {}

    public var isReplaced: Bool { replacedByID != nil }

    /// What the page shows as the task: the light version while it is the one chosen.
    public var displayText: String {
        usedDegraded ? (degradedTextSnapshot ?? textSnapshot) : textSnapshot
    }

    /// The doodle this row wears: its chosen one, else the one its text suggests.
    public var doodle: DoodleKey { DoodleKey.resolve(iconKey: iconKey, text: displayText) }

    /// The base the version currently chosen is worth — what scoring and the overdue penalty are
    /// both measured against, so a day that only asked for a walk is neither paid nor charged as
    /// if it had asked for the full session.
    public var effectiveBasePoints: Int {
        usedDegraded ? (degradedBasePoints ?? basePoints) : basePoints
    }
}
