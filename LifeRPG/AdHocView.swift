import LifeRPGCore
import SwiftData
import SwiftUI

/// Adding a routine for the day in place of one random slot (`PLAN.md` §3): pick it from the
/// routine library or write one, choose the slot it takes over, confirm. Which slots and which
/// routines qualify, and what a custom task is worth, are `AdHoc`'s rules — this only renders them.
struct AdHocView: View {
    let today: String
    let tier: Tier

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \DailyQuest.dayKey) private var allQuests: [DailyQuest]
    @Query private var occurrences: [RoutineOccurrence]
    @Query private var routines: [RoutineTask]

    private enum Tab: Hashable { case library, custom }
    @State private var tab: Tab = .library
    @State private var routineID: UUID?
    @State private var text = ""
    @State private var difficulty: Difficulty = .easy
    @State private var slotID: UUID?
    @State private var confirming = false
    @State private var error: String?

    private var candidates: [RoutineTask] {
        AdHoc.libraryCandidates(routines, occurrences: occurrences, on: today)
    }
    private var slots: [DailyQuest] {
        AdHoc.replaceableSlots(allQuests.filter { $0.dayKey == today }, on: today)
    }
    private var chosenRoutine: RoutineTask? { candidates.first { $0.id == routineID } }
    private var chosenSlot: DailyQuest? { slots.first { $0.id == slotID } }

    private var source: AdHoc.Source? {
        switch tab {
        case .library:
            return chosenRoutine.map { .routine($0) }
        case .custom:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .custom(text: trimmed, difficulty: difficulty)
        }
    }
    private var sourceText: String {
        switch source {
        case .routine(let r): r.text
        case .custom(let t, _): t
        case nil: ""
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Source", selection: $tab) {
                        Text("From library").tag(Tab.library)
                        Text("Custom").tag(Tab.custom)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                switch tab {
                case .library: librarySection
                case .custom: customSection
                }

                Section {
                    if slots.isEmpty {
                        Text("Every random slot is done or already replaced.").foregroundStyle(.secondary)
                    }
                    ForEach(slots) { quest in
                        choiceRow(selected: slotID == quest.id) {
                            HStack {
                                Text(quest.isTrivialGroup ? "T×3" : quest.slot.code)
                                    .font(.caption.bold()).frame(minWidth: 32)
                                Text(quest.isTrivialGroup ? quest.trivialGroup.joined(separator: " · ")
                                                          : quest.textSnapshot)
                            }
                        } action: { slotID = quest.id }
                    }
                } header: {
                    Text("Replaces")
                } footer: {
                    Text("The replaced quest no longer counts toward today's clear. The new routine does — and like any routine, it loses points each day it stays undone.")
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add for today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Replace") { confirming = true }
                        .disabled(source == nil || chosenSlot == nil)
                }
            }
            .alert("Replace this slot?", isPresented: $confirming) {
                Button("Replace") { replace() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(chosenSlot?.textSnapshot ?? "") → \(sourceText)\n\nThis is final — the slot can't be brought back.")
            }
        }
    }

    private var librarySection: some View {
        Section {
            if candidates.isEmpty {
                Text("Every active routine is already on today's page.").foregroundStyle(.secondary)
            }
            ForEach(candidates) { r in
                choiceRow(selected: routineID == r.id) {
                    HStack {
                        Text(r.text)
                        Spacer()
                        Text("\(pays(r.basePoints))").monospacedDigit().foregroundStyle(.secondary)
                    }
                } action: { routineID = r.id }
            }
        } header: {
            Text("Routine")
        }
    }

    private var customSection: some View {
        Section {
            TextField("What needs doing", text: $text)
            Picker("Difficulty", selection: $difficulty) {
                ForEach([Difficulty.easy, .medium, .hard], id: \.self) { d in
                    Text(d.code).tag(d)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Task")
        } footer: {
            if let base = AdHoc.basePoints(for: difficulty) {
                Text("Pays \(pays(base)) — the middle of \(difficulty.code)'s range.")
            }
        }
    }

    private func choiceRow(selected: Bool, @ViewBuilder label: () -> some View,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                label()
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// What it pays done today — the same number `Completion.completeRoutine` will pay.
    private func pays(_ base: Int) -> Int {
        Scoring.routinePoints(basePoints: base, tier: tier, late: false)
    }

    private func replace() {
        guard let source, let slot = chosenSlot else { return }
        do {
            try AdHoc.replace(slot, with: source, in: context)
            dismiss()
        } catch {
            self.error = "\(error)"
        }
    }
}

#Preview {
    AdHocView(today: Date().dayKey, tier: .normal)
        .modelContainer(for: LifeRPGSchema.models, inMemory: true)
}
