import LifeRPGCore
import SwiftData
import SwiftUI

/// The forms that write the library: the schedule controls shared by every place that picks when
/// a routine comes due, the sheet that changes it for a routine already there, and the sheet that
/// adds a new row from the Library page. They only edit a `LibrarySave.Draft`; what is valid and
/// what it becomes are Core's rules (`LibrarySave`, `LibraryEdit`).

// MARK: - the schedule controls

/// Weekly on chosen days, or monthly on the first / last given weekday; fixed or flexible, and how
/// many days a flexible week asks for. Used by "Save to library", by the new-row sheet and by the
/// schedule editor, so the three cannot drift.
struct ScheduleFields: View {
    @Binding var draft: LibrarySave.Draft
    /// Set while a session of the routine is open: switching fixed / flexible and lowering a
    /// flexible target are refused (`LibraryEdit.Failure.sessionOpen`), so the controls say so.
    var locked: (flexible: Bool, target: Int)?

    static let weekdays: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Segmented(items: [(LibrarySave.Draft.Frequency.weekly, "Weekly"), (.monthly, "Monthly")],
                      selection: $draft.frequency)
            switch draft.frequency {
            case .weekly: weeklyOptions
            case .monthly: monthlyOptions
            }
            FormToggle(title: "Flexible: any day that week counts", isOn: $draft.flexible)
                .disabled(locked != nil)
            if locked != nil {
                Text("Finish or skip the open one first.")
                    .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var weeklyOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("On these days").lr(.caption).foregroundStyle(LR.Color.inkSecondary)
            FlowRow(spacing: 6) {
                ForEach(Self.weekdays, id: \.self) { day in
                    DayChip(title: Self.short(day), selected: draft.days.contains(day),
                            label: Self.long(day)) {
                        if draft.days.contains(day) { draft.days.remove(day) } else { draft.days.insert(day) }
                        draft.timesPerWeek = min(max(draft.timesPerWeek, 1), draft.timesRange.upperBound)
                    }
                }
            }
            if draft.flexible, draft.days.count > 1 {
                Stepper(value: $draft.timesPerWeek, in: timesRange) {
                    Text("\(draft.timesPerWeek) of \(draft.days.count) days a week").lr(.bodyStrong)
                        .foregroundStyle(LR.Color.ink)
                }
                .frame(minHeight: 44)
            }
        }
    }

    /// A locked flexible routine may not ask for fewer days than it does now.
    private var timesRange: ClosedRange<Int> {
        let upper = draft.timesRange.upperBound
        guard let locked, locked.flexible else { return draft.timesRange }
        return min(locked.target, upper)...upper
    }

    private var monthlyOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Segmented(items: [(LibrarySave.MonthPosition.first, "First"), (.last, "Last")],
                      selection: $draft.position)
            FlowRow(spacing: 6) {
                ForEach(Self.weekdays, id: \.self) { day in
                    DayChip(title: Self.short(day), selected: draft.monthlyWeekday == day,
                            label: Self.long(day)) { draft.monthlyWeekday = day }
                }
            }
        }
    }

    /// "Due Mon, Thu" / "Due the last Saturday of the month" / "Pick the days".
    static func when(_ draft: LibrarySave.Draft) -> String {
        switch draft.frequency {
        case .weekly:
            return draft.days.isEmpty ? "Pick the days"
                : "Due " + weekdays.filter(draft.days.contains).map(short).joined(separator: ", ")
        case .monthly:
            return "Due the \(draft.position == .first ? "first" : "last") \(long(draft.monthlyWeekday)) of the month"
        }
    }

    static func short(_ day: Weekday) -> String {
        switch day {
        case .monday: "Mon"; case .tuesday: "Tue"; case .wednesday: "Wed"; case .thursday: "Thu"
        case .friday: "Fri"; case .saturday: "Sat"; case .sunday: "Sun"
        }
    }

    static func long(_ day: Weekday) -> String {
        switch day {
        case .monday: "Monday"; case .tuesday: "Tuesday"; case .wednesday: "Wednesday"; case .thursday: "Thursday"
        case .friday: "Friday"; case .saturday: "Saturday"; case .sunday: "Sunday"
        }
    }
}

