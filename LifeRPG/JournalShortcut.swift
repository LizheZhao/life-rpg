import LifeRPGCore
import Observation
import SwiftUI

/// What the user's Shortcut last reported, for the journal sheet to show. The links are Core's
/// (`JournalShortcutLink`); this only carries the answer from `onOpenURL` to the view that asked.
/// Nothing here can lose the journal: the turns are in the store before the Shortcut is run.
@MainActor @Observable
final class JournalShortcutStatus {
    var outcome: JournalShortcutLink.Outcome?

    func receive(_ url: URL) {
        if let outcome = JournalShortcutLink.outcome(of: url) { self.outcome = outcome }
    }

    var message: String? {
        switch outcome {
        case .saved: "Saved to Journal."
        case .cancelled: "The Shortcut was cancelled. Your words are still here."
        case .failed: "The Shortcut could not run. Your words are still here, and you can share them instead."
        case nil: nil
        }
    }
}

extension JournalShortcutLink {
    /// `@AppStorage` key of the Shortcut's name. Empty means no automatic run.
    static let nameKey = "journalShortcutName"
}
