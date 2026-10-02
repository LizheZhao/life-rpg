import SwiftUI
import UIKit

enum RootTab: CaseIterable, Identifiable {
    case today, calendar, rewards, settings

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .today: "Today"
        case .calendar: "Calendar"
        case .rewards: "Rewards"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .today: "checklist"
        case .calendar: "calendar"
        case .rewards: "gift"
        case .settings: "gearshape"
        }
    }
}

/// The app's tab bar: a neutral-card capsule floating above the bottom edge, four round buttons, the
/// selected one filled. The only shadow in the app (`doc/UI_DESIGN.md`).
///
/// Meant as the bottom overlay of a `TabView` whose system bar is hidden. Seen on the simulator:
/// a safe-area inset or safe-area padding outside a page's `NavigationStack` never reaches the
/// list inside it, so each scroll view reserves the space itself with `reservingTabBarSpace()`,
/// a content margin. Apply it to the scroll view, not to something that also presents sheets: the
/// margin is inherited by whatever the view presents. The bar hides while the keyboard is up (an overlay otherwise rides on top of it).
struct FloatingTabBar: View {
    @Binding var selection: RootTab

    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var keyboardShown = false

    private static let buttonSize: CGFloat = 56
    private static let bottomGap: CGFloat = 8

    /// What the bar takes from the bottom of the screen: the capsule and the gap under it.
    static let reservedHeight: CGFloat = buttonSize + 2 * 6 + bottomGap

    var body: some View {
        HStack(spacing: 4) {
            ForEach(RootTab.allCases) { tab in
                button(for: tab)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: LR.Radius.tabBar, style: .continuous)
            .fill(LR.Color.surface))
        // SwiftUI's radius is half of a design tool's blur, so blur 30 is radius 15.
        .shadow(color: .black.opacity(0.10), radius: 15, y: 10)
        .frame(maxWidth: .infinity)
        .padding(.bottom, Self.bottomGap)
        .opacity(keyboardShown ? 0 : 1)
        .allowsHitTesting(!keyboardShown)
        .accessibilityHidden(keyboardShown)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardShown = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardShown = false
        }
    }

    private func button(for tab: RootTab) -> some View {
        let selected = selection == tab
        return Button {
            select(tab)
        } label: {
            Image(systemName: tab.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(selected ? LR.Color.cardOnFill : LR.Color.cardInkSecondary)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background { indicatorCircle(selected: selected) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// One circle that slides between the buttons; with Reduce Motion each button fades its own
    /// circle in and out instead of anything moving.
    @ViewBuilder
    private func indicatorCircle(selected: Bool) -> some View {
        if reduceMotion {
            Circle().fill(LR.Color.cardFill).opacity(selected ? 1 : 0)
        } else if selected {
            Circle().fill(LR.Color.cardFill).matchedGeometryEffect(id: "selection", in: indicator)
        }
    }

    private func select(_ tab: RootTab) {
        guard tab != selection else { return }
        Haptics.selection()
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.2)
                                                : .spring(response: 0.35, dampingFraction: 0.8)
        withAnimation(animation) { selection = tab }
    }
}

extension View {
    /// Lets scroll content stop above the floating bar instead of running under it.
    func reservingTabBarSpace() -> some View {
        contentMargins(.bottom, FloatingTabBar.reservedHeight, for: .scrollContent)
            .contentMargins(.bottom, FloatingTabBar.reservedHeight, for: .scrollIndicators)
    }
}

#Preview("Light") {
    FloatingTabBar(selection: .constant(.calendar))
        .padding(.vertical, 40)
        .background(LR.Color.canvas)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    FloatingTabBar(selection: .constant(.today))
        .padding(.vertical, 40)
        .background(LR.Color.canvas)
        .preferredColorScheme(.dark)
}
