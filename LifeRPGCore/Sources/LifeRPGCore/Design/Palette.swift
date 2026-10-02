import Foundation

/// The colour tokens of `doc/UI_DESIGN.md`, as hex ints so the contrast bar can be a test. The
/// values are the user's palette sheet (`diary_palette.xlsx`), light and dark. The app wraps each in
/// a dynamic `Color`; a view never contains a hex literal of its own.
public enum Palette {
    public enum Appearance: CaseIterable, Sendable { case light, dark }

    public struct Token: Hashable, Sendable {
        public let light: Int
        public let dark: Int

        public init(light: Int, dark: Int) {
            self.light = light
            self.dark = dark
        }

        public func value(_ appearance: Appearance) -> Int {
            appearance == .light ? light : dark
        }
    }

    // MARK: neutrals

    /// The page behind everything.
    public static let canvas = Token(light: 0xFBFBF8, dark: 0x14141A)
    /// A neutral card, a row, the tab bar.
    public static let surface = Token(light: 0xFFFFFF, dark: 0x1D1C25)
    /// The 1 pt edge of a neutral card. In dark the card is only about 1.09:1 above the page, so
    /// this edge, not a luminance step, is what separates them.
    public static let hairline = Token(light: 0xEEEFE9, dark: 0x272631)
    /// The ruled lines between rows and under stacked cards.
    public static let divider = Token(light: 0xE9EBE5, dark: 0x2B2A35)
    public static let ink = Token(light: 0x25232F, dark: 0xE6E4EC)
    public static let inkSecondary = Token(light: 0x6A6877, dark: 0xB1AFBD)
    /// The Caveat hand labels and the ring of an open complete button. Large text, so held to 3:1
    /// (`largeTextBar`): light is 3.96 on the canvas, dark 8.08.
    public static let accent = Token(light: 0x4682B4, dark: 0x8FB0CC)
    public static let fill = Token(light: 0x25232F, dark: 0xE6E4EC)
    public static let onFill = Token(light: 0xFFFFFF, dark: 0x14141A)
    public static let dotEmpty = Token(light: 0xDDDED9, dark: 0x34333F)
    public static let dotFill = Token(light: 0x9CAF88, dark: 0x86987A)

    // MARK: tints (trivial, easy, medium, hard, hidden)

    public static let tintTrivial = Token(light: 0x9CAF88, dark: 0x86987A)   // sage
    public static let tintEasy = Token(light: 0x4682B4, dark: 0x3F76A5)      // steel blue
    public static let tintMedium = Token(light: 0xFFBF00, dark: 0xD8A645)    // amber
    public static let tintHard = Token(light: 0xC8465A, dark: 0xB84A60)      // crimson
    public static let tintHidden = Token(light: 0x8A7BB3, dark: 0x7A6CA8)    // dusk violet

    /// Title, caption, doodle, `⋯` and open ring on amber and sage.
    public static let onTintDark = Token(light: 0x25232F, dark: 0x1B1A22)
    /// The same on steel blue, crimson and violet: white in both appearances.
    public static let onTintWhite = Token(light: 0xFFFFFF, dark: 0xFFFFFF)

    /// A pill on a tinted row: a solid chip, so the range or `+N` keeps its shape on every tint.
    public static let chip = Token(light: 0xFFFFFF, dark: 0x14141A)
    /// A pill on a neutral card or the canvas: darker than either, so it keeps its edge there.
    public static let pillFill = Token(light: 0xEEEFEA, dark: 0x2E2D38)

    /// Overdue and negative balance. Never an alarm red.
    public static let clay = Token(light: 0x9C472A, dark: 0xE8A183)
    public static let clayBg = Token(light: 0xF3DDD2, dark: 0x4A2E22)
    public static let avatarPink = Token(light: 0xF7C6D4, dark: 0x6B3F4C)

    public static func tint(_ tint: QuestTint) -> Token {
        switch tint {
        case .trivial: tintTrivial
        case .easy: tintEasy
        case .medium: tintMedium
        case .hard: tintHard
        case .hidden: tintHidden
        }
    }

    /// What is drawn on a tint, per tint: dark on the light amber and sage, white on the rest (the
    /// sheet's rule). One colour serves the title, the caption, the doodle and the glyphs.
    public static func ink(on tint: QuestTint) -> Token {
        switch tint {
        case .trivial, .medium: onTintDark
        case .easy, .hard, .hidden: onTintWhite
        }
    }

