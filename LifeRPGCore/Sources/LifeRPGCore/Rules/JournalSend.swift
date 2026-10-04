import Foundation

/// When to run the user's Shortcut. The Shortcut can only create an Apple Journal entry, never
/// change one, so running it again for a text that is already there would duplicate it.
public enum JournalSend {
    /// The app day before the current one. At 04:59 on Oct 5 the app day is still Oct 4, so the
    /// finished day is Oct 3; at 05:00 the app day is Oct 5 and the finished day is Oct 4. Today's
    /// own page is not the answer: at the very moment the automation runs, today is already empty.
    public static func finishedDayKey(now: Date, timeZone: TimeZone) -> String {
        let today = now.dayKey(in: timeZone)
        return DayKey.adding(-1, to: today, in: timeZone) ?? today
    }

    /// The composed text of `turns` (one day's), or the empty string when there is nothing to
    /// send: nothing written, or the very text that was last sent. Empty is what lets the
    /// automation run twice without a second entry. A text edited after it was sent comes back
    /// again here; this rule only says whether the text is new, and the app decides whether to ask.
    public static func textToSend(turns: [JournalTurn], language: JournalLanguage,
                                  lastSentFingerprint: String?) -> String {
        let text = JournalComposer.text(turns: turns, language: language)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              fingerprint(of: text) != lastSentFingerprint else { return "" }
        return text
    }

    /// False with no shortcut set, with nothing written, and for the very text that was last sent.
    ///
    /// A text that changed since it was sent is true: this is only "is there something new to
    /// send". The app asks the user before it sends such a text again, knowing it makes a second
    /// entry.
    public static func shouldRunShortcut(shortcutConfigured: Bool, text: String,
                                         lastSentFingerprint: String?) -> Bool {
        guard shortcutConfigured, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return fingerprint(of: text) != lastSentFingerprint
    }

    /// What to do when the user is done with the day's text.
    public enum Plan: Equatable, Sendable {
        /// No Shortcut, nothing written, or this very text is already in Apple Journal.
        case nothing
        /// Never sent, so run it.
        case run
        /// Sent before and changed since: the Shortcut would add a second entry, so ask first.
        case askBeforeSendingAgain
    }

    public static func plan(shortcutConfigured: Bool, text: String, lastSentFingerprint: String?) -> Plan {
        guard shouldRunShortcut(shortcutConfigured: shortcutConfigured, text: text,
                                lastSentFingerprint: lastSentFingerprint) else { return .nothing }
        return lastSentFingerprint == nil ? .run : .askBeforeSendingAgain
    }

    /// Where the fingerprint of what was last sent for `dayKey` is kept between launches.
    public static func sentKey(dayKey: String) -> String { "journalSent.\(dayKey)" }

    /// FNV-1a 64 over the UTF-8 bytes, as 16 hex digits. Stored between launches, so it can not be
    /// `hashValue`, which Swift seeds per process.
    public static func fingerprint(of text: String) -> String {
        let hash = text.utf8.reduce(0xcbf2_9ce4_8422_2325 as UInt64) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}
