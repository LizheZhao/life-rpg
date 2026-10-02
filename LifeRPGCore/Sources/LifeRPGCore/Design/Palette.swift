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

    // The epic card is dark in both appearances, but `fill` inverts in dark mode, so it has its own.
    public static let epic = Token(light: 0x18181B, dark: 0x303036)
    public static let epicTrack = Token(light: 0x3A3A40, dark: 0x4A4A52)
    public static let onEpic = Token(light: 0xFFFFFF, dark: 0xF4F1EE)
    public static let epicSecondary = Token(light: 0xB5B5BD, dark: 0xB5B5BD)
    public static let epicLabel = Token(light: 0xB9E3F4, dark: 0xB9E3F4)

    /// Every token by name, in the order the gallery lists them.
    public static let tokens: [(name: String, token: Token)] = [
        ("canvas", canvas), ("surface", surface),
        ("ink", ink), ("inkSecondary", inkSecondary), ("inkOnTint", inkOnTint), ("inkHand", inkHand),
        ("fill", fill), ("onFill", onFill),
        ("dotEmpty", dotEmpty), ("dotFill", dotFill),
        ("tintTrivial", tintTrivial), ("tintEasy", tintEasy), ("tintMedium", tintMedium),
        ("tintHard", tintHard), ("tintHidden", tintHidden),
        ("clay", clay), ("clayBg", clayBg), ("avatarPink", avatarPink),
        ("epic", epic), ("epicTrack", epicTrack), ("onEpic", onEpic),
        ("epicSecondary", epicSecondary), ("epicLabel", epicLabel),
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
        add(("onEpic", onEpic), on: ("epic", epic))
        add(("epicSecondary", epicSecondary), on: ("epic", epic))
        add(("epicLabel", epicLabel), on: ("epic", epic))
        add(("onEpic", onEpic), on: ("epicTrack", epicTrack))
        return pairs
    }()

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
