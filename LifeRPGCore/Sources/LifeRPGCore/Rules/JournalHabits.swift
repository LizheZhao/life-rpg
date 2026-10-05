import Foundation

/// Compatibility shim. `JournalHabits` was derived from turns and is gone; only this one constant
/// survives because `JournalTrends.swift` (`usualHour`) still reads it. That file must switch to
/// its own constant, then this file goes.
enum JournalHabits {
    static let minimumTurnsForHour = 5
}
