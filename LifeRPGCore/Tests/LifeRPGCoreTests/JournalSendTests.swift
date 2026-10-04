import Foundation
import Testing
@testable import LifeRPGCore

struct JournalSendTests {
    private let zone = TimeZone(identifier: "America/Los_Angeles")!

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var parts = DateComponents()
        parts.year = year; parts.month = month; parts.day = day; parts.hour = hour; parts.minute = minute
        return LifeCalendar.gregorian(zone).date(from: parts)!
    }

    private func turn(_ index: Int, q: String, a: String, day: String = "2026-10-03") -> JournalTurn {
        let t = JournalTurn()
        t.dayKey = day; t.index = index; t.kind = .opening; t.questionText = q; t.answer = a; t.outcome = .answered
        return t
    }

    private let composed = "Journal 2026-10-03\n\nWhat from today do you want to remember?\nThe rain."
    private var turns: [JournalTurn] { [turn(0, q: "What from today do you want to remember?", a: "The rain.")] }

    // MARK: the day that has just ended

    @Test func justBeforeFiveTheAppDayHasNotEndedYet() {
        // 04:59 on Oct 5 is still Oct 4's evening, so the day that has just ended is Oct 3.
        #expect(JournalSend.finishedDayKey(now: at(2026, 10, 5, 4, 59), timeZone: zone) == "2026-10-03")
    }

    @Test func atFiveTheDayBeforeHasEnded() {
        #expect(JournalSend.finishedDayKey(now: at(2026, 10, 5, 5, 0), timeZone: zone) == "2026-10-04")
    }

    @Test func atMidnightTheAppDayIsStillTheOldOne() {
        #expect(JournalSend.finishedDayKey(now: at(2026, 10, 5, 0, 0), timeZone: zone) == "2026-10-03")
    }

    @Test func theFinishedDayCrossesAMonthEnd() {
        #expect(JournalSend.finishedDayKey(now: at(2026, 11, 1, 5, 0), timeZone: zone) == "2026-10-31")
        #expect(JournalSend.finishedDayKey(now: at(2026, 11, 1, 4, 59), timeZone: zone) == "2026-10-30")
        #expect(JournalSend.finishedDayKey(now: at(2027, 1, 1, 5, 0), timeZone: zone) == "2026-12-31")
    }

    @Test func theFinishedDayFollowsTheGivenTimeZone() {
        let moment = at(2026, 10, 5, 5, 0)
        // 05:00 in Los Angeles is 02:00 in Honolulu, still the night of the day before there.
        let honolulu = TimeZone(identifier: "Pacific/Honolulu")!
        #expect(JournalSend.finishedDayKey(now: moment, timeZone: zone) == "2026-10-04")
        #expect(JournalSend.finishedDayKey(now: moment, timeZone: honolulu) == "2026-10-03")
    }

    // MARK: what goes to Apple Journal

    @Test func anUnsentDayGivesItsComposedText() {
        #expect(JournalSend.textToSend(turns: turns, language: .en, lastSentFingerprint: nil) == composed)
    }

    @Test func aDayAlreadySentGivesNothingSoARepeatedRunCannotDuplicate() {
        let sent = JournalSend.fingerprint(of: composed)
        #expect(JournalSend.textToSend(turns: turns, language: .en, lastSentFingerprint: sent) == "")
    }

    @Test func aDayWithNothingWrittenGivesNothing() {
        #expect(JournalSend.textToSend(turns: [], language: .en, lastSentFingerprint: nil) == "")
        let skipped = turn(0, q: "Q", a: "")
        skipped.outcome = .skipped
        #expect(JournalSend.textToSend(turns: [skipped], language: .en, lastSentFingerprint: nil) == "")
    }

    @Test func aBlankAnswerGivesNothing() {
        #expect(JournalSend.textToSend(turns: [turn(0, q: "Q", a: " \n\t")], language: .en,
                                       lastSentFingerprint: nil) == "")
    }

    /// The rule only says "is this text new". Whether the app ever sends it again is its decision.
    @Test func aTextEditedAfterItWasSentIsNewAgain() {
        let sent = JournalSend.fingerprint(of: composed)
        let edited = [turn(0, q: "What from today do you want to remember?", a: "The rain, and the walk.")]
        #expect(JournalSend.textToSend(turns: edited, language: .en, lastSentFingerprint: sent)
                == "Journal 2026-10-03\n\nWhat from today do you want to remember?\nThe rain, and the walk.")
    }

    @Test func theTextFollowsTheLanguage() {
        #expect(JournalSend.textToSend(turns: turns, language: .zhHans, lastSentFingerprint: nil)
                .hasPrefix("日记 2026-10-03"))
    }

    // MARK: the fingerprint

    /// The published FNV-1a 64 test vectors, so the hash can not drift from the algorithm.
    @Test func theFingerprintIsFNV1a64InHex() {
        #expect(JournalSend.fingerprint(of: "") == "cbf29ce484222325")
        #expect(JournalSend.fingerprint(of: "a") == "af63dc4c8601ec8c")
        #expect(JournalSend.fingerprint(of: "foobar") == "85944171f73967e8")
    }

    @Test func theFingerprintIsOverUTF8AndAlwaysSixteenDigits() {
        #expect(JournalSend.fingerprint(of: "今天").count == 16)
        #expect(JournalSend.fingerprint(of: "今天") == JournalSend.fingerprint(of: "今天"))
        #expect(JournalSend.fingerprint(of: "今天") != JournalSend.fingerprint(of: "今日"))
    }
}
