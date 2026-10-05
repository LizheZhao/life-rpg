import Foundation
import LifeRPGCore

/// The clock the journal's views hand to Core. The simulator's Debug page can force the hour
/// ("evening" is 21:00, "daytime" and "cleared" are 12:00) so both the day and the night wording
/// can be seen at any time; on a device the timing is always "" and this is `Date()`.
enum JournalClock {
    static let timingKey = "debugJournalTiming"

    static var timing: String {
        #if targetEnvironment(simulator)
        UserDefaults.standard.string(forKey: timingKey) ?? ""
        #else
        ""
        #endif
    }

    static func now(_ real: Date = Date(), timing: String = timing) -> Date {
        func at(_ hour: Int) -> Date {
            LifeCalendar.gregorian().date(bySettingHour: hour, minute: 0, second: 0, of: real) ?? real
        }
        switch timing {
        case "evening": return at(21)
        case "daytime", "cleared": return at(12)
        default: return real
        }
    }

    static func allCleared(_ real: Bool, timing: String = timing) -> Bool {
        switch timing {
        case "daytime": false
        case "cleared": true
        default: real
        }
    }
}
