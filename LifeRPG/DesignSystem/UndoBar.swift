import SwiftUI

/// A short-lived line above the floating tab bar: what just happened, and one tap to take it back.
/// The page that shows it decides how long it stays.
struct UndoBar: View {
    let message: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message).lr(.bodyStrong).foregroundStyle(LR.Color.onFill)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Undo", action: undo)
                .lr(.bodyStrong).foregroundStyle(LR.Color.onFill)
                .underline()
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .background(Capsule().fill(LR.Color.fill))
        .padding(.horizontal, 16)
        .padding(.bottom, FloatingTabBar.reservedHeight)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Undo", undo)
    }
}
