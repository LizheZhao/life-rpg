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
                case .routine: ScheduleFields(draft: $draft)
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
            FormToggle(title: "Can be the hidden quest", isOn: $draft.hiddenEligible)
            FormToggle(title: "Weekends only", isOn: $draft.weekendOnly)
        }
    }

    /// One line saying what saving will make: when it comes due and what it pays.
    private var summary: String {
        switch draft.kind {
        case .quest:
            return "Joins the random pool; its tier (\(difficulty.rawValue.capitalized)) decides what it pays."
        case .routine:
            let pays = AdHoc.basePoints(for: difficulty).map { "pays \($0)" } ?? ""
            return "\(ScheduleFields.when(draft)) · \(pays) · counts toward clearing the day."
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
