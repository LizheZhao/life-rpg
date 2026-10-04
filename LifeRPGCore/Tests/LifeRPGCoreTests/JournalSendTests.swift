import Testing
@testable import LifeRPGCore

struct JournalSendTests {
    private let text = "Journal 2026-09-18\n\nGrateful for rain."

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

    @Test func aTextNeverSentRuns() {
        #expect(JournalSend.shouldRunShortcut(shortcutConfigured: true, text: text, lastSentFingerprint: nil))
    }

    @Test func noShortcutMeansNoRun() {
        #expect(!JournalSend.shouldRunShortcut(shortcutConfigured: false, text: text, lastSentFingerprint: nil))
    }

    @Test func aBlankTextNeverRuns() {
        #expect(!JournalSend.shouldRunShortcut(shortcutConfigured: true, text: "", lastSentFingerprint: nil))
        #expect(!JournalSend.shouldRunShortcut(shortcutConfigured: true, text: " \n\t", lastSentFingerprint: nil))
    }

    @Test func theTextThatWasAlreadySentDoesNotRunAgain() {
        let sent = JournalSend.fingerprint(of: text)
        #expect(!JournalSend.shouldRunShortcut(shortcutConfigured: true, text: text, lastSentFingerprint: sent))
    }

    /// The Shortcut can only create an entry, so a changed text would add a second one. The rule
    /// still says true: the app asks the user before it sends again.
    @Test func aTextChangedSinceItWasSentRuns() {
        let sent = JournalSend.fingerprint(of: text)
        #expect(JournalSend.shouldRunShortcut(shortcutConfigured: true, text: text + " More.", lastSentFingerprint: sent))
    }

    @Test func aPlanRunsAFirstSendAndAsksBeforeASecond() {
        let sent = JournalSend.fingerprint(of: text)
        #expect(JournalSend.plan(shortcutConfigured: true, text: text, lastSentFingerprint: nil) == .run)
        #expect(JournalSend.plan(shortcutConfigured: true, text: text + " More.", lastSentFingerprint: sent)
                == .askBeforeSendingAgain)
        #expect(JournalSend.plan(shortcutConfigured: true, text: text, lastSentFingerprint: sent) == .nothing)
        #expect(JournalSend.plan(shortcutConfigured: false, text: text, lastSentFingerprint: nil) == .nothing)
        #expect(JournalSend.plan(shortcutConfigured: true, text: "", lastSentFingerprint: sent) == .nothing)
    }

    @Test func theSentKeyIsPerDay() {
        #expect(JournalSend.sentKey(dayKey: "2026-09-18") == "journalSent.2026-09-18")
        #expect(JournalSend.sentKey(dayKey: "2026-09-18") != JournalSend.sentKey(dayKey: "2026-09-19"))
    }
}
