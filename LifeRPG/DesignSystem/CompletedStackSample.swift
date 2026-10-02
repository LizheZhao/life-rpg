import LifeRPGCore
import SwiftUI

// A SAMPLE, not wired to the Today page: completed items gathered into a stack of cards that
// fans out on tap, next to a flat dimmed list for comparison. The views take value structs and
// hold only their own expanded flag, so they can move onto the real page later unchanged.

/// One finished thing, as the states Core already builds for the Today cards.
enum CompletedItem: Identifiable {
    case quest(QuestCardState)
    case routine(RoutineRowState)
    case epic(EpicCardState)

    var id: UUID {
        switch self {
        case .quest(let s): s.id
        case .routine(let s): s.id
        case .epic(let s): s.id
        }
    }

    var awardedPoints: Int {
        switch self {
        case .quest(let s): s.awardedPoints ?? 0
        case .routine(let s): s.awardedPoints ?? 0
        case .epic(let s): s.awardedPoints ?? 0
        }
    }

    /// The colour of the card the item had while open: a quest keeps its tint when done.
    var fill: Color {
        switch self {
        case .quest(let s): s.tint.color
        case .routine, .epic: LR.Color.surface
        }
    }
}

/// `4 done · +160`, the hand label of the section.
private func completedSummary(_ items: [CompletedItem]) -> String {
    "\(items.count) done · +\(items.reduce(0) { $0 + $1.awardedPoints })"
}

/// A finished item as a card: a routine row, the epic row, or a small tinted row for a quest.
private struct CompletedCardView: View {
    let item: CompletedItem

    var body: some View {
        switch item {
        case .quest(let state): CompletedQuestRow(state: state)
        case .routine(let state): RoutineRowView(state: state, onComplete: {})
        case .epic(let state): EpicCardView(state: state, onComplete: {})
        }
    }
}

