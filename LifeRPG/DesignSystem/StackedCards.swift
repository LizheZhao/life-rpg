import SwiftUI

/// A section of cards that gathers into one stack: the first card on top with up to two more
/// peeking out behind it and `+N more`. A tap on the stack or the header fans it out into the
/// full list; `Collapse` or the header folds it again. The flag lives with the caller, so a lazily
/// recycled row cannot forget it and the caller's own rule can drive it.
struct StackedCards<Item: Identifiable, Row: View>: View {
    let title: String
    /// The hand label beside the title.
    let summary: String
    /// A second hand label in clay, for a cost the section is about to charge.
    var badge: String?
    /// What VoiceOver says for the whole section, title included; the view adds the state.
    let accessibilityLabel: String
    let items: [Item]
    @Binding var expanded: Bool
    /// The card each slab behind the top one stands for.
    let fill: (Item) -> CardFill
    let row: (Item) -> Row

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .footnote) private var captionHeight: CGFloat = 18

    init(title: String, summary: String, badge: String? = nil, accessibilityLabel: String,
         items: [Item], expanded: Binding<Bool>,
         fill: @escaping (Item) -> CardFill = { _ in .surface },
         @ViewBuilder row: @escaping (Item) -> Row) {
        self.title = title
        self.summary = summary
        self.badge = badge
        self.accessibilityLabel = accessibilityLabel
        self.items = items
        _expanded = expanded
        self.fill = fill
        self.row = row
    }

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.8)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LR.Spacing.sectionGap) {
            header
            if expanded {
                VStack(spacing: LR.Spacing.gridGap) {
                    ForEach(items) { row($0) }
                    Button("Collapse", action: toggle)
                        .lr(.bodyStrong).foregroundStyle(LR.Color.cardInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .lrCard(.surface, radius: LR.Radius.row)
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            } else if let top = items.first {
                Button(action: toggle) { stack(top: top) }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityValue("collapsed")
                    .accessibilityHint("Shows every card")
                    .accessibilityAddTraits(.isButton)
                    .transition(.opacity)
            }
        }
    }

    /// Collapsed, the stack below speaks for the whole section, so the header is skipped rather
    /// than read twice.
    private var header: some View {
        Button(action: toggle) {
            // Stacked at accessibility sizes, so the title is never broken mid-word.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    headerTitle; Spacer(minLength: 8); headerLabels; chevron
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack { headerTitle; Spacer(minLength: 8); chevron }
                    FlowRow(spacing: 8) { headerLabels }
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("expanded")
        .accessibilityAddTraits(.isHeader)
        .accessibilityHint("Collapses the list")
        .accessibilityHidden(!expanded)
    }

    private var headerTitle: some View {
        Text(title).lr(.heading).foregroundStyle(LR.Color.ink)
    }

    @ViewBuilder private var headerLabels: some View {
        Text(summary).lr(.hand).foregroundStyle(LR.Color.accent)
        if let badge { Text(badge).lr(.hand).foregroundStyle(LR.Color.clay) }
    }

    /// The header sits on the canvas, so its chevron is the canvas's secondary ink.
    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(LR.Color.inkSecondary)
            .rotationEffect(.degrees(expanded ? 90 : 0))
    }

    /// The top card, and behind it the next two as slightly narrower slabs of the same colour faded
    /// toward the canvas, each a little lower. The bottom padding makes room for what sticks out.
    private func stack(top: Item) -> some View {
        let behind = Array(items.dropFirst().prefix(2))
        return row(top)
            .allowsHitTesting(false)
            .background(alignment: .top) {
                ForEach(Array(behind.enumerated()).reversed(), id: \.element.id) { index, item in
                    let depth = CGFloat(index + 1)
                    let card = fill(item)
                    RoundedRectangle(cornerRadius: LR.Radius.row, style: .continuous)
                        .fill(card.color)
                        .overlay {
                            RoundedRectangle(cornerRadius: LR.Radius.row, style: .continuous)
                                .fill(LR.Color.canvas.opacity(0.1 + 0.12 * depth))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: LR.Radius.row, style: .continuous)
                                .strokeBorder(card.tint == nil ? LR.Color.hairline : LR.Color.divider, lineWidth: 1)
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
