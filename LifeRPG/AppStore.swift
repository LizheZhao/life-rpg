import LifeRPGCore
import SwiftData

/// The one `ModelContainer` of the process. The app scene and App Intents run in the same process
/// and must read the same store, so it is opened once here instead of privately in `LifeRPGApp`.
///
/// A failure is kept, not retried and never repaired: the store file is the only copy of the
/// history, so nothing here deletes or rebuilds it, and the app shows `StartupErrorView` instead.
@MainActor
enum AppStore {
    static let opened = Result {
        try ModelContainer(for: LifeRPGSchema.current, migrationPlan: LifeRPGMigrationPlan.self)
    }
}
