import Foundation

/// The Settings switch "Send my writing with the question request". The writing is only ever read
/// when the pill is tapped, and the editor reads this switch at that moment.
enum JournalAskSettings {
    static let sendWritingKey = "journalSendWriting"
    static let sendWritingDefault = true

    static let sendWritingCaption = "Lets the question see what you've written so far. Off: it only sees today's quests."

    static func includeWriting(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: sendWritingKey) as? Bool ?? sendWritingDefault
    }
}
