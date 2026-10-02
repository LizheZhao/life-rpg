import Foundation

/// The colour tokens of `doc/UI_DESIGN.md`, as hex ints so the contrast bar can be a test. The
/// canvas and the five tints are the user's palette sheet (`diary_palette.xlsx`), light and dark.
/// A neutral card is the opposite polarity of the page in both appearances (dark on the light page,
/// light on the dark one), so what is drawn on the canvas and what is drawn on a card are separate
/// tokens: `ink`, `inkSecondary`, `accent` for the canvas, the `card…` ones for a card. The app
/// wraps each in a dynamic `Color`; a view never contains a hex literal of its own.
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

    // MARK: canvas

    /// The page behind everything.
    public static let canvas = Token(light: 0xFBFBF8, dark: 0x14141A)
    /// Ruled lines on the canvas: the outline of a tinted slab peeking out of a stack.
    public static let divider = Token(light: 0xE9EBE5, dark: 0x2B2A35)
    /// Text and doodles drawn on the canvas: the greeting, section titles, `Collapse`.
    public static let ink = Token(light: 0x25232F, dark: 0xE6E4EC)
    public static let inkSecondary = Token(light: 0x6A6877, dark: 0xB1AFBD)
    /// The Caveat hand labels on the canvas. Large text, so held to 3:1 (`largeTextBar`): light is
    /// 3.96 on the canvas, dark 8.08.
    public static let accent = Token(light: 0x4682B4, dark: 0x8FB0CC)
    /// The filled done check on a tinted row (`fill`) and the check drawn on it (`onFill`).
    public static let fill = Token(light: 0x25232F, dark: 0xE6E4EC)
    public static let onFill = Token(light: 0xFFFFFF, dark: 0x14141A)
    /// A pill on the canvas, darker than it so it keeps its edge there.
    public static let pillFill = Token(light: 0xEEEFEA, dark: 0x2E2D38)

    // MARK: neutral card (inverted against the page)

    /// A neutral card, a row, the tab bar: dark on the light page, light on the dark one.
    public static let surface = Token(light: 0x25232F, dark: 0xEEEFE9)
    /// The 1 pt edge of a neutral card.
    public static let hairline = Token(light: 0x34323F, dark: 0xDCDDD6)
    public static let cardInk = Token(light: 0xE6E4EC, dark: 0x25232F)
    public static let cardInkSecondary = Token(light: 0xA9A7B6, dark: 0x6A6877)
    /// The ring of an open complete button and a card's chevrons.
    public static let cardAccent = Token(light: 0x8FB0CC, dark: 0x4682B4)
    /// The filled done check on a neutral card, and the selected tab circle; `cardOnFill` is the
    /// check drawn on it, which is the card's own colour.
    public static let cardFill = cardInk
    public static let cardOnFill = surface
    /// A pill and the doodle disc on a neutral card.
    public static let cardPill = Token(light: 0x34323F, dark: 0xE1E2DB)
    /// Ruled lines between the rows of a card list (Settings).
    public static let cardDivider = Token(light: 0x464456, dark: 0xD9DAD3)
    /// Overdue and a negative balance on a neutral card: the other appearance's `clay`.
    public static let cardClay = Token(light: 0xE8A183, dark: 0x9C472A)
    /// The empty and the filled dots of the level grid, the epic's week and the goal bar. All sit
    /// on a neutral card. The filled dot is the sage in light and a deeper sage in dark, so it is
    /// 3:1 against a light card.
    public static let dotEmpty = Token(light: 0x3A3847, dark: 0xD9DAD3)
    public static let dotFill = Token(light: 0x9CAF88, dark: 0x65785A)

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
        ("canvas", canvas), ("divider", divider),
        ("ink", ink), ("inkSecondary", inkSecondary), ("accent", accent),
        ("fill", fill), ("onFill", onFill), ("pillFill", pillFill),
        ("surface", surface), ("hairline", hairline), ("cardInk", cardInk),
        ("cardInkSecondary", cardInkSecondary), ("cardAccent", cardAccent), ("cardFill", cardFill),
        ("cardOnFill", cardOnFill), ("cardPill", cardPill), ("cardDivider", cardDivider),
        ("cardClay", cardClay), ("dotEmpty", dotEmpty), ("dotFill", dotFill),
        ("tintTrivial", tintTrivial), ("tintEasy", tintEasy), ("tintMedium", tintMedium),
        ("tintHard", tintHard), ("tintHidden", tintHidden),
        ("onTintDark", onTintDark), ("onTintWhite", onTintWhite),
        ("chip", chip),
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
        pairs.append(TextPair(label: "ink on canvas", foreground: v(ink), background: v(canvas)))
        pairs.append(TextPair(label: "inkSecondary on canvas", foreground: v(inkSecondary), background: v(canvas)))
        pairs.append(TextPair(label: "clay on canvas", foreground: v(clay), background: v(canvas)))
        pairs.append(TextPair(label: "cardInk on surface", foreground: v(cardInk), background: v(surface)))
        pairs.append(TextPair(label: "cardInkSecondary on surface", foreground: v(cardInkSecondary), background: v(surface)))
        pairs.append(TextPair(label: "cardClay on surface", foreground: v(cardClay), background: v(surface)))
        pairs.append(TextPair(label: "cardInk on cardPill", foreground: v(cardInk), background: v(cardPill)))
        pairs.append(TextPair(label: "cardOnFill on cardFill", foreground: v(cardOnFill), background: v(cardFill)))
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
        [TextPair(label: "accent on canvas", foreground: accent.value(appearance), background: canvas.value(appearance))]
    }

    /// Drawn shapes that carry meaning (the open ring, a done circle, a filled dot against an empty
    /// one) are held to 3:1, the WCAG bar for UI components.
    public static let nonTextBar = 3.0

    public static func nonTextPairs(_ appearance: Appearance) -> [TextPair] {
        func v(_ token: Token) -> Int { token.value(appearance) }
        return [
            TextPair(label: "cardAccent ring on surface", foreground: v(cardAccent), background: v(surface)),
            TextPair(label: "cardFill on surface", foreground: v(cardFill), background: v(surface)),
            TextPair(label: "dotFill on surface", foreground: v(dotFill), background: v(surface)),
            TextPair(label: "dotFill on dotEmpty", foreground: v(dotFill), background: v(dotEmpty)),
            TextPair(label: "cardFill on dotEmpty", foreground: v(cardFill), background: v(dotEmpty)),
        ]
    }

    // MARK: shadows

    /// A soft drop shadow under cards (radius 16, y 6). Light: soft black under a neutral (dark)
    /// card and the row's own colour under a tinted one. Dark: a very faint black under a neutral
    /// (light) card and plain black under a tinted one. The one exception to "only the tab bar has
    /// a shadow".
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
        case .light: CardShadow(surface: 0.14, tint: 0.22, tintedByCard: true)
        case .dark: CardShadow(surface: 0.1, tint: 0.4, tintedByCard: false)
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
