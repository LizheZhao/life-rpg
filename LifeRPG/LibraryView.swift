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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Which sections are open, as comma-joined keys: quests by tier name (none open by default),
    // routines by group key (all open by default).
    @AppStorage("library.openQuestTiers") private var openTiers = ""
    @AppStorage("library.openRoutineGroups") private var openGroups =
        RoutineSchedulePresentation.Group.allCases.map(\.rawValue).joined(separator: ",")

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

    private var routineSections: [RoutineSchedulePresentation.Section] {
        RoutineSchedulePresentation.grouped(routines.filter { matches($0.text) },
                                            lightIDs: Degrade.versionIDs(in: routines))
    }

    private var isEmpty: Bool {
        switch kind {
        case .quest: questGroups.isEmpty
        case .routine: routineSections.isEmpty
        }
    }

    /// A search shows every section that has a match, open, and leaves the remembered state alone.
    private func isOpen(_ stored: String, _ key: String) -> Bool {
        !search.isEmpty || OpenSections.contains(stored, key)
    }

    private func toggle(_ stored: Binding<String>, _ key: String) {
        guard search.isEmpty else { return }
        Haptics.selection()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            stored.wrappedValue = OpenSections.toggled(stored.wrappedValue, key)
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
                        let key = group.difficulty.rawValue
                        let open = isOpen(openTiers, key)
                        VStack(alignment: .leading, spacing: 10) {
                            LibrarySectionHeader(title: group.difficulty.rawValue.capitalized,
                                                 tint: QuestTint(group.difficulty), count: group.rows.count,
                                                 noun: "quest", isOpen: open) { toggle($openTiers, key) }
                            if open {
                                ForEach(group.rows) { link(LibraryEntry(template: $0)) }
                                    .transition(.opacity)
                            }
                        }
                    }
                case .routine:
                    ForEach(routineSections, id: \.group) { section in
                        let key = section.group.rawValue
                        let open = isOpen(openGroups, key)
                        VStack(alignment: .leading, spacing: 10) {
                            LibrarySectionHeader(title: section.group.title, tint: nil,
                                                 count: section.rows.count, noun: "routine",
                                                 isOpen: open) { toggle($openGroups, key) }
                            if open {
                                ForEach(section.rows, id: \.routine.id) {
                                    link(LibraryEntry(routine: $0.routine, schedule: $0.schedule))
                                }
                                .transition(.opacity)
                            }
                        }
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
            if entry.schedule != nil || !entry.isActive || notes > 0 {
                FlowRow(spacing: 6) {
                    if let schedule = entry.schedule { PillLabel(text: schedule.summary) }
                    if !entry.isActive { PillLabel(text: "inactive") }
                    if notes > 0 { PillLabel(text: "\(notes) note\(notes == 1 ? "" : "s")") }
                }
            }
            if let schedule = entry.schedule, schedule.strip != .none {
                WeekStrip(schedule: schedule, dimmed: !entry.isActive)
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
        [entry.tierName, entry.schedule?.summary, entry.isActive ? nil : "inactive",
         notes > 0 ? "\(notes) note\(notes == 1 ? "" : "s")" : nil,
         rating.map { "latest rating \($0 > 0 ? "+\($0)" : "\($0)")" }]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

/// The entry's doodle (from its text, like every other row) on a disc in its tier's colour, the
/// way Today's rows wear theirs. The section header and VoiceOver name the tier in words.
private struct LibraryDisc: View {
    let entry: LibraryEntry

    var body: some View {
        Circle().fill(entry.tint.color)
            .frame(width: 52, height: 52)
            .overlay {
                DoodleView(key: DoodleKey.forText(entry.text), size: 28, tint: LR.Color.ink(on: entry.tint))
            }
            .opacity(entry.isActive ? 1 : 0.4)
    }
}

/// The tier by name in its colour; plain when the entry is inactive.
private struct LibraryTierPill: View {
    let entry: LibraryEntry

    var body: some View {
        if entry.isActive {
            PillLabel(text: entry.tierName, style: .tint(entry.tint))
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
    let tint: QuestTint
    let isActive: Bool
    /// Nil for a quest.
    let schedule: RoutineSchedulePresentation?

    init(template t: QuestTemplate) {
        id = t.id; target = .quest; text = t.text
        tierName = t.difficulty.rawValue.capitalized; tint = QuestTint(t.difficulty); isActive = t.isActive
        schedule = nil
    }

    init(routine r: RoutineTask, schedule: RoutineSchedulePresentation) {
        id = r.id; target = .routine; text = r.text
        tierName = r.difficulty.rawValue.capitalized; tint = QuestTint(r.difficulty); isActive = r.isActive
        self.schedule = schedule
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
                if let schedule = entry.schedule { scheduleSection(schedule) }
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

    // MARK: schedule

    private func scheduleSection(_ s: RoutineSchedulePresentation) -> some View {
        section("Schedule") {
            card {
                VStack(alignment: .leading, spacing: 12) {
                    PillLabel(text: s.summary)
                    if s.strip != .none { WeekStrip(schedule: s, large: true, dimmed: !entry.isActive) }
                    Text(s.sentence).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let miss = s.missRule {
                        Text(miss).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if s.weeklyTarget != nil || s.usesAnchorWeek {
                        divider
                        if let target = s.weeklyTarget {
                            fact("Weekly target", "\(target)")
                            fact("Counts toward clearing the day", s.countsForClear ? "Yes" : "No")
                        }
                        if s.usesAnchorWeek {
                            fact("Anchor week", s.anchorWeekKey ?? "Set by the first time you do it")
                        }
                    }
                }
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value).lr(.bodyStrong).monospacedDigit().foregroundStyle(LR.Color.ink)
                .multilineTextAlignment(.trailing)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
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

/// Which sections of a list are open, kept as a comma-joined string so `@AppStorage` can hold it.
/// A key nobody asks about any more is simply never looked up.
private enum OpenSections {
    private static func keys(_ stored: String) -> [String] {
        stored.split(separator: ",").map(String.init)
    }

    static func contains(_ stored: String, _ key: String) -> Bool { keys(stored).contains(key) }

    static func toggled(_ stored: String, _ key: String) -> String {
        var open = keys(stored)
        if let index = open.firstIndex(of: key) { open.remove(at: index) } else { open.append(key) }
        return open.joined(separator: ",")
    }
}

/// A section header in Settings' own style that opens and closes its list: a chevron that turns, the
/// tier's colour as a dot (routine groups have none), the title and a hand count.
private struct LibrarySectionHeader: View {
    let title: String
    let tint: QuestTint?
    let count: Int
    let noun: String
    let isOpen: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .headline) private var dot: CGFloat = 10
    @ScaledMetric(relativeTo: .headline) private var chevronWidth: CGFloat = 16

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(LR.Color.iconNeutral)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: chevronWidth)
                    .accessibilityHidden(true)
                if let tint {
                    Circle().fill(tint.color).frame(width: dot, height: dot)
                        .accessibilityHidden(true)
                }
                Text(title).lr(.heading).foregroundStyle(LR.Color.sectionTitle)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("\(count)").lr(.hand).monospacedDigit().foregroundStyle(LR.Color.accent)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(count) \(noun)\(count == 1 ? "" : "s")")
        .accessibilityValue(isOpen ? "expanded" : "collapsed")
        .accessibilityHint(isOpen ? "Hides the list" : "Shows the list")
        .accessibilityAddTraits(.isHeader)
    }
}

/// Monday to Sunday as seven small circles. A fixed-day routine fills the days it comes up on; a
/// flexible one outlines all seven softly, since any day of the week counts. Decorative: the pill
/// and the sentence say the same in words, so VoiceOver skips it.
private struct WeekStrip: View {
    let schedule: RoutineSchedulePresentation
    var large = false
    var dimmed = false

    @ScaledMetric(relativeTo: .caption) private var largeLetter: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var rowCell: CGFloat = 24
    @ScaledMetric(relativeTo: .caption) private var rowLetter: CGFloat = 11

    private static let letters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        let cell: CGFloat = large ? 44 : rowCell
        let gap: CGFloat = large ? 6 : 4
        HStack(spacing: gap) {
            ForEach(0..<7, id: \.self) { day in
                self.cell(day)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: cell)
            }
        }
        .frame(maxWidth: cell * 7 + gap * 6, alignment: .leading)
        .accessibilityHidden(true)
    }

    private func cell(_ day: Int) -> some View {
        let filled = schedule.strip == .days && schedule.weekdays[day]
        return ZStack {
            if filled {
                Circle().fill(dimmed ? LR.Color.iconNeutral : LR.Color.ink)
            } else if schedule.strip == .anyDay {
                Circle().strokeBorder(LR.Color.iconNeutral.opacity(0.5), lineWidth: 1.5)
            } else {
                Circle().strokeBorder(LR.Color.hairline, lineWidth: 1.5)
            }
            Text(Self.letters[day])
                .font(.system(size: large ? min(largeLetter, 20) : min(rowLetter, 15), weight: .semibold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(filled ? LR.Color.onFill : LR.Color.inkSecondary)
        }
    }
}
