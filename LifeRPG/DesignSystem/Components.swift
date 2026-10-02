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

    /// The disc behind a doodle: a darker neutral on a surface, the translucent pill veil on a tint.
    var disc: Color {
        switch self {
        case .surface, .clayBg: LR.Color.pillFill
        case .tint: LR.Color.chip
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

    /// A neutral card's shadow is tighter (radius 12, y 4) than a tinted row's (16, 6).
    private var shadowGeometry: (radius: CGFloat, y: CGFloat) { fill.tint == nil ? (12, 4) : (16, 6) }

    func body(content: Content) -> some View {
        content.background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            shape.fill(fill.color)
                .overlay { if fill.tint == nil { shape.strokeBorder(LR.Color.hairline, lineWidth: 1) } }
                .shadow(color: shadowColor, radius: shadowGeometry.radius, x: 0, y: shadowGeometry.y)
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
    /// `plain` sits on a white card or the canvas, `onTint` on a pastel tile; each has its own
    /// fill so the pill keeps a visible shape on both (`Palette.pillFill`, `Palette.chip`). `tint`
    /// fills the pill itself with a difficulty tint (a positive average on the ratings page).
    enum Style { case plain, onTint, clay, tint(QuestTint) }

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
        case .plain: LR.Color.ink
        case .onTint: LR.Color.ink
        case .clay: LR.Color.clay
        case .tint(let tint): LR.Color.ink(on: tint)
        }
    }

    private var background: Color {
        switch style {
        case .plain: LR.Color.pillFill
        case .onTint: LR.Color.chip
        case .clay: LR.Color.clayBg
        case .tint(let tint): tint.color
        }
    }
}

/// A light capsule button ("Do now"): the pill's fill and ink, a hairline edge, and a 44 pt target
/// taller than what is drawn.
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lr(.bodyStrong)
            .foregroundStyle(LR.Color.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(LR.Color.pillFill))
            .overlay(Capsule().strokeBorder(LR.Color.inkSecondary.opacity(0.35), lineWidth: 1))
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

// MARK: - sheets

/// One thing a bottom sheet answers: a full-width ink pill, with the payout it leads to when there
/// is one.
struct SheetChoice: Identifiable {
    let title: String
    var pill: String?
    /// Closes the sheet after the action, for a pill that only acknowledges. The ones that change
    /// something close it through the state they clear.
    var dismisses = false
    let action: () -> Void

    var id: String { title }
}

/// The full-width ink-filled pill at the foot of a sheet, sized for the thumb.
struct SheetPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lr(.heading)
            .foregroundStyle(LR.Color.onFill)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Capsule().fill(LR.Color.fill))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.8 : 1)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}

private struct SheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The frame every Today popup shares: the canvas, a drag indicator, 26 pt corners, and a detent
/// as tall as the content. The content scrolls once it outgrows the screen (accessibility sizes).
struct SheetFrame<Content: View>: View {
    @ViewBuilder let content: Content

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, LR.Spacing.inset)
                .padding(.top, 14)
                .padding(.bottom, 2)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: SheetHeightKey.self, value: proxy.size.height)
                    }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .onPreferenceChange(SheetHeightKey.self) { contentHeight = $0 }
        .presentationDetents([.height(contentHeight > 0 ? contentHeight : 360)])
        .presentationDragIndicator(.visible)
        .presentationBackground(LR.Color.canvas)
        .presentationCornerRadius(26)
    }
}

/// The popup language of the Today page: an optional hand-written title, the card the question is
/// about, a few secondary lines, one or two ink pills, and a quiet text button underneath.
struct ConfirmSheet: View {
    var title: String?
    var subject: SheetSubject?
    var notes: [String] = []
    let choices: [SheetChoice]
    /// The quiet way out under the pills; nil leaves only the pills.
    var quietTitle: String? = "Not yet"

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetFrame {
            VStack(alignment: .leading, spacing: 16) {
                if let title {
                    Text(title).lr(.handTitle).foregroundStyle(LR.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                if let subject { SheetSubjectRow(subject: subject) }
                if !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(notes, id: \.self) { note in
                            Text(note).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                VStack(spacing: 6) {
                    ForEach(choices) { choice in
                        Button {
                            choice.action()
                            if choice.dismisses { dismiss() }
                        } label: { choiceLabel(choice) }
                            .buttonStyle(SheetPrimaryButtonStyle())
                    }
                    if let quietTitle {
                        Button(quietTitle) { dismiss() }
                            .lr(.bodyStrong).foregroundStyle(LR.Color.inkSecondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func choiceLabel(_ choice: SheetChoice) -> some View {
        HStack(spacing: 10) {
            Text(choice.title)
            if let pill = choice.pill {
                Text(pill).lr(.pill)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(LR.Color.onFill.opacity(0.2)))
            }
        }
    }
}
