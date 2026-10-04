import Foundation

/// When to run the user's Shortcut. The Shortcut can only create an Apple Journal entry, never
/// change one, so running it again for a text that is already there would duplicate it.
public enum JournalSend {
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

    /// FNV-1a 64 over the UTF-8 bytes, as 16 hex digits. Stored between launches, so it can not be
    /// `hashValue`, which Swift seeds per process.
    public static func fingerprint(of text: String) -> String {
        let hash = text.utf8.reduce(0xcbf2_9ce4_8422_2325 as UInt64) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}
