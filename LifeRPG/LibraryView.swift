import LifeRPGCore
import SwiftData
import SwiftUI

/// The quest and routine library, for rating and noting things outside the moment of completion
/// (`PLAN.md` §7, "QuestRating / QuestComment"). Ratings and notes are append-only logs: rating
/// again is a new row, and the old ones stay as the record of what you thought then.
///
/// Which rating is "latest" and whose notes are whose are `Feedback`'s rules; this page hands in
/// the rows its queries already hold.
struct LibraryView: View {
    let today: String

    @Query(sort: \QuestTemplate.text) private var templates: [QuestTemplate]
    @Query(sort: \RoutineTask.text) private var routines: [RoutineTask]
    @Query private var ratings: [QuestRating]
    @Query private var comments: [QuestComment]

    @State private var kind: FeedbackTarget = .quest
    @State private var search = ""

    private var latest: [UUID: QuestRating] { Feedback.latestRatings(ratings) }

    private func matches(_ text: String) -> Bool {
        search.isEmpty || text.localizedCaseInsensitiveContains(search)
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Library", selection: $kind) {
                    Text("Quests").tag(FeedbackTarget.quest)
                    Text("Routines").tag(FeedbackTarget.routine)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                switch kind {
                case .quest:
                    // Easiest first, the way the today page and the composition table read.
                    ForEach(Difficulty.allCases, id: \.self) { d in
                        let rows = templates.filter { $0.difficulty == d && matches($0.text) }
                        if !rows.isEmpty {
                            Section(d.code) {
                                ForEach(rows) { t in
                                    link(LibraryEntry(template: t))
                                }
                            }
                        }
                    }
                case .routine:
                    Section {
                        ForEach(routines.filter { matches($0.text) }) { r in
                            link(LibraryEntry(routine: r))
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $search)
        }
    }

    private func link(_ entry: LibraryEntry) -> some View {
        NavigationLink {
            LibraryDetailView(entry: entry, today: today)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.text).foregroundStyle(entry.isActive ? .primary : .secondary)
                    let notes = Feedback.comments(comments, for: entry.id).count
                    if !entry.isActive || notes > 0 {
                        Text([entry.isActive ? nil : "inactive",
                              notes > 0 ? "\(notes) note\(notes == 1 ? "" : "s")" : nil]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let r = latest[entry.id] { RatingBadge(value: r.rating) }
            }
        }
    }
}

/// One library row, whichever table it came from. The text is what a new rating or note
/// snapshots, like every other history row.
private struct LibraryEntry {
    let id: UUID
    let target: FeedbackTarget
    let text: String
    let code: String
    let isActive: Bool

    init(template t: QuestTemplate) {
        id = t.id; target = .quest; text = t.text; code = t.difficulty.code; isActive = t.isActive
    }

    init(routine r: RoutineTask) {
        id = r.id; target = .routine; text = r.text; code = "R"; isActive = r.isActive
    }
}

/// Rate it again, or leave a note. Both only ever append.
private struct LibraryDetailView: View {
    let entry: LibraryEntry
    let today: String

    @Environment(\.modelContext) private var context
    @Query private var ratings: [QuestRating]
    @Query private var comments: [QuestComment]

    @State private var note = ""
    @State private var error: String?

    private var history: [QuestRating] { Feedback.ratings(ratings, for: entry.id) }
    private var notes: [QuestComment] { Feedback.comments(comments, for: entry.id) }

    var body: some View {
        List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.code).font(.caption.bold()).frame(minWidth: 36)
                    Text(entry.text)
                }
                if !entry.isActive {
                    Text("Inactive — not drawn any more").font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                HStack(spacing: 10) {
                    ForEach(PointsRollView.scale, id: \.value) { step in
                        Button { rate(step.value) } label: {
                            Image(systemName: step.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(history.first?.rating == step.value ? AnyShapeStyle(.tint)
                                                                               : AnyShapeStyle(.quaternary),
                                            in: RoundedRectangle(cornerRadius: 9))
                                .foregroundStyle(history.first?.rating == step.value ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(step.label)
                    }
                }
            } header: {
                Text("How do you feel about it now?")
            } footer: {
                if let last = history.first {
                    Text("Latest: \(label(last.rating)), \(last.dayKey). Rating again adds a new entry; the old ones stay.")
                } else {
                    Text("Not rated yet.")
                }
            }

            Section("Add a note") {
                TextField("What worked, what didn't", text: $note, axis: .vertical)
                Button("Add note") { addNote() }
                    .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }

            if !notes.isEmpty {
                Section("Notes") {
                    ForEach(notes) { c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.comment)
                            Text(c.dayKey).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !history.isEmpty {
                Section("Ratings") {
                    ForEach(history) { r in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(label(r.rating))
                                Text(r.questID == nil ? r.dayKey : "\(r.dayKey) · right after doing it")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            RatingBadge(value: r.rating)
                        }
                    }
                }
            }
        }
        .navigationTitle(entry.target == .quest ? "Quest" : "Routine")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func label(_ value: Int) -> String {
        PointsRollView.scale.first { $0.value == value }?.label ?? "\(value)"
    }

    private func rate(_ value: Int) {
        Feedback.rate(context, target: entry.target, id: entry.id, text: entry.text,
                      rating: value, dayKey: today)
        try? Affinity.sync(context)           // the next draw already weighs it
        save()
    }

    private func addNote() {
        Feedback.comment(context, target: entry.target, id: entry.id, text: entry.text,
                         comment: note.trimmingCharacters(in: .whitespacesAndNewlines), dayKey: today)
        if save() { note = "" }
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try context.save()
            error = nil
            return true
        } catch {
            self.error = "\(error)"
            return false
        }
    }
}

/// `+2` green, `-1` red, `0` grey — the same look the day detail uses.
private struct RatingBadge: View {
    let value: Int

    var body: some View {
        Text(value > 0 ? "+\(value)" : "\(value)")
            .font(.caption.weight(.semibold)).monospacedDigit()
            .foregroundStyle(value > 0 ? .green : value < 0 ? .red : .secondary)
    }
}
