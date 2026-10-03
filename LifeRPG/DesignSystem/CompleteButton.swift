import LifeRPGCore
import SwiftUI

/// The filled disc and tick of a done mark. On the epic's dark umber the ink disc has an edge of
/// only about 2.2:1 in light, so the epic takes what is drawn on it (white, `ink(on: .epic)`, 7.1:1
/// in light and 5.3:1 in dark) with the dark on-tint ink for the tick. Every other tint keeps the
/// ink disc and the white tick.
enum DoneMark {
    static func fill(on tint: QuestTint?) -> Color { tint == .epic ? LR.Color.ink(on: .epic) : LR.Color.fill }
    static func check(on tint: QuestTint?) -> Color { tint == .epic ? LR.Color.ink(on: .routine) : LR.Color.onFill }
}

/// 44 x 44 open / done toggle. Completion is final (`PLAN.md` §3), so a done button does nothing:
/// there is no reverse animation to design. The tick draws on; with Reduce Motion it fades in.
///
/// `isDone` is the data, and the only thing that draws the check: a tap just calls `action`, which
/// on the Today page raises the confirmation. The medium haptic belongs to the confirmed
/// completion, not to the tap, so it is fired where the completion happens.
struct CompleteButton: View {
    let isDone: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lrTint) private var tint

    var body: some View {
        Button {
            guard !isDone else { return }
            action()
        } label: {
            ZStack {
                Circle().strokeBorder(tint.map(LR.Color.ink(on:)) ?? LR.Color.accent, lineWidth: 1.5)
                    .opacity(isDone ? 0 : 1)
                Circle().fill(DoneMark.fill(on: tint))
                    .opacity(isDone ? 1 : 0)
                HandCheck()
                    .trim(from: 0, to: isDone || reduceMotion ? 1 : 0)
                    .stroke(DoneMark.check(on: tint), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 20, height: 20)
                    .opacity(isDone ? 1 : 0)
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.25), value: isDone)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel(isDone ? "Done" : "Mark as done")
        .accessibilityAddTraits(isDone ? .isSelected : [])
    }
}
