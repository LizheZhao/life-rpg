import LifeRPGCore
import SwiftData
import SwiftUI

@main struct LifeRPGApp: App {
    let container: ModelContainer
    let seedStatus: String

    init() {
        do {
            container = try ModelContainer(for: Schema(LifeRPGSchema.models))
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        seedStatus = Self.seed(container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(seedStatus: seedStatus)
        }
        .modelContainer(container)
    }

    /// Seeds empty tables from the CSVs bundled from `doc/` (via symlinks in `LifeRPG/Seed/`).
    /// After the first launch the DB is the user's copy and this is a no-op.
    @MainActor
    private static func seed(_ context: ModelContext) -> String {
        do {
            let result = try SeedImporter.seedIfEmpty(context,
                                                      sideQuestsCSV: try bundledCSV("side_quests"),
                                                      routinesCSV: try bundledCSV("routine_quests"))
            return "Seeded \(result.questTemplates) quests, \(result.routineTasks) routines"
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
