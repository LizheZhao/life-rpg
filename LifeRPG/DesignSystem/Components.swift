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

/// Every Caveat string goes through here, never `Text(...).lr(.hand...)` on its own.
///
/// Caveat's glyphs overhang their advance (the stroke of a `d`, the tail of a `6`, a `?`), and Text
/// clips what hangs past its measured width, so the last glyph loses a sliver. The string is
/// measured with an invisible full stop after it (a space is trimmed away, and the first attempt
/// with a thin space widened nothing), and an equal negative padding takes that width back out of
/// the layout, so the visible glyphs sit exactly where they did and right-aligned or centred text
/// does not move. `balanced` pads the leading side too, for centred values. VoiceOver reads the
/// original string, not the padding.
struct HandText: View {
    let string: String
    let style: LR.Typography
    var balanced = false
    /// A string that may need more than one line (a centred title). Everything else is one line at
    /// its own width: the padding trick above makes a Text in a tight spot (the payout band) lose
    /// its last digit to truncation otherwise.
    var wraps = false

    @Environment(\.dynamicTypeSize) private var dynamicType

    init(_ string: String, _ style: LR.Typography, balanced: Bool = false, wraps: Bool = false) {
        self.string = string
        self.style = style
        self.balanced = balanced
        self.wraps = wraps
    }

    /// The system full stop at the style's own size, in whatever the user's Dynamic Type makes of it (about a quarter of an em).
    private var padFont: UIFont { .systemFont(ofSize: style.pointSize(dynamicType: dynamicType)) }
    private var pad: CGFloat { ("." as NSString).size(withAttributes: [.font: padFont]).width }

    var body: some View {
        let mark = Text(verbatim: ".").font(Font(padFont as CTFont)).foregroundColor(.clear)
        let lead = balanced ? mark : Text(verbatim: "")
        Text("\(lead)\(Text(verbatim: string))\(mark)")
            .lr(style)
            .accessibilityLabel(string)
            .fixedSize(horizontal: !wraps, vertical: true)
            .padding(.leading, balanced ? -pad : 0)
            .padding(.trailing, -pad)
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

// MARK: - buttons

/// A full-width ink-filled pill, sized for the thumb (the Rewards empty state's `Add a reward`).
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

/// A compact filled ink capsule for the one action on a card or beside a field (`Redeem`, `Add
/// note`). Disabled it turns into the quiet pill, so a blocked action still reads as a button.
struct InkPillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lr(.bodyStrong)
            .foregroundStyle(isEnabled ? LR.Color.onFill : LR.Color.inkSecondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .background(Capsule().fill(isEnabled ? LR.Color.fill : LR.Color.pillFill).padding(.vertical, 2))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.8 : 1)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}

/// The one full-width ink pill at the bottom of the sheet.
struct ConfirmBar: View {
    let title: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).lr(.bodyStrong).foregroundStyle(LR.Color.onFill)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Capsule().fill(LR.Color.fill))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableCardStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(LR.Color.canvas)
    }
}

/// The library search rule, shared by every library picker: the query trimmed, then matched the way
/// the system's own search matches (case, diacritics and width ignored). An empty query keeps everything.
extension Sequence {
    func matching(_ query: String, text: (Element) -> String) -> [Element] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? Array(self) : filter { text($0).localizedStandardContains(query) }
    }
}

/// A search field in the card language: a magnifier, the app's text style, and a clear button once
/// there is something to clear. The keyboard's Search key puts the keyboard away.
struct LibrarySearchField: View {
    @Binding var text: String
    var prompt = "Search library"

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LR.Color.iconNeutral)
                .accessibilityHidden(true)
            TextField(prompt, text: $text, prompt: Text(prompt).foregroundStyle(LR.Color.inkSecondary))
                .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                .submitLabel(.search)
                .focused($focused)
                .onSubmit { focused = false }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .frame(minHeight: 44)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(LR.Color.iconNeutral)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, text.isEmpty ? 14 : 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard(.surface, radius: LR.Radius.row)
    }
}

/// Says which row is picked while the search hides it, so `Add` never looks like it acts on nothing.
struct SelectedHint: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(LR.Color.fill)
            Text(title).lr(.pill).foregroundStyle(LR.Color.ink).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(LR.Color.pillFill))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Selected, \(title), hidden by the search")
    }
}

/// Two to four options as a capsule with a sliding fill (the ratings window, Add's From library /
/// Custom). At accessibility sizes the options no longer fit in a row, so they wrap into two.
struct PillSegmentedControl<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value
    var accessibilityLabel: String

    @Namespace private var slider
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) { buttons }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)],
                      spacing: 0) { buttons }
        }
        .padding(4)
        .background(Capsule().fill(LR.Color.pillFill))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var buttons: some View {
        ForEach(Array(options.enumerated()), id: \.offset) { _, option in
            let selected = selection == option.value
            Button {
                guard !selected else { return }
                Haptics.selection()
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.8)) {
                    selection = option.value
                }
            } label: {
                Text(option.label)
                    .lr(.bodyStrong)
                    .foregroundStyle(selected ? LR.Color.onFill : LR.Color.ink)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .padding(.horizontal, 8)
                    .background {
                        if selected {
                            Capsule().fill(LR.Color.fill).matchedGeometryEffect(id: "selected", in: slider)
                        }
                    }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}