    /// Every token by name, in the order the gallery lists them.
    public static let tokens: [(name: String, token: Token)] = [
        ("canvas", canvas), ("surface", surface), ("hairline", hairline), ("divider", divider),
        ("ink", ink), ("inkSecondary", inkSecondary), ("accent", accent),
        ("fill", fill), ("onFill", onFill), ("dotEmpty", dotEmpty), ("dotFill", dotFill),
        ("tintTrivial", tintTrivial), ("tintEasy", tintEasy), ("tintMedium", tintMedium),
        ("tintHard", tintHard), ("tintHidden", tintHidden),
        ("onTintDark", onTintDark), ("onTintWhite", onTintWhite),
        ("chip", chip), ("pillFill", pillFill),
        ("clay", clay), ("clayBg", clayBg), ("avatarPink", avatarPink),
    ]

    /// The five tints in the order the gallery lists them.
    public static let tints: [(name: String, tint: QuestTint, token: Token)] = [
        ("tintTrivial", .trivial, tintTrivial), ("tintEasy", .easy, tintEasy),
        ("tintMedium", .medium, tintMedium), ("tintHard", .hard, tintHard),
        ("tintHidden", .hidden, tintHidden),
    ]

    // MARK: contrast

    /// A foreground that carries text over a background.
    public struct TextPair: Sendable {
        public let label: String
        public let foreground: Int
        public let background: Int
    }

    /// Body text: held to 4.5:1 in each appearance (with `knownBelowAA` named in the tests as the
    /// only way out).
    public static func textPairs(_ appearance: Appearance) -> [TextPair] {
        func v(_ token: Token) -> Int { token.value(appearance) }
        var pairs: [TextPair] = []
        for (name, ground) in [("canvas", canvas), ("surface", surface)] {
            pairs.append(TextPair(label: "ink on \(name)", foreground: v(ink), background: v(ground)))
            pairs.append(TextPair(label: "inkSecondary on \(name)", foreground: v(inkSecondary), background: v(ground)))
            pairs.append(TextPair(label: "clay on \(name)", foreground: v(clay), background: v(ground)))
        }
        for (name, kind, token) in tints {
            pairs.append(TextPair(label: "ink on \(name)", foreground: v(ink(on: kind)), background: v(token)))
        }
        pairs.append(TextPair(label: "ink on chip", foreground: v(ink), background: v(chip)))
        pairs.append(TextPair(label: "ink on pillFill", foreground: v(ink), background: v(pillFill)))
        pairs.append(TextPair(label: "clay on clayBg", foreground: v(clay), background: v(clayBg)))
        pairs.append(TextPair(label: "onFill on fill", foreground: v(onFill), background: v(fill)))
        return pairs
    }

    /// Caveat 22 pt labels are large text, held to 3:1 rather than 4.5.
    public static let largeTextBar = 3.0

    public static func largeTextPairs(_ appearance: Appearance) -> [TextPair] {
        [TextPair(label: "accent on canvas", foreground: accent.value(appearance), background: canvas.value(appearance)),
         TextPair(label: "accent on surface", foreground: accent.value(appearance), background: surface.value(appearance))]
    }

    // MARK: shadows

    /// A soft drop shadow under cards (radius 16, y 6). Light: faint black under a neutral card and
    /// the row's own colour under a tinted one. Dark: plain black. The one exception to "only the
    /// tab bar has a shadow".
    public struct CardShadow: Equatable, Sendable {
        /// Opacity under a neutral card.
        public let surface: Double
        /// Opacity under a tinted row.
        public let tint: Double
        /// Whether a tinted row's shadow is its own colour (light) or plain black (dark).
        public let tintedByCard: Bool
    }

    public static func shadow(_ appearance: Appearance) -> CardShadow {
        switch appearance {
        case .light: CardShadow(surface: 0.07, tint: 0.22, tintedByCard: true)
        case .dark: CardShadow(surface: 0.4, tint: 0.4, tintedByCard: false)
        }
    }

    /// `foreground` painted over `background` at `alpha`, channel by channel, rounded.
    public static func blend(_ foreground: Int, over background: Int, alpha: Double) -> Int {
        func channel(_ shift: Int) -> Int {
            let f = Double((foreground >> shift) & 0xFF), b = Double((background >> shift) & 0xFF)
            return Int((f * alpha + b * (1 - alpha)).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }

    /// WCAG 2.x contrast ratio, 1...21, symmetric in its arguments.
    public static func contrast(_ a: Int, _ b: Int) -> Double {
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }

    static func luminance(_ hex: Int) -> Double {
        func channel(_ shift: Int) -> Double {
            let c = Double((hex >> shift) & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }
}
