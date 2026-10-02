import LifeRPGCore
import SwiftUI
import UIKit

/// The design tokens of `doc/UI_DESIGN.md`. Colours come from Core's `Palette`; nothing here
/// carries a hex literal of its own.
enum LR {
    enum Color {
        static let canvas = color(Palette.canvas)
        static let surface = color(Palette.surface)
        /// The 1 pt edge of a neutral card.
        static let hairline = color(Palette.hairline)
        static let divider = color(Palette.divider)
        static let ink = color(Palette.ink)
        static let inkSecondary = color(Palette.inkSecondary)
        /// Chevrons and decorative icons.
        static let iconNeutral = color(Palette.iconNeutral)
        /// Settings section headers only.
        static let sectionTitle = color(Palette.sectionTitle)
        /// The filled circle behind the selected tab icon.
        static let tabPill = color(Palette.tabPill)
        /// The Caveat hand labels and the ring of an open complete button.
        static let accent = color(Palette.accent)
        static let fill = color(Palette.fill)
        static let onFill = color(Palette.onFill)
        static let dotEmpty = color(Palette.dotEmpty)
        static let dotFill = color(Palette.dotFill)
        static let tintTrivial = color(Palette.tintTrivial)
        static let tintEasy = color(Palette.tintEasy)
        static let tintMedium = color(Palette.tintMedium)
        static let tintHard = color(Palette.tintHard)
        static let tintHidden = color(Palette.tintHidden)
        /// A tint at the opacity of the circle behind a Settings section icon.
        static func sectionCircle(_ tint: QuestTint) -> SwiftUI.Color {
            color(Palette.tint(tint)).opacity(Palette.sectionCircleOpacity)
        }
        static let clay = color(Palette.clay)
        static let clayBg = color(Palette.clayBg)
        static let avatarPink = color(Palette.avatarPink)
        /// A pill on a tinted row: a solid chip.
        static let chip = color(Palette.chip)
        static let pillFill = color(Palette.pillFill)

        /// What is drawn on a tint (title, caption, doodle, `⋯`, open ring): per tint.
        static func ink(on tint: QuestTint) -> SwiftUI.Color { color(Palette.ink(on: tint)) }

        /// A colour that re-resolves when the appearance changes, including inside a view that
        /// overrides it with `.environment(\.colorScheme, ...)`.
        static func color(_ token: Palette.Token) -> SwiftUI.Color {
            SwiftUI.Color(uiColor: UIColor { traits in
                uiColor(hex: token.value(traits.userInterfaceStyle == .dark ? .dark : .light))
            })
        }

        private static func uiColor(hex: Int) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255,
                    alpha: 1)
        }
    }

    /// All continuous corners.
    enum Radius {
        static let card: CGFloat = 28
        static let tile: CGFloat = 26
        static let row: CGFloat = 24
        static let pill: CGFloat = 12
        static let tabBar: CGFloat = 34
    }

    enum Spacing {
        static let inset: CGFloat = 22
        static let sectionGap: CGFloat = 14
        static let gridGap: CGFloat = 10
    }

    enum Typography: CaseIterable {
        case displayGreeting, displayGreetingEmphasis, displayLevel, levelInline
        case titleCard, heading, bodyStrong, caption, pill, hand, handTitle, handDisplay

        struct Spec {
            let family: LRFonts.Family
            let weight: CGFloat
            let size: CGFloat
            let textStyle: UIFont.TextStyle
            var maximumSize: CGFloat?
            var tracking: CGFloat = 0
        }

        var spec: Spec {
            switch self {
            case .displayGreeting:
                Spec(family: .jakarta, weight: 300, size: 32, textStyle: .largeTitle, maximumSize: 52, tracking: -0.5)
            case .displayGreetingEmphasis:
                Spec(family: .jakarta, weight: 800, size: 32, textStyle: .largeTitle, maximumSize: 52, tracking: -0.5)
            case .displayLevel:
                Spec(family: .jakarta, weight: 300, size: 52, textStyle: .largeTitle, maximumSize: 72, tracking: -2)
            case .levelInline:
                Spec(family: .jakarta, weight: 300, size: 34, textStyle: .largeTitle, maximumSize: 52, tracking: -1)
            case .titleCard:
                Spec(family: .jakarta, weight: 700, size: 22, textStyle: .title2)
            case .heading:
                Spec(family: .jakarta, weight: 700, size: 17, textStyle: .headline)
            case .bodyStrong:
                Spec(family: .jakarta, weight: 600, size: 15, textStyle: .body)
            case .caption:
                Spec(family: .jakarta, weight: 400, size: 13, textStyle: .footnote)
            case .pill:
                Spec(family: .jakarta, weight: 600, size: 12, textStyle: .caption1)
            case .hand:
                Spec(family: .caveat, weight: 500, size: 22, textStyle: .title3)
            case .handTitle:
                Spec(family: .caveat, weight: 600, size: 34, textStyle: .title1, maximumSize: 52)
            case .handDisplay:
                Spec(family: .caveat, weight: 600, size: 52, textStyle: .largeTitle, maximumSize: 72)
            }
        }

        /// Scaled for `dynamicType` by hand, because `UIFontMetrics` alone reads the process-wide
        /// category and would ignore a SwiftUI `.dynamicTypeSize` override (previews, the gallery).
        /// Bold Text raises the weight one step (100 on the axis).
        func font(dynamicType: DynamicTypeSize, boldText: Bool) -> Font {
            let spec = spec
            let traits = UITraitCollection(preferredContentSizeCategory: dynamicType.contentSizeCategory)
            var size = UIFontMetrics(forTextStyle: spec.textStyle).scaledValue(for: spec.size, compatibleWith: traits)
            if let cap = spec.maximumSize { size = min(size, cap) }
            let weight = spec.weight + (boldText ? 100 : 0)
            return Font(LRFonts.uiFont(spec.family, weight: weight, size: size) as CTFont)
        }

        var name: String {
            switch self {
            case .displayGreeting: "displayGreeting"
            case .displayGreetingEmphasis: "displayGreeting emphasis"
            case .displayLevel: "displayLevel"
            case .levelInline: "levelInline"
            case .titleCard: "titleCard"
            case .heading: "heading"
            case .bodyStrong: "bodyStrong"
            case .caption: "caption"
            case .pill: "pill"
            case .hand: "hand"
            case .handTitle: "handTitle"
            case .handDisplay: "handDisplay"
            }
        }
    }
}

private extension DynamicTypeSize {
    var contentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}

private struct LRTypographyModifier: ViewModifier {
    let style: LR.Typography
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.legibilityWeight) private var legibility

    func body(content: Content) -> some View {
        content
            .font(style.font(dynamicType: dynamicType, boldText: legibility == .bold))
            .tracking(style.spec.tracking)
    }
}

extension View {
    func lr(_ style: LR.Typography) -> some View {
        modifier(LRTypographyModifier(style: style))
    }
}
