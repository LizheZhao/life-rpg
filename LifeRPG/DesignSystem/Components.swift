import LifeRPGCore
import SwiftUI
import UIKit

/// Feedback for a finished action. System haptics already follow the user's own setting, and
/// Reduce Motion is about movement, so a completion still taps.
enum Haptics {
    @MainActor static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    @MainActor static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @MainActor static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

/// What a card is filled with: the neutral surface, a difficulty tint, or the clay error ground.
enum CardFill {
    case surface, tint(QuestTint), clayBg

    var color: Color {
        switch self {
        case .surface: LR.Color.surface
        case .tint(let tint): tint.color
        case .clayBg: LR.Color.clayBg
        }
    }

    /// The disc behind a doodle: the card's pill colour on a surface, the solid chip on a tint.
    var disc: Color {
        switch self {
        case .surface: LR.Color.cardPill
        case .clayBg: LR.Color.pillFill
        case .tint: LR.Color.chip
        }
    }

    /// The doodle's stroke on `disc`: the card's ink on a surface, the canvas ink on the chip.
    var doodleInk: Color {
        switch self {
        case .surface: LR.Color.cardInk
        case .clayBg, .tint: LR.Color.ink
        }
    }

    var tint: QuestTint? {
        if case .tint(let tint) = self { return tint }
        return nil
    }

}

private struct TintKey: EnvironmentKey {
    static let defaultValue: QuestTint? = nil
}

extension EnvironmentValues {
    /// The tint of the card this view sits on, nil on a surface. Titles, glyphs, captions and the
    /// `+N` float pick the colours that read on it without every call site saying so.
    var lrTint: QuestTint? {
        get { self[TintKey.self] }
        set { self[TintKey.self] = newValue }
    }
}

private struct CardBackground: ViewModifier {
    let fill: CardFill
    let radius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var shadowColor: Color {
        let shadow = Palette.shadow(colorScheme == .dark ? .dark : .light)
        guard fill.tint != nil else { return .black.opacity(shadow.surface) }
        return (shadow.tintedByCard ? fill.color : .black).opacity(shadow.tint)
    }

    func body(content: Content) -> some View {
        content.background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            shape.fill(fill.color)
                .overlay { if fill.tint == nil { shape.strokeBorder(LR.Color.hairline, lineWidth: 1) } }
                .shadow(color: shadowColor, radius: 16, x: 0, y: 6)
        }
    }
}

extension View {
    /// A card: its fill, a neutral card's 1 pt hairline, and the soft shadow (`Palette.shadow`).
    func lrCard(_ fill: CardFill = .surface, radius: CGFloat = LR.Radius.card) -> some View {
        modifier(CardBackground(fill: fill, radius: radius))
    }
}

struct PillLabel: View {
    /// `plain` sits on the canvas, `onCard` on a neutral card, `onTint` on a tinted row; each has
    /// its own fill so the pill keeps a visible shape on all three (`Palette.pillFill`,
    /// `Palette.cardPill`, `Palette.chip`).
    enum Style { case plain, onCard, onTint, clay }

    let text: String
    var style: Style = .plain
    /// Less padding, for a second line under a title.
    var dense = false

    var body: some View {
        Text(text)
            .lr(.pill)
            .foregroundStyle(foreground)
            .padding(.horizontal, dense ? 8 : 10)
            .padding(.vertical, dense ? 2 : 5)
            .background(RoundedRectangle(cornerRadius: LR.Radius.pill, style: .continuous).fill(background))
    }

    private var foreground: Color {
        switch style {
        case .plain, .onTint: LR.Color.ink
        case .onCard: LR.Color.cardInk
        case .clay: LR.Color.clay
        }
    }

    private var background: Color {
        switch style {
        case .plain: LR.Color.pillFill
        case .onCard: LR.Color.cardPill
        case .onTint: LR.Color.chip
        case .clay: LR.Color.clayBg
        }
    }
}

/// A capsule button ("Do now") on a neutral card: the card pill's fill and ink, a hairline edge,
/// and a 44 pt target taller than what is drawn.
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lr(.bodyStrong)
            .foregroundStyle(LR.Color.cardInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(LR.Color.cardPill))
            .overlay(Capsule().strokeBorder(LR.Color.cardInkSecondary.opacity(0.35), lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Scale 0.97 on press with a spring; Reduce Motion swaps the movement for a dim.
struct PressableCardStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.8 : 1)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}

/// Thin segments for a count (the epic's seven days). Decorative: the caller says the numbers.
struct SegmentedProgress: View {
    let filled: Int
    let total: Int
    var fill: Color = LR.Color.cardFill
    var track: Color = LR.Color.dotEmpty

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(total, 0), id: \.self) { index in
                Capsule()
                    .fill(index < filled ? fill : track)
                    .frame(height: 4)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Wraps its children onto new lines, so pills never truncate at large text sizes.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Take the whole offered width: a narrower answer would be wrapped again at that narrower
        // width when the children are placed, and the extra line would spill out of the card.
        let result = arrange(proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? result.size.width, height: result.size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(bounds.width, subviews)
        for (subview, origin) in zip(subviews, result.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                          proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            // Offered the row's width, so a pill wider than the row wraps its own text rather than
            // spilling over the card's edge.
            let size = subview.sizeThatFits(ProposedViewSize(width: width.isFinite ? width : nil, height: nil))
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (origins, CGSize(width: maxX, height: y + rowHeight))
    }
}
