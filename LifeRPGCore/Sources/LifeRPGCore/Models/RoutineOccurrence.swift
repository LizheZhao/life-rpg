import Foundation
import SwiftData

@Model public final class RoutineOccurrence {
    public var id: UUID = UUID()
    public var routineID: UUID?
    public var dueDayKey: String = ""
    public var weekKey: String = ""
    public var completedDayKey: String?
    public var textSnapshot: String = ""
    public var usedDegraded: Bool = false
    public var basePoints: Int = 0
    // Snapshotted from the routine, not read back off it: whether this occurrence gates the
    // day's full-clear (and therefore the hidden quest). PLAN.md §3.
    public var countsForClear: Bool = true
    public var awardedPoints: Int?                // late make-up = half of base × m
    public var penaltyApplied: Int = 0            // running total of escalating deductions
    public var skipped: Bool = false              // user skip, or auto on day 4
    public var completedAt: Date?

    public init() {}
}
