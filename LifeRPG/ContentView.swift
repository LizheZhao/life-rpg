import LifeRPGCore
import SwiftData
import SwiftUI

/// Stage 0 debug page: row counts per table, to confirm the seed landed.
struct ContentView: View {
    let seedStatus: String

    @Query private var questTemplates: [QuestTemplate]
    @Query private var routineTasks: [RoutineTask]
    @Query private var dailyQuests: [DailyQuest]
    @Query private var routineOccurrences: [RoutineOccurrence]
    @Query private var rewards: [Reward]
    @Query private var ledgerEntries: [LedgerEntry]
    @Query private var dailyContexts: [DailyContext]

    var body: some View {
        NavigationStack {
            List {
                Section("Seed") {
                    Text(seedStatus)
                }
                Section("Tables") {
                    row("QuestTemplate", questTemplates.count,
                        detail: "\(questTemplates.filter(\.isActive).count) active")
                    row("RoutineTask", routineTasks.count,
                        detail: "\(routineTasks.filter(\.isActive).count) active")
                    row("DailyQuest", dailyQuests.count)
                    row("RoutineOccurrence", routineOccurrences.count)
                    row("Reward", rewards.count)
                    row("LedgerEntry", ledgerEntries.count)
                    row("DailyContext", dailyContexts.count)
                }
                Section("Quests by difficulty") {
                    ForEach(Difficulty.allCases, id: \.self) { d in
                        row(d.rawValue, questTemplates.filter { $0.difficulty == d }.count)
                    }
                }
            }
            .navigationTitle("Life RPG · debug")
        }
    }

    private func row(_ name: String, _ count: Int, detail: String? = nil) -> some View {
        HStack {
            Text(name)
            Spacer()
            if let detail { Text(detail).foregroundStyle(.secondary) }
            Text("\(count)").monospacedDigit()
        }
    }
}

#Preview {
    ContentView(seedStatus: "Preview")
        .modelContainer(for: LifeRPGSchema.models, inMemory: true)
}
