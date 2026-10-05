import Foundation
import Testing
@testable import LifeRPGCore

/// The leading mark on a day-detail row: check, open ring, dash, cross.
struct RecordMarkTests {
    @Test func routineStatusesMapToMarks() {
        #expect(RecordMark.mark(for: DayRecord.RoutineStatus.done) == .done)
        #expect(RecordMark.mark(for: DayRecord.RoutineStatus.doneAhead(on: "2026-09-15")) == .done)
        #expect(RecordMark.mark(for: DayRecord.RoutineStatus.late(on: "2026-09-18")) == .done)
        #expect(RecordMark.mark(for: DayRecord.RoutineStatus.notDone) == .open)
        #expect(RecordMark.mark(for: DayRecord.RoutineStatus.replaced) == .dashed)
        // Paid to cancel and given up on by the settlement both end unfinished: a cross.
        #expect(RecordMark.mark(for: DayRecord.RoutineStatus.skipped) == .crossed)
        #expect(RecordMark.mark(for: DayRecord.RoutineStatus.missed) == .crossed)
    }

    private func quest(replaced reason: ReplacedReason? = nil, done: Bool = false) -> DailyQuest {
        let q = DailyQuest()
        if let reason {
            q.replaced = true
            q.replacedReason = reason
        }
        if done { q.completedAt = Date(timeIntervalSince1970: 0) }
        return q
    }

    @Test func questMarks() {
        #expect(RecordMark.mark(for: quest(done: true)) == .done)
        #expect(RecordMark.mark(for: quest()) == .open)
        #expect(RecordMark.mark(for: quest(replaced: .cancelled)) == .crossed)
        for reason in [ReplacedReason.adHoc, .replan, .rerolled, .swapped] {
            #expect(RecordMark.mark(for: quest(replaced: reason)) == .dashed)
        }
    }
}
