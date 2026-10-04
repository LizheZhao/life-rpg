import Foundation

/// When the journal is the thing to do: the evening, from `eveningStartHour` until the day rolls
/// over at `LifeCalendar.dayStartHour`, so a late night is still the evening it belongs to.
public enum JournalTiming {
    public static let eveningStartHour = 18

    public static func isEvening(at now: Date, timeZone: TimeZone) -> Bool {
        let hour = LifeCalendar.gregorian(timeZone).component(.hour, from: now)
        return hour >= eveningStartHour || hour < LifeCalendar.dayStartHour
    }
}
