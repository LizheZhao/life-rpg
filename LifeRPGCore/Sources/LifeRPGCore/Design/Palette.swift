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
    /// A neutral card, a row, the tab bar. One step off the page in both appearances (1.04:1 in
    /// light, 1.17:1 in dark), so text and the tinted rows carry the contrast, not a black or white
    /// block.
    public static let surface = Token(light: 0xFFFFFF, dark: 0x23222C)
    /// The 1 pt edge of a neutral card and of the tab bar.
    public static let hairline = Token(light: 0xECECE6, dark: 0x2F2E3A)
    /// The ruled lines between rows and under stacked cards.
    public static let divider = Token(light: 0xECECE6, dark: 0x34323F)
    public static let ink = Token(light: 0x25232F, dark: 0xE8E6EE)
    public static let inkSecondary = Token(light: 0x6A6877, dark: 0xB1AFBD)
    /// Chevrons and decorative icons: not text, so held to the 3:1 non-text bar on a card and on
    /// the tab pill.
    public static let iconNeutral = Token(light: 0x6E6C7A, dark: 0x8A8896)
    /// Settings section headers only (17 pt, weight 700, so large text). Dark clears 4.5; light is
    /// 4.32 on a card and 4.17 on the page, kept as the sheet has it and listed as below AA.
    public static let sectionTitle = Token(light: 0x7A7886, dark: 0x9C9AA8)
    /// The filled circle behind the selected tab icon.
    public static let tabPill = Token(light: 0xE9E7F2, dark: 0x3A3848)
    /// The Caveat hand labels and the ring of an open complete button. Large text, so held to 3:1
    /// (`largeTextBar`): light is 3.96 on the canvas, dark 8.08.
    public static let accent = Token(light: 0x4682B4, dark: 0x8FB0CC)
    public static let fill = Token(light: 0x25232F, dark: 0xE8E6EE)
    public static let onFill = Token(light: 0xFFFFFF, dark: 0x14141A)
    public static let dotEmpty = Token(light: 0xDDDED9, dark: 0x34333F)
    public static let dotFill = Token(light: 0x9CAF88, dark: 0x86987A)

    // MARK: tints (trivial, easy, medium, hard, hidden, routine, epic)

    public static let tintTrivial = Token(light: 0x9CAF88, dark: 0x86987A)   // sage
    public static let tintEasy = Token(light: 0x4682B4, dark: 0x3F76A5)      // steel blue
    public static let tintMedium = Token(light: 0xFFBF00, dark: 0xD8A645)    // amber
    public static let tintHard = Token(light: 0xC8465A, dark: 0xB84A60)      // crimson
    public static let tintHidden = Token(light: 0x8A7BB3, dark: 0x7A6CA8)    // dusk violet
    /// Routine rows: the light beige grey (the user's own pick).
    public static let tintRoutine = Token(light: 0xC9C4BB, dark: 0xB9B4AB)
    /// The weekly epic: the dark umber (the user's own pick).
    public static let tintEpic = Token(light: 0x5D5750, dark: 0x716B63)

    /// Title, caption, `⋯` and open ring on amber, sage and the routine beige.
    public static let onTintDark = Token(light: 0x25232F, dark: 0x1B1A22)
    /// The same on steel blue, crimson, violet and the epic umber: white in both appearances.
    public static let onTintWhite = Token(light: 0xFFFFFF, dark: 0xFFFFFF)

    /// A pill on a tinted row: a solid chip, so the range or `+N` keeps its shape on every tint.
    public static let chip = Token(light: 0xFFFFFF, dark: 0x14141A)
    /// A pill on a neutral card or the canvas: darker than either, so it keeps its edge there.
    public static let pillFill = Token(light: 0xEEEFEA, dark: 0x2E2D38)

    /// Overdue and negative balance. Never an alarm red.
    public static let clay = Token(light: 0x9C472A, dark: 0xE8A183)
    public static let clayBg = Token(light: 0xF3DDD2, dark: 0x4A2E22)
    public static let avatarPink = Token(light: 0xF7C6D4, dark: 0x6B3F4C)

    /// How much of its tint the circle behind a Settings section icon carries.
    public static let sectionCircleOpacity = 0.18

    public static func tint(_ tint: QuestTint) -> Token {
        switch tint {
        case .trivial: tintTrivial
        case .easy: tintEasy
        case .medium: tintMedium
        case .hard: tintHard
        case .hidden: tintHidden
        case .routine: tintRoutine
        case .epic: tintEpic
        }
    }

    /// What is drawn on a tint, per tint: dark on the light amber, sage and routine beige, white on
    /// the rest (the sheet's rule, extended to the two warm greys by their measured contrast). One
    /// colour serves the title, the caption and the glyphs.
    public static func ink(on tint: QuestTint) -> Token {
        switch tint {
        case .trivial, .medium, .routine: onTintDark
        case .easy, .hard, .hidden, .epic: onTintWhite
        }
    }

    /// Every token by name, in the order the gallery lists them.
    public static let tokens: [(name: String, token: Token)] = [
        ("canvas", canvas), ("surface", surface), ("hairline", hairline), ("divider", divider),
        ("ink", ink), ("inkSecondary", inkSecondary), ("iconNeutral", iconNeutral),
        ("sectionTitle", sectionTitle), ("tabPill", tabPill), ("accent", accent),
        ("fill", fill), ("onFill", onFill), ("dotEmpty", dotEmpty), ("dotFill", dotFill),
        ("tintTrivial", tintTrivial), ("tintEasy", tintEasy), ("tintMedium", tintMedium),
        ("tintHard", tintHard), ("tintHidden", tintHidden),
        ("tintRoutine", tintRoutine), ("tintEpic", tintEpic),
        ("onTintDark", onTintDark), ("onTintWhite", onTintWhite),
        ("chip", chip), ("pillFill", pillFill),
        ("clay", clay), ("clayBg", clayBg), ("avatarPink", avatarPink),
    ]

    /// Every tint in the order the gallery lists them (the order of `QuestTint.allCases`).
    public static let tints: [(name: String, tint: QuestTint, token: Token)] = [
        ("tintTrivial", .trivial, tintTrivial), ("tintEasy", .easy, tintEasy),
        ("tintMedium", .medium, tintMedium), ("tintHard", .hard, tintHard),
        ("tintHidden", .hidden, tintHidden), ("tintRoutine", .routine, tintRoutine),
        ("tintEpic", .epic, tintEpic),
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

    /// Settings section headers: large text, so the 3:1 bar. Light is under 4.5 on purpose (see
    /// `sectionTitle`).
    public static func sectionTitlePairs(_ appearance: Appearance) -> [TextPair] {
        func v(_ token: Token) -> Int { token.value(appearance) }
        return [TextPair(label: "sectionTitle on canvas", foreground: v(sectionTitle), background: v(canvas)),
                TextPair(label: "sectionTitle on surface", foreground: v(sectionTitle), background: v(surface))]
    }

    /// Chevrons and icons, held to the 3:1 non-text bar: iconNeutral on the card, on the tab pill,
    /// and on each tint's 18% circle; the selected tab icon (ink) on the pill.
    public static func iconPairs(_ appearance: Appearance) -> [TextPair] {
        func v(_ token: Token) -> Int { token.value(appearance) }
        var pairs = [
            TextPair(label: "iconNeutral on surface", foreground: v(iconNeutral), background: v(surface)),
            TextPair(label: "iconNeutral on tabPill", foreground: v(iconNeutral), background: v(tabPill)),
            TextPair(label: "ink on tabPill", foreground: v(ink), background: v(tabPill)),
        ]
        for (name, _, token) in tints {
            let circle = blend(v(token), over: v(surface), alpha: sectionCircleOpacity)
            pairs.append(TextPair(label: "iconNeutral on \(name) circle", foreground: v(iconNeutral), background: circle))
        }
        return pairs
    }

    public static func largeTextPairs(_ appearance: Appearance) -> [TextPair] {
        [TextPair(label: "accent on canvas", foreground: accent.value(appearance), background: canvas.value(appearance)),
         TextPair(label: "accent on surface", foreground: accent.value(appearance), background: surface.value(appearance))]
    }

    // MARK: shadows

    /// A soft drop shadow under cards. A neutral card: radius 12, y 4, 5.5% black in light and none
    /// in dark (its hairline is the edge). A tinted row: radius 16, y 6, its own colour at 22% in
    /// light and plain black at 40% in dark.
    public struct CardShadow: Equatable, Sendable {
        /// Opacity under a neutral card; zero means no shadow.
        public let surface: Double
        /// Opacity under a tinted row.
        public let tint: Double
        /// Whether a tinted row's shadow is its own colour (light) or plain black (dark).
        public let tintedByCard: Bool
    }

    public static func shadow(_ appearance: Appearance) -> CardShadow {
        switch appearance {
        case .light: CardShadow(surface: 0.055, tint: 0.22, tintedByCard: true)
        case .dark: CardShadow(surface: 0, tint: 0.4, tintedByCard: false)
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
