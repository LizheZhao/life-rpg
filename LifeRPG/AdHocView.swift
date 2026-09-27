import LifeRPGCore
import SwiftData
import SwiftUI

/// Adding a routine for the day (`PLAN.md` §3), three ways:
/// - from a random slot's "Replace" swipe action, in place of that slot (`AdHoc.replace`);
/// - from a routine's "Replace" swipe action, in place of that routine, for something at least as
///   heavy (`AdHoc.replaceRoutine`);
/// - from the today page's +, on top of the day, replacing nothing (`AdHoc.add`).
/// Either way: pick the routine from the library or write one, confirm. Which routines qualify
/// and what a custom task is worth are `AdHoc`'s rules — this only renders them.
struct AdHocView: View {
    enum Target {
        case add
        case slot(DailyQuest)
        case routine(RoutineOccurrence, flexible: Bool)
    }

    let today: String
    let tier: Tier
    let target: Target

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
    /// An occurrence already on today's page, about to be marked done from here instead of retyped.
    @State private var markingDone: RoutineOccurrence?

    private var slot: DailyQuest? {
        if case .slot(let q) = target { q } else { nil }
    }
    private var replacedRoutine: RoutineOccurrence? {
        if case .routine(let o, _) = target { o } else { nil }
    }
    private var isAdding: Bool {
        if case .add = target { true } else { false }
    }
    /// Replacing a routine: nothing lighter than what it is worth.
    private var minimumBase: Int { replacedRoutine.map(AdHoc.minimumBase(replacing:)) ?? 0 }
    private var difficulties: [Difficulty] {
        replacedRoutine.map(AdHoc.customDifficulties(replacing:)) ?? [.easy, .medium, .hard]
    }

    private var candidates: [RoutineTask] {
        AdHoc.libraryCandidates(routines, occurrences: occurrences, on: today)
            .filter { $0.basePoints >= minimumBase }
    }
    private var chosenRoutine: RoutineTask? { candidates.first { $0.id == routineID } }

    /// Routines `candidates` leaves out because they are already on today's page — listed anyway,
    /// with where they are, so the library never looks like it is missing one.
    private var onPage: [(routine: RoutineTask, occurrence: RoutineOccurrence)] {
        let downgrades = Degrade.versionIDs(in: routines)
        return routines.filter { $0.isActive && !downgrades.contains($0.id) }
            .sorted { $0.text < $1.text }
            .compactMap { r in
                AdHoc.onPageOccurrence(for: r, occurrences: occurrences, on: today).map { (r, $0) }
            }
    }

    /// Library routines close to what is being typed as a custom task.
    private var similar: [RoutineTask] { AdHoc.similarRoutines(to: text, in: routines) }
    private var slotText: String {
        switch target {
        case .slot(let slot): slot.isTrivialGroup ? slot.trivialGroup.joined(separator: " · ") : slot.textSnapshot
        case .routine(let o, _): o.displayText
        case .add: ""
        }
    }