/// A switch row with the form's spacing.
struct FormToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) { Text(title).lr(.bodyStrong).foregroundStyle(LR.Color.ink) }
            .tint(LR.Color.accent)
            .frame(minHeight: 44)
    }
}

/// A day or a tier as a capsule, selected or not.
struct DayChip: View {
    let title: String
    let selected: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(title).lr(.bodyStrong)
                .foregroundStyle(selected ? LR.Color.onFill : LR.Color.ink)
                .frame(minWidth: 44, minHeight: 44)
                .padding(.horizontal, 6)
                .background(Capsule().fill(selected ? LR.Color.fill : LR.Color.pillFill))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Two or three choices as capsules, one selected: the shape the Add sheet's own tabs have.
struct Segmented<Value: Hashable>: View {
    let items: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.0) { item in
                let selected = selection == item.0
                Button {
                    Haptics.selection()
                    selection = item.0
                } label: {
                    Text(item.1).lr(.bodyStrong)
                        .foregroundStyle(selected ? LR.Color.onFill : LR.Color.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(selected ? LR.Color.fill : LR.Color.pillFill))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

private struct FieldCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            // The row's disc is as tall as the field; without room above and below it meets the
            // card's rounded edge and reads as sitting outside the card.
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lrCard(.surface, radius: LR.Radius.row)
    }
}

// MARK: - change when a routine comes due

/// The sheet behind the Schedule card's button. Days reach forward only: a session already on the
/// page keeps its day (`LibraryEdit.setSchedule`).
struct LibraryScheduleEditor: View {
    let routineID: UUID
    let routineText: String
    @State var draft: LibrarySave.Draft
    /// Non-nil while a session of the routine is open.
    let locked: (flexible: Bool, target: Int)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LR.Spacing.sectionGap) {
                    Text(routineText).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    ScheduleFields(draft: $draft, locked: locked)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lrCard(.surface, radius: LR.Radius.row)
                    Text("\(ScheduleFields.when(draft)).")
                        .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                    if let problem = draft.problem {
                        Text("\(problem)").lr(.caption).foregroundStyle(LR.Color.clay)
                    }
                    if let error { BannerView(message: error) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                ConfirmBar(title: "Save", enabled: draft.problem == nil) { save() }
            }
            .background(LR.Color.canvas.ignoresSafeArea())
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(LR.Color.ink)
                }
            }
        }
    }

    private func save() {
        do {
            try LibraryEdit.setSchedule(draft, forRoutine: routineID, in: context)
            dismiss()
        } catch {
            self.error = "\(error)"
        }
    }
}

// MARK: - add a row to the library

