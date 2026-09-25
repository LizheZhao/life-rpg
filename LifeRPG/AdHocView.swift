import LifeRPGCore
import SwiftData
import SwiftUI

/// Adding a routine for the day (`PLAN.md` §3), two ways:
/// - from a random slot's "Replace" swipe action, in place of that slot (`AdHoc.replace`);
/// - from the today page's +, on top of the day, replacing nothing (`AdHoc.add`).
/// Either way: pick the routine from the library or write one, confirm. Which routines qualify
/// and what a custom task is worth are `AdHoc`'s rules — this only renders them.
struct AdHocView: View {
    let today: String
    let tier: Tier
    /// The slot being taken over, or nil when adding on top of the day.
    let slot: DailyQuest?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var occurrences: [RoutineOccurrence]
    @Query private var routines: [RoutineTask]

    private enum Tab: Hashable { case library, custom }
    @State private var tab: Tab = .library
    @State private var routineID: UUID?
    @State private var text = ""
    @State private var difficulty: Difficulty = .easy
    @State private var confirming = false
    @State private var error: String?

    private var candidates: [RoutineTask] {
        AdHoc.libraryCandidates(routines, occurrences: occurrences, on: today)
    }
    private var chosenRoutine: RoutineTask? { candidates.first { $0.id == routineID } }
    private var slotText: String {
        guard let slot else { return "" }
        return slot.isTrivialGroup ? slot.trivialGroup.joined(separator: " · ") : slot.textSnapshot
    }

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
                if let slot {
                    Section {
                        HStack {
                            Text(slot.isTrivialGroup ? "T×3" : slot.slot.code)
                                .font(.caption.bold()).frame(minWidth: 32)
                            Text(slotText).strikethrough().foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Replaces")
                    } footer: {
                        Text("The replaced quest no longer counts toward today's clear. The new routine does — and like any routine, it loses points each day it stays undone.")
                    }
                }

                Section {
                    Picker("Source", selection: $tab) {
                        Text("From library").tag(Tab.library)
                        Text("Custom").tag(Tab.custom)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    if slot == nil {
                        Text("Extra work on top of today. It replaces nothing, doesn't block the hidden quest and costs nothing if left undone — done, it pays like any routine.")
                    }
                }

                switch tab {
                case .library: librarySection
                case .custom: customSection
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
                    Button(slot == nil ? "Add" : "Replace") { confirming = true }
                        .disabled(source == nil)
                }
            }
            .alert(slot == nil ? "Add for today?" : "Replace this slot?", isPresented: $confirming) {
                Button(slot == nil ? "Add" : "Replace") { commit() }
                Button("Cancel", role: .cancel) {}
            } message: {
                if slot == nil {
                    Text("\(sourceText)\n\nThis is final — it stays on today's page.")
                } else {
                    Text("\(slotText) → \(sourceText)\n\nThis is final — the slot can't be brought back.")
                }
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

    private func commit() {
        guard let source else { return }
        do {
            if let slot {
                try AdHoc.replace(slot, with: source, in: context)
            } else {
                try AdHoc.add(source, on: today, in: context)
            }
            dismiss()
        } catch {
            self.error = "\(error)"
        }
    }
}

#Preview {
    let quest = DailyQuest()
    quest.textSnapshot = "Compliment a stranger"
    quest.slot = .medium
    return AdHocView(today: Date().dayKey, tier: .normal, slot: quest)
        .modelContainer(for: LifeRPGSchema.models, inMemory: true)
}
