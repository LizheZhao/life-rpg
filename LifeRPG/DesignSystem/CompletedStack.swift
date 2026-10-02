import LifeRPGCore
import SwiftUI

extension CompletedItem {
    /// The colour of the card the item had while open: a quest keeps its tint when done.
    var fill: Color {
        switch self {
        case .quest(let s): s.tint.color
        case .routine, .epic: LR.Color.surface
        }
    }
}

/// A finished item as a card: a routine row, the epic row, or a small tinted row for a quest.
/// Done rows carry no menu and complete nothing; only the epic still expands on a tap.
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
        VStack(alignment: .leading, spacing: 2) {
            DoneTitle(text: state.title, isDone: true)
            if state.layout == .trivialGroup {
                Text(state.items.map(\.text).joined(separator: " · "))
                    .lr(.caption).foregroundStyle(LR.Color.inkOnTint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var check: some View { CompleteButton(isDone: true) {} }
}

/// Everything done today in one section: the most recent card on top with up to two more peeking
/// out behind it. A tap on the stack or the header fans it out into the full list; `Collapse` or
/// the header folds it again. The flag lives with the caller, so a lazily recycled row cannot
/// forget it.
struct CompletedStackView: View {
    let state: CompletedStackState
    @Binding var expanded: Bool

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
                    ForEach(state.items) { CompletedCardView(item: $0) }
                    Button("Collapse", action: toggle)
                        .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .lrCard(.surface, radius: LR.Radius.row)
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            } else if let top = state.items.first {
                Button(action: toggle) { stack(top: top) }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(state.accessibilityLabel)
                    .accessibilityValue("collapsed")
                    .accessibilityHint("Shows every completed item")
                    .accessibilityAddTraits(.isButton)
                    .transition(.opacity)
            }
        }
    }

    /// Collapsed, the stack below speaks for the whole section, so the header is skipped rather
    /// than read twice.
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
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityValue("expanded")
        .accessibilityAddTraits(.isHeader)
        .accessibilityHint("Collapses the list")
        .accessibilityHidden(!expanded)
    }

    private var headerTitle: some View {
        Text("Completed").lr(.heading).foregroundStyle(LR.Color.ink)
    }

    private var headerCount: some View {
        Text(state.summary).lr(.hand).foregroundStyle(LR.Color.inkHand)
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
        let behind = Array(state.items.dropFirst().prefix(2))
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
                if state.count > 1 {
                    Text("+\(state.count - 1) more")
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
