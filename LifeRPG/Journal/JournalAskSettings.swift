import Foundation

/// The Settings switch "Send my writing with the question request". The writing is only ever read
/// when the pill is tapped, and the editor reads this switch at that moment.
enum JournalAskSettings {
    static let sendWritingKey = "journalSendWriting"
    static let sendWritingDefault = true

    static let sendWritingCaption = "On, the question request includes what you have written in this entry. Off, it includes only today's quests and the questions already in the entry. The writing is only ever used when you tap the button."

    static func includeWriting(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: sendWritingKey) as? Bool ?? sendWritingDefault
    }
}
