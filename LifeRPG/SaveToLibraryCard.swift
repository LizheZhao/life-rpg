import LifeRPGCore
import SwiftUI

/// "Save to library", under a custom task: keep what was just typed as a quest in the random pool,
/// or as a routine on a schedule, so it never has to be typed again. The card only edits a
/// `LibrarySave.Draft`; what it needs to be valid and what it becomes are Core's rules.
struct SaveToLibraryCard: View {
    @Binding var isOn: Bool
    @Binding var draft: LibrarySave.Draft
    /// The difficulty chosen above, which is what decides a routine's points.
    let difficulty: Difficulty

    private static let weekdays: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $isOn) {
                Text("Save to library").lr(.bodyStrong).foregroundStyle(LR.Color.ink)
            }
            .tint(LR.Color.accent)
            .frame(minHeight: 44)

            if isOn {
                Segmented(items: [(LibrarySave.Draft.Kind.quest, "Random quest"), (.routine, "Routine")],
                          selection: $draft.kind)
                switch draft.kind {
                case .quest: questOptions
                case .routine: routineOptions
                }
                if let problem = draft.problem {
                    Text("\(problem)").lr(.caption).foregroundStyle(LR.Color.clay)
                }
                caption(summary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard(.surface, radius: LR.Radius.row)
        .animation(.easeOut(duration: 0.2), value: isOn)
    }

    // MARK: a quest

    private var questOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            toggle("Can be the hidden quest", $draft.hiddenEligible)
            toggle("Weekends only", $draft.weekendOnly)
        }
    }

    // MARK: a routine

    private var routineOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Segmented(items: [(LibrarySave.Draft.Frequency.weekly, "Weekly"), (.monthly, "Monthly")],
                      selection: $draft.frequency)
            switch draft.frequency {
            case .weekly: weeklyOptions
            case .monthly: monthlyOptions
            }
            toggle("Flexible: any day that week counts", $draft.flexible)
        }
    }

    private var weeklyOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("On these days")
            FlowRow(spacing: 6) {
                ForEach(Self.weekdays, id: \.self) { day in
                    chip(Self.short(day), selected: draft.days.contains(day)) {
                        if draft.days.contains(day) { draft.days.remove(day) } else { draft.days.insert(day) }
                        draft.timesPerWeek = min(max(draft.timesPerWeek, 1), draft.timesRange.upperBound)
                    }
                }
            }
            if draft.flexible, draft.days.count > 1 {
                Stepper(value: $draft.timesPerWeek, in: draft.timesRange) {
                    Text("\(draft.timesPerWeek) of \(draft.days.count) days a week").lr(.bodyStrong)
                        .foregroundStyle(LR.Color.ink)
                }
                .frame(minHeight: 44)
            }
        }
    }

    private var monthlyOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Segmented(items: [(LibrarySave.MonthPosition.first, "First"), (.last, "Last")],
                      selection: $draft.position)
            FlowRow(spacing: 6) {
                ForEach(Self.weekdays, id: \.self) { day in
                    chip(Self.short(day), selected: draft.monthlyWeekday == day) { draft.monthlyWeekday = day }
                }
            }
        }
    }

    // MARK: pieces

    /// One line saying what saving will make: when it comes due and what it pays.
    private var summary: String {
        switch draft.kind {
        case .quest:
            return "Joins the random pool as a \(difficulty.rawValue) quest; its tier decides what it pays."
        case .routine:
            let pays = AdHoc.basePoints(for: difficulty).map { "pays \($0)" } ?? ""
            let when: String
            switch draft.frequency {
            case .weekly:
                when = draft.days.isEmpty ? "pick the days"
                    : "due " + Self.weekdays.filter(draft.days.contains).map(Self.short).joined(separator: ", ")
            case .monthly:
                when = "due the \(draft.position == .first ? "first" : "last") \(Self.long(draft.monthlyWeekday)) of the month"
            }
            return "\(when.prefix(1).uppercased() + when.dropFirst()) · \(pays) · counts toward clearing the day."
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
    }

    private func caption(_ text: String) -> some View {
        Text(text).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func toggle(_ title: String, _ value: Binding<Bool>) -> some View {
        Toggle(isOn: value) { Text(title).lr(.bodyStrong).foregroundStyle(LR.Color.ink) }
            .tint(LR.Color.accent)
            .frame(minHeight: 44)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
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
        .accessibilityLabel(Self.long(Self.weekdays.first { Self.short($0) == title } ?? .monday))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private static func short(_ day: Weekday) -> String {
        switch day {
        case .monday: "Mon"; case .tuesday: "Tue"; case .wednesday: "Wed"; case .thursday: "Thu"
        case .friday: "Fri"; case .saturday: "Sat"; case .sunday: "Sun"
        }
    }

    private static func long(_ day: Weekday) -> String {
        switch day {
        case .monday: "Monday"; case .tuesday: "Tuesday"; case .wednesday: "Wednesday"; case .thursday: "Thursday"
        case .friday: "Friday"; case .saturday: "Saturday"; case .sunday: "Sunday"
        }
    }
}

/// Two or three choices as capsules, one selected: the shape the Add sheet's own tabs have.
private struct Segmented<Value: Hashable>: View {
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
