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

    private var questGroups: [(difficulty: Difficulty, rows: [QuestTemplate])] {
        // Easiest first, the way the today page and the composition table read.
        Difficulty.allCases.compactMap { d in
            let rows = templates.filter { $0.difficulty == d && matches($0.text) }
            return rows.isEmpty ? nil : (d, rows)
        }
    }

    private var routineRows: [RoutineTask] { routines.filter { matches($0.text) } }

    private var isEmpty: Bool {
        switch kind {
        case .quest: questGroups.isEmpty
        case .routine: routineRows.isEmpty
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LR.Spacing.sectionGap) {
                PillSegmentedControl(options: [("Quests", FeedbackTarget.quest), ("Routines", FeedbackTarget.routine)],
                                     selection: $kind, accessibilityLabel: "Library")
                switch kind {
                case .quest:
                    ForEach(questGroups, id: \.difficulty) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            header(group.difficulty.rawValue.capitalized, tint: QuestTint(group.difficulty),
                                   count: group.rows.count)
                            ForEach(group.rows) { link(LibraryEntry(template: $0)) }
                        }
                    }
                case .routine:
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(routineRows) { link(LibraryEntry(routine: $0)) }
                    }
                }
                if isEmpty {
                    RecordRowView(title: search.isEmpty ? "Nothing in the library yet" : "Nothing matches \"\(search)\"",
                                  secondary: true) { EmptyView() }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .reservingTabBarSpace()
        .background(LR.Color.canvas.ignoresSafeArea())
        .navigationTitle("Library")
        .searchable(text: $search)
    }

    /// A section header in Settings' own style, with the tier's colour as a dot and a hand count.
    private func header(_ title: String, tint: QuestTint, count: Int) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Circle().fill(tint.color).frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(title).lr(.heading).foregroundStyle(LR.Color.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Text("\(count)").lr(.hand).monospacedDigit().foregroundStyle(LR.Color.accent)
        }
        .padding(.top, 6)
    }

    private func link(_ entry: LibraryEntry) -> some View {
        let notes = Feedback.comments(comments, for: entry.id).count
        let rating = latest[entry.id]?.rating
        return NavigationLink {
            LibraryDetailView(entry: entry, today: today)
        } label: {
            LibraryRow(entry: entry, notes: notes, rating: rating)
        }
        .buttonStyle(PressableCardStyle())
    }
}

