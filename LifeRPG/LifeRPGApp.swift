import LifeRPGCore
import SwiftData
import SwiftUI

@main struct LifeRPGApp: App {
    private let container: ModelContainer?
    private let startupError: Error?
    private let seedStatus: String

    init() {
        do {
            let container = try ModelContainer(for: LifeRPGSchema.current,
                                               migrationPlan: LifeRPGMigrationPlan.self)
            self.container = container
            startupError = nil
            seedStatus = Self.seed(container.mainContext)
        } catch {
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

    /// Additive merge from the CSVs bundled from `doc/` (via symlinks in `LifeRPG/Seed/`):
    /// new rows are inserted, existing ones are left alone.
    @MainActor
    private static func seed(_ context: ModelContext) -> String {
        do {
            let result = try SeedImporter.mergeSeeds(context,
                                                     sideQuestsCSV: try bundledCSV("side_quests"),
                                                     routinesCSV: try bundledCSV("routine_quests"))
            // The opening float, once ever. Without it coins mean nothing for the first week:
            // nothing can be spent, so nothing has a price.
            let granted = try Economy.grantStartingBalanceIfNeeded(context, dayKey: Date().dayKey)
            let grant = granted.map { " · granted \($0.points) coins" } ?? ""
            return "Inserted \(result.questTemplates) quests, \(result.routineTasks) routines\(grant)"
        } catch {
            return "Seed failed: \(error)"
        }
    }

    private static func bundledCSV(_ name: String) throws -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "csv") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).csv"])
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
