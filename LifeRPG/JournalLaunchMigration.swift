import Foundation
import LifeRPGCore
import SwiftData

/// Copies the old turn-based journal into entries, once. The flag matters: `JournalMigration` makes
/// an entry for every day that has turns and no entry, and a day the user later clears has no
/// entry either, so running it on every launch would bring a cleared day back.
enum JournalLaunchMigration {
    static let flagKey = "journalTurnsMigrated"

    /// Runs the migration when the flag is unset and sets it once the context is saved. A failure
    /// leaves the flag unset, so the next launch tries again; it never touches a turn.
    @MainActor
    @discardableResult
    static func runOnce(_ context: ModelContext, defaults: UserDefaults = .standard) -> Int? {
        guard !defaults.bool(forKey: flagKey) else { return nil }
        do {
            let created = try JournalMigration.migrateTurns(in: context)
            try context.save()
            defaults.set(true, forKey: flagKey)
            return created
        } catch {
            return nil
        }
    }
}
