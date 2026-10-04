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
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              fingerprint(of: text) != lastSentFingerprint else { return "" }
        return text
    }

    /// FNV-1a 64 over the UTF-8 bytes, as 16 hex digits. Stored between launches, so it can not be
    /// `hashValue`, which Swift seeds per process.
    public static func fingerprint(of text: String) -> String {
        let hash = text.utf8.reduce(0xcbf2_9ce4_8422_2325 as UInt64) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}
