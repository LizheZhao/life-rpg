import LifeRPGCore
import Observation
import SwiftUI

/// What the user's Shortcut last reported, for the journal pages to show, and the one place the
/// app runs it from. The links are Core's (`JournalShortcutLink`) and so is the decision of when
/// to run (`JournalSend`); this carries the answer from `onOpenURL` back to the screen that asked,
/// and remembers what was sent so the same day is not sent twice. Nothing here can lose the
/// journal: the turns are in the store before the Shortcut is run.
@MainActor @Observable
final class JournalShortcutStatus {
    var outcome: JournalShortcutLink.Outcome?

    /// The text the running Shortcut will read, kept until it answers: `.saved` is what makes it
    /// "sent". Not observed: no screen draws it.
    @ObservationIgnored private var pending: (dayKey: String, fingerprint: String)?

    func receive(_ url: URL) {
        guard let outcome = JournalShortcutLink.outcome(of: url) else { return }
        self.outcome = outcome
        if outcome == .saved, let pending {
            UserDefaults.standard.set(pending.fingerprint, forKey: JournalSend.sentKey(dayKey: pending.dayKey))
        }
        pending = nil
    }

    var message: String? {
        switch outcome {
        case .saved: "Saved to Journal."
        case .cancelled: "The Shortcut was cancelled. Your words are still here."
        case .failed: "The Shortcut could not run. Your words are still here, and you can share them instead."
        case nil: nil
        }
    }

    /// What `JournalSend` says to do with `text` for `dayKey`, given the Shortcut named in Settings.
    func plan(dayKey: String, text: String, shortcutName: String) -> JournalSend.Plan {
        JournalSend.plan(shortcutConfigured: JournalShortcutLink.runURL(shortcutName: shortcutName) != nil,
                         text: text,
                         lastSentFingerprint: UserDefaults.standard.string(forKey: JournalSend.sentKey(dayKey: dayKey)))
    }

    /// Runs the Shortcut for `text`. The Shortcut asks the app for the words
    /// (`GetTodaysJournalTextIntent`); only the fingerprint is kept, to know later what was sent.
    func run(dayKey: String, text: String, shortcutName: String, openURL: OpenURLAction) {
        guard let url = JournalShortcutLink.runURL(shortcutName: shortcutName) else { return }
        outcome = nil
        pending = (dayKey, JournalSend.fingerprint(of: text))
        openURL(url) { [self] accepted in
            if !accepted {
                pending = nil
                outcome = .failed
            }
        }
    }
}

extension JournalShortcutLink {
    /// `@AppStorage` key of the Shortcut's name. Empty means no automatic run.
    static let nameKey = "journalShortcutName"
}
