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
    // The routine's `degraded_text` on the day this occurrence was created, beside the original
    // in `textSnapshot` — like `DailyQuest.variantSnapshot`. Nil = no light version was on offer.
    // Added after V1 shipped: optional, so lightweight migration fills nil.
    public var degradedTextSnapshot: String?
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

    public init() {}

    /// What the page shows as the task: the light version while it is the one chosen.
    public var displayText: String {
        usedDegraded ? (degradedTextSnapshot ?? textSnapshot) : textSnapshot
    }
}
