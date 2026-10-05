import Foundation

/// When a day's journal is closed, read from the day's turns alone: the rule the planner follows
/// when it decides to ask nothing more.
public enum JournalProgress {
    /// The closing turn, whether it answers the closing question or is free writing, ends the day.
    /// A free-writing turn that is blank (the page was cleared) has not closed anything.
    public static func isClosed(_ turns: [JournalTurn]) -> Bool {
        turns.contains { $0.kind == .closing && !$0.isBlankFreeWriting }
    }
}
