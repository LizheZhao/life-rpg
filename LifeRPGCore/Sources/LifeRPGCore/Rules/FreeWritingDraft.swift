import Foundation

/// What the free-writing page holds between keystrokes: the words, the active writing time
/// (`JournalWritingClock`) and what the store already has. Pure, so the page can keep it in
/// memory and touch the store only when `hasUnsavedChanges` says there is something to write.
public struct FreeWritingDraft: Equatable, Sendable {
    public private(set) var text: String
    public private(set) var writingSeconds: Int
    /// The last keystroke of this session. Nil at the start, so the hours between two sessions are
    /// not writing time.
    private var lastActivity: Date?
    private var savedText: String
    private var savedSeconds: Int

    /// A draft that starts equal to what is stored: nothing to save yet.
    public init(text: String = "", writingSeconds: Int = 0) {
        self.text = text
        self.writingSeconds = writingSeconds
        savedText = text
        savedSeconds = writingSeconds
    }

    public var wordCount: Int { JournalWords.count(text) }

    public var hasUnsavedChanges: Bool { text != savedText || writingSeconds != savedSeconds }

    /// The page now reads `newText`. A change counts as a keystroke at `now`; the same text (a
    /// cursor move reported by the editor) is nothing.
    public mutating func edit(to newText: String, at now: Date) {
        guard newText != text else { return }
        let next = JournalWritingClock.adding(activityAt: now, to: writingSeconds, lastActivity: lastActivity)
        writingSeconds = next.total
        lastActivity = next.lastActivity
        text = newText
    }

    /// Tapping a starter: the phrase goes in as `JournalStarter.insert` says, and counts as typing.
    public mutating func insert(_ starter: JournalStarter, at now: Date) {
        edit(to: starter.insert(into: text), at: now)
    }

    /// The store now holds what the draft held when it was saved.
    public mutating func markSaved() {
        savedText = text
        savedSeconds = writingSeconds
    }

    /// The store holds `text` and `writingSeconds` (written by another screen); the draft starts over
    /// from them. The session's clock is not carried over.
    public mutating func reset(text: String, writingSeconds: Int) {
        self = FreeWritingDraft(text: text, writingSeconds: writingSeconds)
    }
}