    private var source: AdHoc.Source? {
        switch tab {
        case .library:
            return chosenRoutine.map { .routine($0) }
        case .custom:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || !difficulties.contains(difficulty) ? nil
                : .custom(text: trimmed, difficulty: difficulty)
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
                if let o = replacedRoutine {
                    Section {
                        HStack {
                            Text("R").font(.caption.bold()).frame(minWidth: 32)
                            Text(slotText).strikethrough().foregroundStyle(.secondary)
                            Spacer()
                            Text("\(minimumBase)").monospacedDigit().foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Replaces")
                    } footer: {
                        Text(o.dueDayKey < today
                             ? "Free, for something worth at least \(minimumBase). It stops being charged; deductions already made stay. The new one takes its place in the overdue count — it doesn't start a fresh round."
                             : "Free, for something worth at least \(minimumBase). The new one takes its place: it gates today's clear and loses points each day it stays undone.")
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
                    if isAdding {
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
                    Button(isAdding ? "Add" : "Replace") { confirming = true }
                        .disabled(source == nil)
                }
            }
            .alert(isAdding ? "Add for today?" : "Replace it?", isPresented: $confirming) {
                Button(isAdding ? "Add" : "Replace") { commit() }
                Button("Cancel", role: .cancel) {}
            } message: {
                if isAdding {
                    Text("\(sourceText)\n\nThis is final — it stays on today's page.")
                } else {
                    Text("\(slotText) → \(sourceText)\n\nThis is final — it can't be brought back.")
                }
            }
            .onAppear {
                if !difficulties.contains(difficulty), let first = difficulties.first { difficulty = first }
            }
            .alert("Mark as done?",
                   isPresented: Binding(get: { markingDone != nil }, set: { if !$0 { markingDone = nil } }),
                   presenting: markingDone) { o in
                Button("Complete") { markDone(o) }
                Button("Cancel", role: .cancel) {}
            } message: { o in
                Text("\(o.displayText)\n\nThe one already on today's page — it counts for that routine as usual. This is final — completion cannot be undone.")
            }
        }
    }

    @ViewBuilder private var librarySection: some View {
        Section {
            if candidates.isEmpty {
                Text(minimumBase > 0
                     ? "No routine that isn't already on today's page is worth \(minimumBase) or more."
                     : "Every active routine is already on today's page.").foregroundStyle(.secondary)
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
        if !onPage.isEmpty {
            Section {
                ForEach(onPage, id: \.occurrence.id) { entry in onPageRow(entry.routine, entry.occurrence) }
            } header: {
                Text("Already on today's page")
            } footer: {
                Text(isAdding ? "Did one of these? Mark it done here — adding it again wouldn't count for the routine."
                              : "These are already on today's page, so they can't be picked here.")
            }
        }
    }

    /// One routine already on the page: where it is, and — when adding — a way to mark it done.
    private func onPageRow(_ r: RoutineTask, _ o: RoutineOccurrence) -> some View {
        let pays = Completion.routinePayout(o, flexible: r.flexibleWithinWeek, on: today, tier: tier)
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(o.displayText)
                Text(whereNote(o, flexible: r.flexibleWithinWeek)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let points = o.awardedPoints {
                Text("+\(points)").monospacedDigit().foregroundStyle(.green)
            } else if isAdding, let pays, Schedule.isOpen(o) {
                Button("Done · \(pays)") { markingDone = o }.buttonStyle(.bordered)
            }
        }
    }

    private func whereNote(_ o: RoutineOccurrence, flexible: Bool) -> String {
        if o.completedDayKey != nil { return "Done today" }
        if o.dueDayKey == today { return "Due today" }
        return flexible ? "Open since \(o.dueDayKey) · any day this week"
                        : "Overdue since \(o.dueDayKey)"
    }

    @ViewBuilder private var customSection: some View {
        Section {
            TextField("What needs doing", text: $text)
            Picker("Difficulty", selection: $difficulty) {
                ForEach(difficulties, id: \.self) { d in
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
        if !similar.isEmpty {
            Section {
                ForEach(similar) { r in similarRow(r) }
            } header: {
                Text("Similar in your library")
            } footer: {
                Text("A custom task counts toward no routine's weekly target. If it's one of these, use that instead.")
            }
        }
    }

    /// A library routine close to the custom text: on the page → mark that one done; otherwise →
    /// switch to the library tab with it selected.
    @ViewBuilder private func similarRow(_ r: RoutineTask) -> some View {
        if let o = AdHoc.onPageOccurrence(for: r, occurrences: occurrences, on: today) {
            onPageRow(r, o)
        } else if candidates.contains(where: { $0.id == r.id }) {
            Button {
                routineID = r.id
                tab = .library
            } label: {
                HStack {
                    Text(r.text)
                    Spacer()
                    Text("Use this").font(.caption).foregroundStyle(.tint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            // Replacing a routine and too light to stand in for it.
            HStack {
                Text(r.text).foregroundStyle(.secondary)
                Spacer()
                Text("worth \(r.basePoints)").font(.caption).foregroundStyle(.secondary)
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

    private func markDone(_ o: RoutineOccurrence) {
        do {
            try Completion.completeRoutine(o, on: today, tier: tier, in: context)
            dismiss()
        } catch {
            self.error = "\(error)"
        }
        markingDone = nil
    }

    private func commit() {
        guard let source else { return }
        do {
            switch target {
            case .slot(let slot): try AdHoc.replace(slot, with: source, in: context)
            case .routine(let o, let flexible):
                try AdHoc.replaceRoutine(o, flexible: flexible, with: source, on: today, in: context)
            case .add: try AdHoc.add(source, on: today, in: context)
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
    return AdHocView(today: Date().dayKey, tier: .normal, target: .slot(quest))
        .modelContainer(for: LifeRPGSchema.models, inMemory: true)
}

/// Swapping the week's epic by hand (`Epic.replace`): one from the library, or written on the
/// spot. Free — an epic left undone costs nothing either — and it keeps the old one's deadline.
struct EpicReplaceView: View {
    let today: String
    let epic: DailyQuest

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var templates: [QuestTemplate]

    private enum Tab: Hashable { case library, custom }
    @State private var tab: Tab = .library
    @State private var templateID: UUID?
    @State private var text = ""
    @State private var confirming = false
    @State private var error: String?

    private var candidates: [QuestTemplate] { Epic.replaceCandidates(templates, replacing: epic) }
    private var pick: Epic.Pick? {
        switch tab {
        case .library:
            return candidates.first { $0.id == templateID }.map { .template($0) }
        case .custom:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .custom(text: trimmed)
        }
    }
    private var pickText: String {
        switch pick {
        case .template(let t): t.text
        case .custom(let t): t
        case nil: ""
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(epic.textSnapshot).strikethrough().foregroundStyle(.secondary)
                } header: {
                    Text("Replaces")
                } footer: {
                    Text("Free. The new epic keeps the deadline (\(Epic.lastDayKey(of: epic) ?? "Sunday")) and pays an ordinary epic roll, \(Difficulty.epic.range.lowerBound)–\(Difficulty.epic.range.upperBound).")
                }
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
                case .library:
                    Section("Epic") {
                        if candidates.isEmpty {
                            Text("No other epic in the library.").foregroundStyle(.secondary)
                        }
                        ForEach(candidates) { t in
                            Button { templateID = t.id } label: {
                                HStack {
                                    Text(t.text)
                                    Spacer()
                                    if templateID == t.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                case .custom:
                    Section("Epic") {
                        TextField("This week's big thing", text: $text)
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Replace the epic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Replace") { confirming = true }.disabled(pick == nil)
                }
            }
            .alert("Replace the epic?", isPresented: $confirming) {
                Button("Replace") { commit() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(epic.textSnapshot) → \(pickText)\n\nThis is final — the old epic can't be brought back.")
            }
        }
    }

    private func commit() {
        guard let pick else { return }
        do {
            try Epic.replace(epic, with: pick, on: today, in: context)
            dismiss()
        } catch {
            self.error = "\(error)"
        }
    }
}