/// The Library page's own add: a quest of any tier (a micro-action, an epic) or a routine, kept
/// without putting it on today's page. The Add sheet's "Save to library" stays the way to keep a
/// task that was just typed *and* do it today.
struct NewLibraryRowEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var draft = LibrarySave.Draft()
    @State private var difficulty: Difficulty = .easy
    @State private var error: String?

    private var isValid: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.problem == nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LR.Spacing.sectionGap) {
                    SectionTitle(title: "What")
                    HStack(spacing: 12) {
                        Circle().fill(LR.Color.pillFill).frame(width: 52, height: 52)
                            .overlay { DoodleView(key: DoodleKey.forText(text), size: 28) }
                            .accessibilityHidden(true)
                        TextField("What needs doing", text: $text,
                                  prompt: Text("What needs doing").foregroundStyle(LR.Color.inkSecondary),
                                  axis: .vertical)
                            .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                            .frame(minHeight: 44)
                    }
                    .modifier(FieldCard())

                    SectionTitle(title: "Kind")
                    Segmented(items: [(LibrarySave.Draft.Kind.quest, "Random quest"), (.routine, "Routine")],
                              selection: $draft.kind)

                    SectionTitle(title: "Tier")
                    FlowRow(spacing: 6) {
                        ForEach(LibrarySave.difficulties(for: draft.kind), id: \.self) { d in
                            DayChip(title: Self.name(d), selected: difficulty == d, label: Self.name(d)) {
                                difficulty = d
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        switch draft.kind {
                        case .quest:
                            if LibrarySave.allowsHiddenAndWeekend(difficulty) {
                                VStack(alignment: .leading, spacing: 0) {
                                    FormToggle(title: "Can be the hidden quest", isOn: $draft.hiddenEligible)
                                    FormToggle(title: "Weekends only", isOn: $draft.weekendOnly)
                                }
                            }
                        case .routine:
                            ScheduleFields(draft: $draft)
                        }
                        if let problem = draft.problem {
                            Text("\(problem)").lr(.caption).foregroundStyle(LR.Color.clay)
                        }
                        Text(summary).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lrCard(.surface, radius: LR.Radius.row)

                    if let error { BannerView(message: error) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                ConfirmBar(title: "Add to library", enabled: isValid) { save() }
            }
            .background(LR.Color.canvas.ignoresSafeArea())
            .navigationTitle("New in library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(LR.Color.ink)
                }
            }
            .onChange(of: draft.kind) { _, kind in
                if !LibrarySave.difficulties(for: kind).contains(difficulty) { difficulty = .easy }
            }
        }
    }

    private static func name(_ d: Difficulty) -> String { d.rawValue.capitalized }

    /// One line saying what saving will make.
    private var summary: String {
        switch draft.kind {
        case .quest:
            return Self.tierNote(difficulty)
        case .routine:
            let pays = AdHoc.basePoints(for: difficulty).map { "pays \($0)" } ?? ""
            return "\(ScheduleFields.when(draft)) · \(pays)."
        }
    }

    /// What a quest of this tier pays, in a few words.
    static func tierNote(_ difficulty: Difficulty) -> String {
        switch difficulty {
        case .trivial: "Pays \(Difficulty.trivial.range.lowerBound) each, drawn in threes."
        case .epic: "Pays \(Difficulty.epic.range.lowerBound)\u{2013}\(Difficulty.epic.range.upperBound)."
        default: "Pays by tier."
        }
    }

    private func save() {
        do {
            try draft.save(text: text, difficulty: difficulty, in: context)
            dismiss()
        } catch {
            self.error = "\(error)"
        }
    }
}

// MARK: - rename or delete a library row

/// Behind the detail page's pencil: the row's name, and Delete. Delete archives at once; the Library
/// page offers an Undo for a few seconds, and Archived keeps the row after that.
struct LibraryManageSheet: View {
    let name: String
    /// Throws what `LibraryEdit.rename` throws; the message stays on the sheet.
    let rename: (String) throws -> Void
    /// Archives the row. The sheet closes after it, and the caller leaves the page.
    let delete: () throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var error: String?

    init(name: String, rename: @escaping (String) throws -> Void, delete: @escaping () throws -> Void) {
        self.name = name
        self.rename = rename
        self.delete = delete
        _text = State(initialValue: name)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmed.isEmpty && trimmed != name }

    var body: some View {
        NavigationStack {
            editor
                .background(LR.Color.canvas.ignoresSafeArea())
                .navigationTitle("Edit")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.foregroundStyle(LR.Color.ink)
                    }
                }
        }
        .presentationDetents([.medium])
        .presentationBackground(LR.Color.canvas)
    }

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LR.Spacing.sectionGap) {
                SectionTitle(title: "Name")
                TextField("Name", text: $text, prompt: Text("Name").foregroundStyle(LR.Color.inkSecondary),
                          axis: .vertical)
                    .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                    .frame(minHeight: 44)
                    .modifier(FieldCard())

                Button {
                    do {
                        try delete()
                        dismiss()
                    } catch {
                        self.error = "\(error)"
                    }
                } label: {
                    Label("Delete", systemImage: "trash").foregroundStyle(LR.Color.clay)
                }
                .buttonStyle(PillButtonStyle())
                .padding(.top, 6)

                if let error { BannerView(message: error) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            ConfirmBar(title: "Save", enabled: canSave) {
                do {
                    try rename(trimmed)
                    dismiss()
                } catch {
                    self.error = "\(error)"
                }
            }
        }
    }
}
