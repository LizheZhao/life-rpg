import Foundation

/// What goes to Apple Journal, and when. The user's Shortcut can only create an entry, never
/// change or remove one, so a day is sent once, after it has ended, and nothing is sent while the
/// user may still edit it. A nightly Personal Automation at the day boundary asks the app for the
/// day that has just ended (`finishedDayKey`) and the text to send (`textToSend`).
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
        guard fingerprint(of: text) != lastSentFingerprint else { return "" }
        return text
    }

    /// The plain text of the day's entry, or the empty string when there is nothing to send: no
    /// entry, nothing written in it, or the very text that was last sent. The document counterpart
    /// of the turn-based `textToSend`.
    public static func textToSend(entry: JournalEntry?, lastSentFingerprint: String?) -> String {
        guard let text = entry?.document.plainText(), !text.isEmpty,
              fingerprint(of: text) != lastSentFingerprint else { return "" }
        return text
    }

    public enum SentState: Equatable, Sendable {
        case notSent
        /// `text` is what was handed to the Shortcut.
        case sent
        /// A day was handed over and its text is different now. Apple Journal keeps the earlier one.
        case editedSince
    }

    /// Where `text` stands against the fingerprint of what was last handed over for its day, for
    /// the page that reads it back.
    public static func sentState(text: String, lastSentFingerprint: String?) -> SentState {
        guard let lastSentFingerprint else { return .notSent }
        return fingerprint(of: text) == lastSentFingerprint ? .sent : .editedSince
    }

    /// FNV-1a 64 over the UTF-8 bytes, as 16 hex digits. Stored between launches, so it can not be
    /// `hashValue`, which Swift seeds per process.
    public static func fingerprint(of text: String) -> String {
        let hash = text.utf8.reduce(0xcbf2_9ce4_8422_2325 as UInt64) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}
