import SwiftUI

/// One thing a card's `⋯` popover, context menu and VoiceOver actions all offer. A swipe action has
/// no equivalent in a grid, so the same list is shown three ways. Whether it can go through is
/// Core's rule, decided by the caller: a blocked one is greyed out here, not hidden, so the price
/// stays visible in the popover, and is simply not offered to VoiceOver.
struct CardAction: Identifiable {
    let title: String
    let systemImage: String
    var isEnabled = true
    /// The popover's row title when `title` carries the price for the menu and VoiceOver
    /// ("Reroll · 30"); nil shows `title`.
    var label: String?
    /// The price pill at the popover row's trailing edge, shown on a blocked row too.
    var trailing: String?
    let run: () -> Void

    var id: String { title }
}

/// The trailing `⋯`, with a 44 pt hit target. A tap opens a small card popover; the long-press
/// context menu on the card itself stays the system one.
struct CardMenuButton: View {
    let actions: [CardAction]

    @Environment(\.lrTint) private var tint
    @State private var showing = false
    /// The row that was tapped, run once the popover has finished leaving: a sheet raised while it
    /// is still dismissing is dropped by UIKit.
    @State private var chosen: (() -> Void)?

    var body: some View {
        if !actions.isEmpty {
            Button { showing = true } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(tint.map(LR.Color.ink(on:)) ?? LR.Color.inkSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableCardStyle())
            .popover(isPresented: $showing) {
                CardPopoverList(actions: actions) { action in
                    chosen = action.run
                    showing = false
                }
                .presentationCompactAdaptation(.popover)
            }
            .onChange(of: showing) { _, isShowing in
                guard !isShowing, let run = chosen else { return }
                chosen = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    run()
                }
            }
            .accessibilityLabel("More actions")
        }
    }
}

/// The popover's card: a row per action with a neutral icon circle, a bold title and the price.
struct CardPopoverList: View {
    let actions: [CardAction]
    let pick: (CardAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                if index > 0 { Rectangle().fill(LR.Color.divider).frame(height: 1).padding(.leading, 52) }
                row(action)
            }
        }
        .padding(.vertical, 4)
        .frame(minWidth: 240)
        .presentationBackground(LR.Color.surface)
        .presentationCornerRadius(18)
    }

    private func row(_ action: CardAction) -> some View {
        Button { pick(action) } label: {
            HStack(spacing: 12) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(action.isEnabled ? LR.Color.ink : LR.Color.iconNeutral)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(LR.Color.pillFill))
                    .accessibilityHidden(true)
                Text(action.label ?? action.title).lr(.bodyStrong)
                    .foregroundStyle(action.isEnabled ? LR.Color.ink : LR.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let trailing = action.trailing {
                    PillLabel(text: trailing, style: .plain, dense: true)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled)
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
    let hint: String?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if !actions.isEmpty { CardActionButtons(actions: actions) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityHint(hint ?? "")
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
                     extra: [(title: String, run: () -> Void)] = [],
                     hint: String? = nil) -> some View {
        modifier(OneElementModifier(label: label, value: value, complete: complete,
                                    actions: actions, extra: extra, hint: hint))
    }
}

/// "+N" rises from a pill and fades over 0.6 s when `isDone` turns true. Under Reduce Motion
/// nothing moves: the pill itself changes to the paid amount.
private struct GainText: View {
    let text: String
    let rise: CGFloat
    let opacity: Double

    @Environment(\.lrTint) private var tint

    var body: some View {
        Text(text)
            .lr(.bodyStrong)
            .foregroundStyle(tint.map(LR.Color.ink(on:)) ?? LR.Color.ink)
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
    var color: Color?
    var lineLimit: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lrTint) private var tint

    var body: some View {
        let color = color ?? tint.map(LR.Color.ink(on:)) ?? LR.Color.ink
        Text(text)
            .lr(style)
            .strikethrough(isDone, color: color)
            .foregroundStyle(color)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.25), value: isDone)
    }
}
