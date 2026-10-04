import Foundation
import LifeRPGCore
import SwiftData

/// What the app has handed to the user's Shortcut, by day: the fingerprint of the text and when.
/// Kept in `UserDefaults` as one JSON value under `key`, so a view can watch it with `@AppStorage`.
/// Core decides what is new (`JournalSend.textToSend`); this only remembers, and the fingerprint is
/// passed in and out so Core stays free of `UserDefaults`.
enum JournalSentLog {
    struct Entry: Codable, Equatable {
        let fingerprint: String
        let sentAt: Date
    }

    static let key = "journalSentLog"

    static func decode(_ data: Data) -> [String: Entry] {
        (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    static func entries(in defaults: UserDefaults = .standard) -> [String: Entry] {
        decode(defaults.data(forKey: key) ?? Data())
    }

    static func record(dayKey: String, fingerprint: String, at date: Date, in defaults: UserDefaults = .standard) {
        var all = entries(in: defaults)
        all[dayKey] = Entry(fingerprint: fingerprint, sentAt: date)
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: key) }
    }

    /// The most recent hand-over, for the Settings status line.
    static func latest(_ entries: [String: Entry]) -> Entry? {
        entries.values.max { $0.sentAt < $1.sentAt }
    }
}

/// The code path of `GetJournalTextToSendIntent`, apart from the intent itself so the simulator's
/// debug page can run the same thing with a shifted clock.
enum JournalHandOff {
    /// The journal of the day that has just ended as of `now`, or empty when there is nothing new.
    ///
    /// The Shortcut gives no callback, so a non-empty text is marked sent here, when the app hands
    /// it over. If Create Journal Entry then fails, the day stays marked and the user can send it
    /// from the share sheet.
    @MainActor
    static func textToSend(now: Date, in context: ModelContext, defaults: UserDefaults = .standard) throws -> String {
        let dayKey = JournalSend.finishedDayKey(now: now, timeZone: .current)
        let turns = try JournalService.turns(on: dayKey, in: context)
        let language = JournalLanguage.resolve(preferred: Locale.preferredLanguages)
        let text = JournalSend.textToSend(turns: turns, language: language,
                                          lastSentFingerprint: JournalSentLog.entries(in: defaults)[dayKey]?.fingerprint)
        if !text.isEmpty {
            JournalSentLog.record(dayKey: dayKey, fingerprint: JournalSend.fingerprint(of: text), at: now, in: defaults)
        }
        return text
    }
}