/// One library entry as a card: its doodle, the title, the tier, how it is doing, and a chevron.
/// An inactive one is dimmed: quiet title and doodle, and its tier loses its colour.
private struct LibraryRow: View {
    let entry: LibraryEntry
    let notes: Int
    let rating: Int?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) { LibraryDisc(entry: entry); text }
                    HStack(spacing: 8) {
                        if let rating { RatingBadge(value: rating) }
                        Spacer(minLength: 0)
                        chevron
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    LibraryDisc(entry: entry)
                    text
                    if let rating { RatingBadge(value: rating) }
                    chevron
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard(.surface, radius: LR.Radius.row)
        .contentShape(RoundedRectangle(cornerRadius: LR.Radius.row, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.text)
        .accessibilityValue(spoken)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.text).lr(.bodyStrong)
                .foregroundStyle(entry.isActive ? LR.Color.ink : LR.Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !entry.isActive || notes > 0 {
                FlowRow(spacing: 6) {
                    if !entry.isActive { PillLabel(text: "inactive") }
                    if notes > 0 { PillLabel(text: "\(notes) note\(notes == 1 ? "" : "s")") }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(LR.Color.iconNeutral)
            .accessibilityHidden(true)
    }

    private var spoken: String {
        [entry.tierName, entry.isActive ? nil : "inactive",
         notes > 0 ? "\(notes) note\(notes == 1 ? "" : "s")" : nil,
         rating.map { "latest rating \($0 > 0 ? "+\($0)" : "\($0)")" }]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

/// The entry's doodle (from its text, like every other row) in the neutral disc. A quest wears its
/// tier as a dot on the disc's edge; the section header and VoiceOver name the tier in words.
private struct LibraryDisc: View {
    let entry: LibraryEntry

    var body: some View {
        Circle().fill(LR.Color.pillFill)
            .frame(width: 52, height: 52)
            .overlay {
                DoodleView(key: DoodleKey.forText(entry.text), size: 28,
                           tint: entry.isActive ? LR.Color.ink : LR.Color.iconNeutral)
            }
            .overlay(alignment: .bottomTrailing) {
                if let tint = entry.tint {
                    Circle().fill(tint.color)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(LR.Color.surface, lineWidth: 2))
                        .opacity(entry.isActive ? 1 : 0.4)
                        .accessibilityHidden(true)
                }
            }
    }
}

/// The tier by name in its colour, or `Routine`; plain when the entry is inactive.
private struct LibraryTierPill: View {
    let entry: LibraryEntry

    var body: some View {
        if let tint = entry.tint, entry.isActive {
            PillLabel(text: entry.tierName, style: .tint(tint))
        } else {
            PillLabel(text: entry.tierName)
        }
    }
}

/// One library row, whichever table it came from. The text is what a new rating or note
/// snapshots, like every other history row.
private struct LibraryEntry {
    let id: UUID
    let target: FeedbackTarget
    let text: String
    let tierName: String
    /// Nil for a routine, which has no tier.
    let tint: QuestTint?
    let isActive: Bool

    init(template t: QuestTemplate) {
        id = t.id; target = .quest; text = t.text
        tierName = t.difficulty.rawValue.capitalized; tint = QuestTint(t.difficulty); isActive = t.isActive
    }

    init(routine r: RoutineTask) {
        id = r.id; target = .routine; text = r.text
        tierName = "Routine"; tint = nil; isActive = r.isActive
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
    private var canAddNote: Bool { !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LR.Spacing.sectionGap) {
                summaryCard
                ratingSection
                noteSection
                if let error { BannerView(message: error) }
                if !notes.isEmpty { notesSection }
                if !history.isEmpty { ratingsSection }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .reservingTabBarSpace()
        .background(LR.Color.canvas.ignoresSafeArea())
        .navigationTitle(entry.target == .quest ? "Quest" : "Routine")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: pieces

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lrCard(.surface, radius: LR.Radius.row)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: title)
            content()
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
    }

    private var divider: some View {
        Rectangle().fill(LR.Color.divider).frame(height: 1)
    }

    private var summaryCard: some View {
        card {
            HStack(alignment: .center, spacing: 12) {
                LibraryDisc(entry: entry)
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.text).lr(.bodyStrong)
                        .foregroundStyle(entry.isActive ? LR.Color.ink : LR.Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    FlowRow(spacing: 6) {
                        LibraryTierPill(entry: entry)
                        if !entry.isActive { PillLabel(text: "inactive") }
                    }
                    if !entry.isActive {
                        Text("Inactive — not drawn any more").lr(.caption)
                            .foregroundStyle(LR.Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.text)
        .accessibilityValue([entry.tierName, entry.isActive ? nil : "inactive, not drawn any more"]
            .compactMap { $0 }.joined(separator: ", "))
    }

    // MARK: rating

    private var ratingSection: some View {
        section("How do you feel about it now?") {
            card {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { ratingButtons }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ratingButtons
                    }
                }
            }
            if let last = history.first {
                caption("Latest: \(label(last.rating)), \(last.dayKey). Rating again adds a new entry; the old ones stay.")
            } else {
                caption("Not rated yet.")
            }
        }
    }

    private var ratingButtons: some View {
        ForEach(PointsRollView.scale, id: \.value) { step in
            let selected = history.first?.rating == step.value
            Button {
                Haptics.selection()
                rate(step.value)
            } label: {
                Image(systemName: step.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(selected ? LR.Color.onFill : LR.Color.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(selected ? LR.Color.fill : LR.Color.pillFill))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityLabel(step.label)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }

    // MARK: notes

    private var noteSection: some View {
        section("Add a note") {
            card {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("What worked, what didn't", text: $note,
                              prompt: Text("What worked, what didn't").foregroundStyle(LR.Color.inkSecondary),
                              axis: .vertical)
                        .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                        .frame(minHeight: 44, alignment: .topLeading)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Button("Add note") { addNote() }
                            .buttonStyle(PillButtonStyle())
                            .disabled(!canAddNote)
                            .opacity(canAddNote ? 1 : 0.4)
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        section("Notes") {
            VStack(spacing: 0) {
                ForEach(Array(notes.enumerated()), id: \.element.id) { index, c in
                    if index > 0 { divider }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.comment).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(c.dayKey).lr(.caption).monospacedDigit().foregroundStyle(LR.Color.inkSecondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(c.comment)
                    .accessibilityValue(c.dayKey)
                }
            }
            .lrCard(.surface, radius: LR.Radius.row)
        }
    }

    private var ratingsSection: some View {
        section("Ratings") {
            VStack(spacing: 0) {
                ForEach(Array(history.enumerated()), id: \.element.id) { index, r in
                    if index > 0 { divider }
                    let when = r.questID == nil ? r.dayKey : "\(r.dayKey) · right after doing it"
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label(r.rating)).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                            Text(when).lr(.caption).monospacedDigit().foregroundStyle(LR.Color.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        RatingBadge(value: r.rating)
                    }
                    .padding(12)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label(r.rating))
                    .accessibilityValue(when)
                }
            }
            .lrCard(.surface, radius: LR.Radius.row)
        }
    }

    // MARK: actions

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

/// `+2` on sage, `-1` on clay, `0` plain — the pill the ratings summary uses. The sign says it too.
private struct RatingBadge: View {
    let value: Int

    var body: some View {
        PillLabel(text: value > 0 ? "+\(value)" : "\(value)",
                  style: value > 0 ? .tint(.trivial) : value < 0 ? .clay : .plain)
            .monospacedDigit()
            .accessibilityHidden(true)
    }
}
