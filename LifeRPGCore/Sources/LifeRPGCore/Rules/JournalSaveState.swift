import Foundation

/// What the editor's header says about saving. A pure function of four facts the editor keeps, so
/// the four labels of the spec cannot drift from when they are shown.
public enum JournalSaveState {
    /// How long "Saved just now" stays after a write.
    public static let justNowSeconds: TimeInterval = 10

    /// - `pending`: a change is waiting for the debounce, or a write is in flight.
    /// - `failed`: the last write was refused by the store.
    /// - `lastWriteAt`: when a change was last written, nil when none was this session.
    /// - `reopenedDone`: the entry was already done when it was opened and has not been changed
    ///   since; the first change replaces the label with the ordinary ones.
    public static func label(pending: Bool, failed: Bool = false, lastWriteAt: Date?, now: Date,
                             reopenedDone: Bool) -> String {
        if failed { return "Couldn\u{2019}t save" }
        if pending { return "Saving\u{2026}" }
        if let lastWriteAt, now.timeIntervalSince(lastWriteAt) < justNowSeconds { return "Saved just now" }
        return reopenedDone ? "Reopened \u{00B7} saved" : "Saved"
    }
}
