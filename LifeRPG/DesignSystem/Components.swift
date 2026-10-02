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
    case surface, tint(Color), epic

    var color: Color {
        switch self {
        case .surface: LR.Color.surface
        case .tint(let color): color
        case .epic: LR.Color.epic
        }
    }
}

extension View {
    func lrCard(_ fill: CardFill = .surface, radius: CGFloat = LR.Radius.card) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill.color))
    }
}

struct PillLabel: View {
    enum Style { case plain, onTint, clay, onEpic }

    let text: String
    var style: Style = .plain

    var body: some View {
        Text(text)
            .lr(.pill)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: LR.Radius.pill, style: .continuous).fill(background))
    }

    // On a tile the pill is a translucent surface, so it stays legible in either appearance
    // without a token per tint.
    private var foreground: Color {
        switch style {
        case .plain: LR.Color.inkSecondary
        case .onTint: LR.Color.ink
        case .clay: LR.Color.clay
        case .onEpic: LR.Color.onEpic
        }
    }

    private var background: Color {
        switch style {
        case .plain: LR.Color.canvas
        case .onTint: LR.Color.surface.opacity(0.6)
        case .clay: LR.Color.clayBg
        case .onEpic: LR.Color.epicTrack
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
    var fill: Color = LR.Color.onEpic
    var track: Color = LR.Color.epicTrack

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
