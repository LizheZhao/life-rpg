import SwiftUI

/// One thing a card's `⋯` menu, context menu and VoiceOver actions all offer. A swipe action has
/// no equivalent in a grid, so the same list is shown three ways. Whether it can go through is
/// Core's rule, decided by the caller: a blocked one is greyed out here, not hidden, so the price
/// stays visible, and is simply not offered to VoiceOver.
struct CardAction: Identifiable {
    let title: String
    let systemImage: String
    var isEnabled = true
    let run: () -> Void

    var id: String { title }
}

/// The trailing `⋯`, with a 44 pt hit target.
struct CardMenuButton: View {
    let actions: [CardAction]
    var onDark = false
    /// Takes 32 pt of layout while keeping a 44 pt target, for a tight row.
    var compact = false
    /// The full text of a card whose title is cut short, shown at the top of the menu.
    var heading: String?

    var body: some View {
        if !actions.isEmpty {
            Menu {
                if let heading {
                    Section(heading) { CardActionButtons(actions: actions) }
                } else {
                    CardActionButtons(actions: actions)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(onDark ? LR.Color.epicSecondary : LR.Color.inkSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .padding(compact ? -6 : 0)
            }
            .accessibilityLabel("More actions")
        }
    }
}

struct CardActionButtons: View {
    let actions: [CardAction]

    var body: some View {
        ForEach(actions) { action in
            Button(action: action.run) { Label(action.title, systemImage: action.systemImage) }
                .disabled(!action.isEnabled)
        }
    }
}

private struct OneElementModifier: ViewModifier {
    let label: String
    let value: String
    let complete: (() -> Void)?
    let actions: [CardAction]
    let extra: [(title: String, run: () -> Void)]

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if !actions.isEmpty { CardActionButtons(actions: actions) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityActions {
                if let complete { Button("Complete", action: complete) }
                ForEach(actions.filter(\.isEnabled)) { action in
                    Button(action.title, action: action.run)
                }
                ForEach(extra.indices, id: \.self) { index in
                    Button(extra[index].title, action: extra[index].run)
                }
            }
    }
}

extension View {
    /// The whole card as one VoiceOver element, completion and the `⋯` menu as custom actions, the
    /// menu again as a context menu. `extra` are actions only VoiceOver needs (a link, a version
    /// switch, one tick of a group) because their visible control is inside the card.
    func cardElement(label: String, value: String,
                     complete: (() -> Void)?,
                     actions: [CardAction] = [],
                     extra: [(title: String, run: () -> Void)] = []) -> some View {
        modifier(OneElementModifier(label: label, value: value, complete: complete,
                                    actions: actions, extra: extra))
    }
}

/// "+N" rises from a pill and fades over 0.6 s when `isDone` turns true. Under Reduce Motion
/// nothing moves: the pill itself changes to the paid amount.
private struct GainText: View {
    let text: String
    let rise: CGFloat
    let opacity: Double

    var body: some View {
        Text(text)
            .lr(.bodyStrong)
            .foregroundStyle(LR.Color.ink)
            .fixedSize()
            .offset(y: rise)
            .opacity(opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct GainFloatModifier: ViewModifier {
    let text: String
    let isDone: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Frame {
        var rise: CGFloat = 0
        var opacity: Double = 0
    }

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.keyframeAnimator(initialValue: Frame(), trigger: isDone) { view, frame in
                view.overlay { GainText(text: text, rise: frame.rise, opacity: frame.opacity) }
            } keyframes: { _ in
                KeyframeTrack(\.rise) {
                    LinearKeyframe(0, duration: 0.001)
                    CubicKeyframe(-30, duration: 0.6)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.001)
                    LinearKeyframe(1, duration: 0.2)
                    LinearKeyframe(0, duration: 0.4)
                }
            }
        }
    }
}

extension View {
    func gainFloat(_ text: String, when isDone: Bool) -> some View {
        modifier(GainFloatModifier(text: text, isDone: isDone))
    }
}

/// Strikethrough that arrives with the completion instead of snapping in.
struct DoneTitle: View {
    let text: String
    let isDone: Bool
    var style: LR.Typography = .bodyStrong
    var color: Color = LR.Color.ink
    var lineLimit: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(text)
            .lr(style)
            .strikethrough(isDone, color: color)
            .foregroundStyle(color)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.25), value: isDone)
    }
}
