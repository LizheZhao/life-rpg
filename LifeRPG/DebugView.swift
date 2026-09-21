import LifeRPGCore
import SwiftData
import SwiftUI

/// Debug page: row counts per table and the data audit. Not part of daily use — it is how a
/// failed seed or an unreadable raw value gets noticed at all.
struct DebugView: View {
    let seedStatus: String

    @Environment(\.modelContext) private var modelContext
    @State private var audit: [StoreAudit.Issue] = []
    @State private var auditError: String?
    @State private var confirmingReset = false
    @State private var resetResult: String?

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
                // The enum getters fall back (`?? .easy`), so an unreadable raw value would
                // otherwise be invisible. Nothing from the CSV can land here — the seed parser
                // rejects it — but a JSON import or an enum rename could.
                Section("Data audit") {
                    if let auditError {
                        Text(auditError).foregroundStyle(.red)
                    } else if audit.isEmpty {
                        Label("No unreadable values", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(audit, id: \.description) { issue in
                            row("\(issue.model).\(issue.field) = '\(issue.value)'", issue.count)
                                .foregroundStyle(.red)
                        }
                    }
                }
                // Deliberately here and not on the today page: `PLAN.md` §3 makes completion
                // final, and a reset button sitting next to the quests would undo that rule in
                // practice whatever the doc says. This is for exercising the payout roll while
                // it is being built, not for changing your mind.
                Section {
                    Button(role: .destructive) { confirmingReset = true } label: {
                        Label("Reopen today", systemImage: "arrow.counterclockwise")
                    }
                    if let resetResult {
                        Text(resetResult).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Testing")
                } footer: {
                    Text("Marks today's quests undone, deletes the ledger entries that paid for them, and removes the hidden quest so it can be revealed again. The same quests come back — only the day's results are undone.")
                }

                Section("Quests by difficulty") {
                    ForEach(Difficulty.allCases, id: \.self) { d in
                        row(d.rawValue, questTemplates.filter { $0.difficulty == d }.count)
                    }
                }
            }
            .navigationTitle("Debug")
            .task {
                do { audit = try StoreAudit.issues(modelContext) }
                catch { auditError = "Audit failed: \(error)" }
            }
            .alert("Reopen today?", isPresented: $confirmingReset) {
                Button("Reopen", role: .destructive) { reopenToday() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Today's completions and the points they paid are deleted. Other days are untouched.")
            }
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

    private func reopenToday() {
        do {
            let result = try DayReset.reopen(modelContext, dayKey: Date().dayKey)
            resetResult = result.description
            audit = try StoreAudit.issues(modelContext)
        } catch {
            resetResult = "Reopen failed: \(error)"
        }
    }
}

#Preview {
    DebugView(seedStatus: "Preview")
        .modelContainer(for: LifeRPGSchema.models, inMemory: true)
}
