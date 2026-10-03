import LifeRPGCore
import SwiftData
import SwiftUI

/// Adding a routine for the day (`PLAN.md` §3), three ways:
/// - from a random slot's "Replace" action, in place of that slot (`AdHoc.replace`);
/// - from a routine's "Replace" action, in place of that routine, for something at least as
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
    @Environment(\.dynamicTypeSize) private var typeSize

    @Query private var occurrences: [RoutineOccurrence]
    @Query private var routines: [RoutineTask]
    /// Only for the level, which prices a late make-up (`Perks`).
    @Query private var ledger: [LedgerEntry]

    private enum Tab: Hashable { case library, custom }
    @State private var tab: Tab = .library
    @State private var routineID: UUID?
    @State private var text = ""
    @State private var difficulty: Difficulty = .easy
    /// The doodle picked by hand; nil follows what the typed text suggests.
    @State private var pickedDoodle: DoodleKey?
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

    /// What the typed text suggests until a doodle is picked by hand.
    private var doodle: DoodleKey { pickedDoodle ?? DoodleKey.forText(text) }

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
                : .custom(text: trimmed, difficulty: difficulty, iconKey: doodle)
        }
    }
    private var sourceText: String {
        switch source {
        case .routine(let r): r.text
        case .custom(let t, _, _): t
        case nil: ""
        }
    }

    private var actionTitle: String { isAdding ? "Add" : "Replace" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LR.Spacing.sectionGap) {
                    replacesCard
                    PillSegmentedControl(options: [("From library", Tab.library), ("Custom", Tab.custom)],
                                         selection: $tab, accessibilityLabel: "Source")
                    if isAdding {
                        Text("Extra work on top of today. It replaces nothing, doesn't block the hidden quest and costs nothing if left undone. Done, it pays like any routine.")
                            .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 6)
                    }
                    switch tab {
                    case .library: librarySection
                    case .custom: customSection
                    }
                    if let error { BannerView(message: error) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                ConfirmBar(title: actionTitle, enabled: source != nil) { confirming = true }
            }
            .background(LR.Color.canvas.ignoresSafeArea())
            .navigationTitle(isAdding ? "Add for today" : "Replace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(LR.Color.ink)
                }
            }
            .alert(isAdding ? "Add for today?" : "Replace it?", isPresented: $confirming) {
                Button(actionTitle) { commit() }
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

    // MARK: what is being replaced

    @ViewBuilder private var replacesCard: some View {
        if let slot {
            ReplacesCard(
                doodle: slot.isTrivialGroup ? .sparkle : DoodleKey.forText(slot.textSnapshot),
                title: slotText,
                pill: slot.isTrivialGroup ? "micro-actions" : slot.slot.rawValue,
                note: "The replaced quest no longer counts toward today's clear. The new routine does, and like any routine it loses points each day it stays undone.")
        }
        if let o = replacedRoutine {
            ReplacesCard(
                doodle: o.doodle,
                title: slotText,
                pill: "worth \(minimumBase)",
                note: o.dueDayKey < today
                    ? "Free, for something worth at least \(minimumBase). It stops being charged; deductions already made stay. The new one takes its place in the overdue count and doesn't start a fresh round."
                    : "Free, for something worth at least \(minimumBase). The new one takes its place: it gates today's clear and loses points each day it stays undone.")
        }
    }

    // MARK: library tab

    @ViewBuilder private var librarySection: some View {
        SectionTitle(title: "Routine")
        if candidates.isEmpty {
            RecordRowView(title: minimumBase > 0
                          ? "No routine that isn't already on today's page is worth \(minimumBase) or more."
                          : "Every active routine is already on today's page.", secondary: true) { EmptyView() }
        }
        ForEach(candidates) { r in
            let pays = pays(r.basePoints)
            ChoiceRow(doodle: DoodleKey.resolve(iconKey: nil, text: r.text), title: r.text,
                      pills: [("+\(pays)", .plain)] + (tier.isLow ? [("low day", .plain)] : []),
                      selected: routineID == r.id) { routineID = r.id }
        }
        if !onPage.isEmpty {
            SectionTitle(title: "Already on today's page")
            ForEach(onPage, id: \.occurrence.id) { entry in
                onPageRow(entry.routine, entry.occurrence).modifier(RowCard())
            }
            Text(isAdding ? "Did one of these? Mark it done here, since adding it again wouldn't count for the routine."
                          : "These are already on today's page, so they can't be picked here.")
                .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
        }
    }

    /// One routine already on the page: where it is, and, when adding, a way to mark it done.
    private func onPageRow(_ r: RoutineTask, _ o: RoutineOccurrence) -> some View {
        let pays = Completion.routinePayout(o, flexible: r.flexibleWithinWeek, on: today, tier: tier,
                                            level: Economy.level(ledger))
        return PlainRow(doodle: o.doodle, title: o.displayText,
                        caption: whereNote(o, flexible: r.flexibleWithinWeek)) {
            if let points = o.awardedPoints {
                PillLabel(text: "+\(points)", style: .plain).monospacedDigit()
            } else if isAdding, let pays, Schedule.isOpen(o) {
                Button("Done · \(pays)") { markingDone = o }.buttonStyle(PillButtonStyle())
            }
        }
    }

    private func whereNote(_ o: RoutineOccurrence, flexible: Bool) -> String {
        if o.completedDayKey != nil { return "Done today" }
        if o.dueDayKey == today { return "Due today" }
        return flexible ? "Open since \(o.dueDayKey) · any day this week"
                        : "Overdue since \(o.dueDayKey)"
    }

    // MARK: custom tab

    @ViewBuilder private var customSection: some View {
        SectionTitle(title: "Task")
        HStack(spacing: 12) {
            DoodleDisc(key: doodle)
            TextField("What needs doing", text: $text,
                      prompt: Text("What needs doing").foregroundStyle(LR.Color.inkSecondary))
                .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                .submitLabel(.done)
                .frame(minHeight: 44)
        }
        .modifier(RowCard())

        SectionTitle(title: "Difficulty")
        difficultyChoices
        if let base = AdHoc.basePoints(for: difficulty) {
            Text("Pays \(pays(base)), the middle of the \(difficulty.rawValue) range.")
                .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                .padding(.horizontal, 6)
        }

        SectionTitle(title: "Doodle", count: pickedDoodle == nil ? "suggested" : "picked")
        DoodlePicker(selection: doodle) { pickedDoodle = $0 }

        if !similar.isEmpty { similarCard }
    }

    private var difficultyChoices: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { difficultyButtons }
            VStack(spacing: 8) { difficultyButtons }
        }
    }

    private var difficultyButtons: some View {
        ForEach(difficulties, id: \.self) { d in
            let selected = difficulty == d
            let tint = QuestTint(d)
            Button {
                Haptics.selection()
                difficulty = d
            } label: {
                Text(d.rawValue.capitalized).lr(.bodyStrong)
                    .foregroundStyle(selected ? LR.Color.ink(on: tint) : LR.Color.ink)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(selected ? tint.color : LR.Color.pillFill))
                    .overlay(Capsule().strokeBorder(LR.Color.ink, lineWidth: selected ? 2 : 0))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }

    /// Library routines close to the custom text: on the page, mark that one done; otherwise,
    /// switch to the library tab with it selected.
    private var similarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Similar in your library").lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(similar.enumerated()), id: \.element.id) { index, r in
                if index > 0 { Rectangle().fill(LR.Color.divider).frame(height: 1) }
                similarRow(r)
            }
            Text("A custom task counts toward no routine's weekly target. If it's one of these, use that instead.")
                .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard(.surface, radius: LR.Radius.row)
    }

    @ViewBuilder private func similarRow(_ r: RoutineTask) -> some View {
        if let o = AdHoc.onPageOccurrence(for: r, occurrences: occurrences, on: today) {
            onPageRow(r, o)
        } else if candidates.contains(where: { $0.id == r.id }) {
            PlainRow(doodle: DoodleKey.resolve(iconKey: nil, text: r.text), title: r.text) {
                Button("Use this") {
                    routineID = r.id
                    tab = .library
                }
                .buttonStyle(PillButtonStyle())
            }
        } else {
            // Replacing a routine and too light to stand in for it.
            PlainRow(doodle: DoodleKey.resolve(iconKey: nil, text: r.text), title: r.text,
                     caption: "worth \(r.basePoints)", secondary: true) { EmptyView() }
        }
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
            ScrollView {
                VStack(alignment: .leading, spacing: LR.Spacing.sectionGap) {
                    ReplacesCard(
                        doodle: .flag, title: epic.textSnapshot, pill: "epic",
                        note: "Free. The new epic keeps the deadline (\(Epic.lastDayKey(of: epic) ?? "Sunday")) and pays an ordinary epic roll, \(Difficulty.epic.range.lowerBound)–\(Difficulty.epic.range.upperBound).")
                    PillSegmentedControl(options: [("From library", Tab.library), ("Custom", Tab.custom)],
                                         selection: $tab, accessibilityLabel: "Source")
                    SectionTitle(title: "Epic")
                    switch tab {
                    case .library:
                        if candidates.isEmpty {
                            RecordRowView(title: "No other epic in the library.", secondary: true) { EmptyView() }
                        }
                        ForEach(candidates) { t in
                            ChoiceRow(doodle: DoodleKey.resolve(iconKey: nil, text: t.text), title: t.text,
                                      pills: [], selected: templateID == t.id) { templateID = t.id }
                        }
                    case .custom:
                        HStack(spacing: 12) {
                            DoodleDisc(key: .flag)
                            TextField("This week's big thing", text: $text,
                                      prompt: Text("This week's big thing").foregroundStyle(LR.Color.inkSecondary))
                                .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                                .submitLabel(.done)
                                .frame(minHeight: 44)
                        }
                        .modifier(RowCard())
                    }
                    if let error { BannerView(message: error) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                ConfirmBar(title: "Replace", enabled: pick != nil) { confirming = true }
            }
            .background(LR.Color.canvas.ignoresSafeArea())
            .navigationTitle("Replace the epic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(LR.Color.ink)
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

// MARK: - pieces shared by both sheets

/// The card frame of a row: padding, the surface and its hairline and shadow.
private struct RowCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lrCard(.surface, radius: LR.Radius.row)
    }
}

/// A doodle in the neutral disc routine rows use on a surface card.
private struct DoodleDisc: View {
    let key: DoodleKey
    var size: CGFloat = 52

    var body: some View {
        Circle().fill(LR.Color.pillFill)
            .frame(width: size, height: size)
            .overlay { DoodleView(key: key, size: size * 0.54) }
    }
}

/// A doodle, a title, an optional caption and whatever sits at the trailing edge. At
/// accessibility sizes the trailing control drops under the text.
private struct PlainRow<Trailing: View>: View {
    let doodle: DoodleKey
    let title: String
    var caption: String?
    var pills: [(text: String, style: PillLabel.Style)] = []
    var secondary = false
    var discSize: CGFloat = 52
    @ViewBuilder let trailing: Trailing

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) { DoodleDisc(key: doodle, size: discSize); text }
                HStack(spacing: 0) { Spacer(minLength: 0); trailing }
            }
        } else {
            HStack(alignment: .center, spacing: 12) {
                DoodleDisc(key: doodle, size: discSize)
                text
                trailing
            }
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).lr(.bodyStrong)
                .foregroundStyle(secondary ? LR.Color.inkSecondary : LR.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let caption {
                Text(caption).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !pills.isEmpty {
                FlowRow(spacing: 6) {
                    ForEach(Array(pills.enumerated()), id: \.offset) { _, pill in
                        PillLabel(text: pill.text, style: pill.style).monospacedDigit()
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A selectable library row: its own doodle, the title, payout and tier pills, and a radio mark.
/// Selected is an ink ring round the card plus a filled check, so it never rests on colour.
private struct ChoiceRow: View {
    let doodle: DoodleKey
    let title: String
    let pills: [(text: String, style: PillLabel.Style)]
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            if !selected { Haptics.selection() }
            action()
        } label: {
            PlainRow(doodle: doodle, title: title, pills: pills) { mark }
                .modifier(RowCard())
                .overlay {
                    RoundedRectangle(cornerRadius: LR.Radius.row, style: .continuous)
                        .strokeBorder(LR.Color.ink, lineWidth: 2)
                        .opacity(selected ? 1 : 0)
                }
                .contentShape(RoundedRectangle(cornerRadius: LR.Radius.row, style: .continuous))
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(pills.map(\.text).joined(separator: ", ") + (selected ? ", selected" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var mark: some View {
        ZStack {
            Circle().strokeBorder(LR.Color.iconNeutral, lineWidth: 1.5).opacity(selected ? 0 : 1)
            Circle().fill(LR.Color.fill).opacity(selected ? 1 : 0)
            HandCheck()
                .stroke(LR.Color.onFill, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .frame(width: 18, height: 18)
                .opacity(selected ? 1 : 0)
        }
        .frame(width: 30, height: 30)
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

/// What is being swapped out: the old row, struck through and quiet, and why it matters.
private struct ReplacesCard: View {
    let doodle: DoodleKey
    let title: String
    let pill: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                DoodleDisc(key: doodle)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Replaces").lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                    Text(title).lr(.bodyStrong).strikethrough()
                        .foregroundStyle(LR.Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    PillLabel(text: pill, style: .plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(note).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard(.surface, radius: LR.Radius.row)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Replaces \(title), \(pill)")
        .accessibilityValue(note)
    }
}

/// Every doodle in a grid, the chosen one ringed. Decorative drawings; each button speaks its name.
private struct DoodlePicker: View {
    let selection: DoodleKey
    let onPick: (DoodleKey) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: LR.Spacing.gridGap)],
                  spacing: LR.Spacing.gridGap) {
            ForEach(DoodleKey.allCases, id: \.self) { key in
                let selected = key == selection
                Button {
                    if !selected { Haptics.selection() }
                    onPick(key)
                } label: {
                    Circle().fill(LR.Color.pillFill)
                        .overlay { DoodleView(key: key, size: 30) }
                        .overlay {
                            Circle().strokeBorder(LR.Color.ink, lineWidth: 2.5).opacity(selected ? 1 : 0)
                        }
                        .frame(width: 56, height: 56)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .contentShape(Circle())
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityLabel(key.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard(.surface, radius: LR.Radius.row)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Doodle")
    }
}
