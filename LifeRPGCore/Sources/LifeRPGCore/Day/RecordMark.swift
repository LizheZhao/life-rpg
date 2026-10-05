import Foundation

/// The mark at the leading edge of a day-detail row, which says how the thing ended before the
/// status text does: a check for done, an open ring for not done, a dash for swapped out (the slot
/// went to something else), a cross for cancelled or given up on (nothing took its place).
public enum RecordMark: Equatable, Sendable {
    case done, open, dashed, crossed

    public static func mark(for status: DayRecord.RoutineStatus) -> RecordMark {
        switch status {
        case .done, .doneAhead, .late: .done
        case .notDone: .open
        case .replaced: .dashed
        case .skipped, .missed: .crossed
        }
    }

    /// A cancelled quest is `replaced(.cancelled)` but, like a cancelled routine, was bought off
    /// rather than swapped, so it crosses; every other reason handed the slot to another row.
    public static func mark(for quest: DailyQuest) -> RecordMark {
        if quest.replaced { return quest.replacedReason == .cancelled ? .crossed : .dashed }
        return quest.completedAt != nil ? .done : .open
    }
}
