import Foundation
import Testing
@testable import LifeRPGCore

struct JournalWritingClockTests {
    private let start = Fixtures.date("2026-09-18", hour: 21)

    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    @Test func theFirstKeystrokeAddsNothingAndStartsTheClock() {
        let result = JournalWritingClock.adding(activityAt: at(0), to: 0, lastActivity: nil)
        #expect(result.total == 0)
        #expect(result.lastActivity == at(0))
    }

    @Test func aTenSecondGapCountsInFull() {
        let result = JournalWritingClock.adding(activityAt: at(10), to: 7, lastActivity: at(0))
        #expect(result.total == 17)
        #expect(result.lastActivity == at(10))
    }

    @Test func aFiveMinuteGapCountsAsThirtySeconds() {
        let result = JournalWritingClock.adding(activityAt: at(300), to: 100, lastActivity: at(0))
        #expect(result.total == 130)
        #expect(result.lastActivity == at(300))
    }

    @Test func theCapIsInclusiveAtThirtyAndAnythingOverIsCappedToIt() {
        #expect(JournalWritingClock.maxGapSeconds == 30)
        #expect(JournalWritingClock.adding(activityAt: at(30), to: 0, lastActivity: at(0)).total == 30)
        #expect(JournalWritingClock.adding(activityAt: at(31), to: 0, lastActivity: at(0)).total == 30)
    }

    @Test func aClockSetBackAddsNothingAndRestartsFromNow() {
        let result = JournalWritingClock.adding(activityAt: at(-60), to: 12, lastActivity: at(0))
        #expect(result.total == 12)
        #expect(result.lastActivity == at(-60))
    }

    /// Keystrokes a fifth of a second apart must still add up to the seconds they took.
    @Test func fastTypingAccumulatesWholeSecondsWithoutLosingTheFractions() {
        var total = 0
        var last: Date?
        for step in 0...50 {
            (total, last) = JournalWritingClock.adding(activityAt: at(Double(step) * 0.2), to: total, lastActivity: last)
        }
        #expect(total == 10)
    }

    @Test func aPauseAfterFastTypingStillCapsAtThirty() {
        var total = 0
        var last: Date?
        for step in 0...5 {
            (total, last) = JournalWritingClock.adding(activityAt: at(Double(step)), to: total, lastActivity: last)
        }
        #expect(total == 5)
        (total, last) = JournalWritingClock.adding(activityAt: at(5 + 120), to: total, lastActivity: last)
        #expect(total == 35)
        #expect(last == at(125))
    }
}
