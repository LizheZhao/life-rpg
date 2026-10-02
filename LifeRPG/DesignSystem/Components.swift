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

/// What a card is filled with: the neutral surface, or a pastel tile.
enum CardFill {
    case surface, tint(Color)

    var color: Color {
        switch self {
        case .surface: LR.Color.surface
        case .tint(let color): color
        }
    }
}

extension View {
    func lrCard(_ fill: CardFill = .surface, radius: CGFloat = LR.Radius.card) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill.color))
    }
}

struct PillLabel: View {
    /// `plain` sits on a white card or the canvas, `onTint` on a pastel tile; each has its own
    /// fill so the pill keeps a visible shape on both (`Palette.pillFill`, `Palette.pillVeil`).
    enum Style { case plain, onTint, clay }

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
        case .clay: LR.Color.clay
        }
    }

    private var background: Color {
        switch style {
        case .plain: LR.Color.pillFill
        case .onTint: LR.Color.pillVeil
        case .clay: LR.Color.clayBg
        }
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
    var fill: Color = LR.Color.fill
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
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (origins, CGSize(width: maxX, height: y + rowHeight))
    }
}
