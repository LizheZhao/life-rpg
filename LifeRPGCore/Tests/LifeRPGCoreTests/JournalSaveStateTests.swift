import Foundation
import Testing
@testable import LifeRPGCore

struct JournalSaveStateTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func label(pending: Bool = false, failed: Bool = false, wrote: Double? = nil, at: Double = 0,
                       reopened: Bool = false) -> String {
        JournalSaveState.label(pending: pending, failed: failed,
                               lastWriteAt: wrote.map { t0.addingTimeInterval($0) },
                               now: t0.addingTimeInterval(at), reopenedDone: reopened)
    }

    @Test func aPendingChangeSaysSaving() {
        #expect(label(pending: true) == "Saving…")
        #expect(label(pending: true, wrote: 0, at: 1, reopened: true) == "Saving…")
    }

    @Test func aWriteIsSavedJustNowForTenSecondsThenSaved() {
        #expect(label(wrote: 0, at: 0) == "Saved just now")
        #expect(label(wrote: 0, at: 9.9) == "Saved just now")
        #expect(label(wrote: 0, at: 10) == "Saved")
        #expect(label(wrote: 0, at: 600) == "Saved")
    }

    @Test func anEntryReopenedAsDoneSaysSoUntilItIsChanged() {
        #expect(label(reopened: true) == "Reopened · saved")
        #expect(label(wrote: 0, at: 3, reopened: true) == "Saved just now")
    }

    @Test func aDraftWithNothingWrittenYetSaysSaved() {
        #expect(label() == "Saved")
    }

    @Test func aRefusedWriteIsNotCalledSaved() {
        #expect(label(failed: true, wrote: 0, at: 1) == "Couldn’t save")
    }
}
