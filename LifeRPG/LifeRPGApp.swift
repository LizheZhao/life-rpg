import LifeRPGCore
import SwiftData
import SwiftUI

@main struct LifeRPGApp: App {
    private let container: ModelContainer?
    private let startupError: Error?
    private let seedStatus: String

    init() {
        LRFonts.register()
        switch AppStore.opened {
        case .success(let container):
            self.container = container
            startupError = nil
            seedStatus = Self.seed(container.mainContext)
            JournalLaunchMigration.runOnce(container.mainContext)
        case .failure(let error):
            // Never delete or rebuild the store here: the file is the only copy of the history.
            container = nil
            startupError = error
            seedStatus = ""
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootView(seedStatus: seedStatus)
                    .modelContainer(container)
            } else if let startupError {
                StartupErrorView(error: startupError)
            }
        }
    }

    /// Starts an empty library from the starter library bundled from `doc/starter_library.json`
    /// (via a symlink in `LifeRPG/Seed/`), once. From then on the library in the store is the
    /// truth: a row the user renamed or deleted stays that way, and a row added to the file later
    /// does not arrive by itself.
    @MainActor
    private static func seed(_ context: ModelContext) -> String {
        do {
            let result = try StarterLibrary.install(try StarterLibraryFile.data(), into: context)
            // The opening float, once ever. Without it coins mean nothing for the first week:
            // nothing can be spent, so nothing has a price.
            let granted = try Economy.grantStartingBalanceIfNeeded(context, dayKey: Date().dayKey)
            let grant = granted.map { " · granted \($0.points) coins" } ?? ""
            return "Inserted \(result.questTemplates) quests, \(result.routineTasks) routines\(grant)"
        } catch {
            return "Seed failed: \(error)"
        }
    }
}