/// A done quest as a small row on its own tint: doodle, struck-through title, `+N`, filled check.
private struct CompletedQuestRow: View {
    let state: QuestCardState

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) { DoodleView(key: state.doodle, size: 30); title }
                    HStack { PillLabel(text: state.pillText, style: .onTint); Spacer(); check }
                }
            } else {
                HStack(spacing: 10) {
                    DoodleView(key: state.doodle, size: 30)
                    title
                    PillLabel(text: state.pillText, style: .onTint)
                    check
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard(.tint(state.tint.color), radius: LR.Radius.tile)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityValue(state.accessibilityValue)
    }

    private var title: some View {
        DoneTitle(text: state.title, isDone: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var check: some View { CompleteButton(isDone: true) {} }
}

/// Variant A: the most recent card on top with up to two more peeking out behind it. Tap the
/// stack (or the header) and it fans out into the full list; `Collapse` or the header folds it.
struct CompletedStackView: View {
    let items: [CompletedItem]

    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .footnote) private var captionHeight: CGFloat = 18

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.8)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LR.Spacing.sectionGap) {
            header
            if expanded {
                VStack(spacing: LR.Spacing.gridGap) {
                    ForEach(items) { CompletedCardView(item: $0) }
                    Button("Collapse", action: toggle)
                        .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .lrCard(.surface, radius: LR.Radius.row)
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            } else if let top = items.first {
                Button(action: toggle) { stack(top: top) }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Completed, \(completedSummary(items))")
                    .accessibilityHint("Shows every completed item")
                    .transition(.opacity)
            }
        }
    }

    private var header: some View {
        Button(action: toggle) {
            // Stacked at accessibility sizes, so "Completed" is never broken mid-word.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { headerTitle; Spacer(minLength: 8); headerCount; chevron }
                VStack(alignment: .leading, spacing: 2) {
                    HStack { headerTitle; Spacer(minLength: 8); chevron }
                    headerCount
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Completed, \(completedSummary(items))")
        .accessibilityValue(expanded ? "expanded" : "collapsed")
        .accessibilityAddTraits(.isHeader)
        .accessibilityHint(expanded ? "Collapses the list" : "Expands the list")
    }

    private var headerTitle: some View {
        Text("Completed").lr(.heading).foregroundStyle(LR.Color.ink)
    }

    private var headerCount: some View {
        Text(completedSummary(items)).lr(.hand).foregroundStyle(LR.Color.inkHand)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(LR.Color.inkSecondary)
            .rotationEffect(.degrees(expanded ? 90 : 0))
    }

    /// The top card, and behind it the next two as slightly narrower, dimmed slabs of the same
    /// colour, each a little lower. The bottom padding makes room for what sticks out.
    private func stack(top: CompletedItem) -> some View {
        let behind = Array(items.dropFirst().prefix(2))
        return CompletedCardView(item: top)
            .allowsHitTesting(false)
            .background(alignment: .top) {
                ForEach(Array(behind.enumerated()).reversed(), id: \.element.id) { index, item in
                    let depth = CGFloat(index + 1)
                    RoundedRectangle(cornerRadius: LR.Radius.row, style: .continuous)
                        .fill(item.fill)
                        .overlay {
                            RoundedRectangle(cornerRadius: LR.Radius.row, style: .continuous)
                                .fill(LR.Color.canvas.opacity(0.1 + 0.12 * depth))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: LR.Radius.row, style: .continuous)
                                .strokeBorder(LR.Color.inkSecondary.opacity(0.35), lineWidth: 1)
                        }
                        .padding(.horizontal, 14 * depth)
                        .offset(y: peek * depth)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if items.count > 1 {
                    Text("+\(items.count - 1) more")
                        .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                        .offset(y: peek * CGFloat(behind.count) + captionHeight + 4)
                }
            }
            .padding(.bottom, peek * CGFloat(behind.count) + captionHeight + 8)
    }

    /// How far each card behind sticks out below the one in front.
    private let peek: CGFloat = 12

    private func toggle() {
        withAnimation(animation) { expanded.toggle() }
    }
}

/// Variant B: no stacking, the same cards in a flat list, dimmed so they step back from open ones.
struct CompletedFlatListView: View {
    let items: [CompletedItem]

    var body: some View {
        VStack(alignment: .leading, spacing: LR.Spacing.gridGap) {
            SectionTitle(title: "Completed", count: completedSummary(items))
            ForEach(items) { CompletedCardView(item: $0).opacity(0.6) }
        }
    }
}

/// The gallery section: both variants from one set of sample items.
struct CompletedStackSample: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("A: stacked, tap to fan out").lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                CompletedStackView(items: Self.items)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("B: flat list, dimmed").lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                CompletedFlatListView(items: Self.items)
            }
        }
    }

    private static let friday = "2026-10-02"

    private static var items: [CompletedItem] {
        [.quest(quest("Browse a supermarket without buying anything", .medium, points: 17)),
         .routine(routine("Workout: running", base: 25)),
         .quest(quest("Listen to a stand-up comedy clip", .easy, points: 6)),
         .epic(epic("Get a side project to demo-able state", points: 112))]
    }

    private static func quest(_ text: String, _ slot: Difficulty, points: Int) -> QuestCardState {
        let q = DailyQuest()
        q.dayKey = friday
        q.slot = slot
        q.textSnapshot = text
        q.points = points
        return QuestCardState(q, tier: .normal)
    }

    private static func routine(_ text: String, base: Int) -> RoutineRowState {
        let o = RoutineOccurrence()
        o.textSnapshot = text
        o.basePoints = base
        o.dueDayKey = friday
        o.weekKey = "2026-W40"
        o.routineID = UUID()
        o.completedDayKey = friday
        o.awardedPoints = base
        return RoutineRowState(o, placement: .today, routine: nil, flexible: false, today: friday,
                               tier: .normal, level: 1, quests: [], occurrences: [o])
    }

    private static func epic(_ text: String, points: Int) -> EpicCardState {
        let e = DailyQuest()
        e.slot = .epic
        e.dayKey = "2026-09-28"
        e.textSnapshot = text
        e.points = points
        return EpicCardState(e, today: friday, tier: .normal, level: 1)
    }
}
