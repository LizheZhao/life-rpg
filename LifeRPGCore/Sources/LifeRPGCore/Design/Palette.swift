import Foundation

/// The colour tokens of `doc/UI_DESIGN.md`, as hex ints so the contrast bar can be a test.
/// The app wraps each in a dynamic `Color`; a view never contains a hex literal of its own.
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

    public static let canvas = Token(light: 0xF6F3F1, dark: 0x151517)
    public static let surface = Token(light: 0xFFFFFF, dark: 0x212125)
    public static let ink = Token(light: 0x18181B, dark: 0xF4F1EE)
    public static let inkSecondary = Token(light: 0x6B6B73, dark: 0xA5A5AD)
    /// Secondary text on a pastel tile: `inkSecondary` is only ~4.2:1 on the sky tile.
    public static let inkOnTint = Token(light: 0x3F3F46, dark: 0xD8D5D1)
    public static let inkHand = Token(light: 0x55555D, dark: 0xB8B8C0)
    public static let fill = Token(light: 0x18181B, dark: 0xF4F1EE)
    public static let onFill = Token(light: 0xFFFFFF, dark: 0x151517)
    public static let dotEmpty = Token(light: 0xDAD5D0, dark: 0x3A3A40)
    public static let dotFill = Token(light: 0x8ED1B4, dark: 0x7CC4A6)
    public static let tintTrivial = Token(light: 0xBFE8D6, dark: 0x2F4A3F)
    public static let tintEasy = Token(light: 0xB9E3F4, dark: 0x2C4655)
    public static let tintMedium = Token(light: 0xF4E29A, dark: 0x55482A)
    public static let tintHard = Token(light: 0xF7D9DE, dark: 0x573640)
    public static let tintHidden = Token(light: 0xD4D6FF, dark: 0x3A3C5E)
    /// Overdue and negative balance. Never an alarm red. Light is darker than the proposal in
    /// `UI_DESIGN.md` (#A8502F was 4.17:1 on `clayBg`).
    public static let clay = Token(light: 0x9C472A, dark: 0xE8A183)
    public static let clayBg = Token(light: 0xF3DDD2, dark: 0x4A2E22)
    public static let avatarPink = Token(light: 0xF7C6D4, dark: 0x6B3F4C)

    /// A pill on a white card or on the canvas: darker than either, so it keeps its edge there.
    public static let pillFill = Token(light: 0xECE8E4, dark: 0x34343A)
    /// A pill on a pastel tile is this colour laid over the tile at `pillVeilAlpha`, so one token
    /// serves all five tints; `pillOnTint(over:_:)` is the blend the contrast tests check.
    public static let pillVeil = Token(light: 0xFFFFFF, dark: 0x151517)
    public static let pillVeilAlpha = 0.55

    /// Every token by name, in the order the gallery lists them.
    public static let tokens: [(name: String, token: Token)] = [
        ("canvas", canvas), ("surface", surface),
        ("ink", ink), ("inkSecondary", inkSecondary), ("inkOnTint", inkOnTint), ("inkHand", inkHand),
        ("fill", fill), ("onFill", onFill),
        ("dotEmpty", dotEmpty), ("dotFill", dotFill),
        ("tintTrivial", tintTrivial), ("tintEasy", tintEasy), ("tintMedium", tintMedium),
        ("tintHard", tintHard), ("tintHidden", tintHidden),
        ("clay", clay), ("clayBg", clayBg), ("avatarPink", avatarPink),
        ("pillFill", pillFill), ("pillVeil", pillVeil),
    ]

    /// A foreground that carries text over a background. Large Caveat labels are held to 4.5 too.
    public struct TextPair: Sendable {
        public let label: String
        public let foreground: Token
        public let background: Token
    }

    public static let textPairs: [TextPair] = {
        var pairs: [TextPair] = []
        func add(_ fg: (String, Token), on bg: (String, Token)) {
            pairs.append(TextPair(label: "\(fg.0) on \(bg.0)", foreground: fg.1, background: bg.1))
        }
        let canvasT = ("canvas", canvas), surfaceT = ("surface", surface)
        for ground in [canvasT, surfaceT] {
            add(("ink", ink), on: ground)
            add(("inkSecondary", inkSecondary), on: ground)
            add(("inkHand", inkHand), on: ground)
            add(("clay", clay), on: ground)
        }
        for tint in [("tintTrivial", tintTrivial), ("tintEasy", tintEasy), ("tintMedium", tintMedium),
                     ("tintHard", tintHard), ("tintHidden", tintHidden)] {
            add(("ink", ink), on: tint)
            add(("inkOnTint", inkOnTint), on: tint)
        }
        add(("clay", clay), on: ("clayBg", clayBg))
        add(("onFill", onFill), on: ("fill", fill))
        return pairs
    }()

    /// The five pastel tiles, in the order the gallery lists them.
    public static let tints: [(name: String, token: Token)] = [
        ("tintTrivial", tintTrivial), ("tintEasy", tintEasy), ("tintMedium", tintMedium),
        ("tintHard", tintHard), ("tintHidden", tintHidden),
    ]

    /// What a pill looks like over `tint`: the veil at `pillVeilAlpha`.
    public static func pillOnTint(over tint: Token, _ appearance: Appearance) -> Int {
        blend(pillVeil.value(appearance), over: tint.value(appearance), alpha: pillVeilAlpha)
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
