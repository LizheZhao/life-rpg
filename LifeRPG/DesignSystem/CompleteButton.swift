import SwiftUI

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

    var body: some View {
        Button {
            guard !isDone else { return }
            action()
        } label: {
            ZStack {
                Circle().strokeBorder(LR.Color.inkSecondary, lineWidth: 1.5)
                    .opacity(isDone ? 0 : 1)
                Circle().fill(LR.Color.fill)
                    .opacity(isDone ? 1 : 0)
                HandCheck()
                    .trim(from: 0, to: isDone || reduceMotion ? 1 : 0)
                    .stroke(LR.Color.onFill, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
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
