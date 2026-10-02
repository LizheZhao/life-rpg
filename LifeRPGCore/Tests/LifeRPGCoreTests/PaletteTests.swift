import Foundation
import Testing
@testable import LifeRPGCore

/// The contrast bar of `doc/UI_DESIGN.md` is enforced here, so a colour tweak that makes text
/// unreadable fails a test instead of shipping.
struct PaletteTests {
    private func ratio(_ a: Int, _ b: Int) -> Double { Palette.contrast(a, b) }

    @Test func contrastMatchesTheWCAGDefinition() {
        #expect(Palette.contrast(0x000000, 0xFFFFFF) == 21.0)
        #expect(Palette.contrast(0xFFFFFF, 0xFFFFFF) == 1.0)
        #expect(abs(Palette.contrast(0xFFFFFF, 0x000000) - 21.0) < 1e-9)   // order does not matter
        // The commonly quoted #777 on white is 4.48:1, just under the bar.
        #expect(abs(Palette.contrast(0x777777, 0xFFFFFF) - 4.48) < 0.01)
    }

    // MARK: the user's sheet, as literals

    @Test func tokensAreTheUsersPaletteSheet() {
        #expect(Palette.canvas == Palette.Token(light: 0xFBFBF8, dark: 0x14141A))
        #expect(Palette.divider == Palette.Token(light: 0xE9EBE5, dark: 0x2B2A35))
        #expect(Palette.ink == Palette.Token(light: 0x25232F, dark: 0xE6E4EC))
        #expect(Palette.accent == Palette.Token(light: 0x4682B4, dark: 0x8FB0CC))
        #expect(Palette.chip == Palette.Token(light: 0xFFFFFF, dark: 0x14141A))
        // sage, steel blue, amber, crimson, dusk violet: trivial, easy, medium, hard, hidden.
        #expect(Palette.tints.map { $0.token.light } == [0x9CAF88, 0x4682B4, 0xFFBF00, 0xC8465A, 0x8A7BB3])
        #expect(Palette.tints.map { $0.token.dark } == [0x86987A, 0x3F76A5, 0xD8A645, 0xB84A60, 0x7A6CA8])
        #expect(Palette.onTintDark == Palette.Token(light: 0x25232F, dark: 0x1B1A22))
    }

    @Test func theNeutralCardIsTheInversionOfThePage() {
        #expect(Palette.surface == Palette.Token(light: 0x25232F, dark: 0xEEEFE9))
        #expect(Palette.hairline == Palette.Token(light: 0x34323F, dark: 0xDCDDD6))
        #expect(Palette.cardInk == Palette.Token(light: 0xE6E4EC, dark: 0x25232F))
        #expect(Palette.cardInkSecondary == Palette.Token(light: 0xA9A7B6, dark: 0x6A6877))
        #expect(Palette.cardAccent == Palette.Token(light: 0x8FB0CC, dark: 0x4682B4))
        #expect(Palette.cardPill == Palette.Token(light: 0x34323F, dark: 0xE1E2DB))
        #expect(Palette.cardDivider == Palette.Token(light: 0x464456, dark: 0xD9DAD3))
        #expect(Palette.cardClay == Palette.Token(light: 0xE8A183, dark: 0x9C472A))
        #expect(Palette.dotFill == Palette.Token(light: 0x9CAF88, dark: 0x65785A))
        #expect(Palette.dotEmpty == Palette.Token(light: 0x3A3847, dark: 0xD9DAD3))
        // The done check on a neutral card is the card's ink on the card's colour, and back.
        #expect(Palette.cardFill == Palette.cardInk)
        #expect(Palette.cardOnFill == Palette.surface)
        // Opposite polarity: the card is darker than the page in light and lighter in dark.
        #expect(Palette.luminance(Palette.surface.light) < Palette.luminance(Palette.canvas.light))
        #expect(Palette.luminance(Palette.surface.dark) > Palette.luminance(Palette.canvas.dark))
        // The card text is the opposite of the canvas text.
        #expect(Palette.cardInk.light == Palette.ink.dark && Palette.cardInk.dark == Palette.ink.light)
    }

    @Test func textOnATintIsChosenPerTint() {
        // Dark on the light amber and sage, white on steel blue, crimson and violet, both appearances.
        #expect(Palette.tints.map { Palette.ink(on: $0.tint) }
                == [Palette.onTintDark, Palette.onTintWhite, Palette.onTintDark,
                    Palette.onTintWhite, Palette.onTintWhite])
        #expect(Palette.onTintWhite.light == 0xFFFFFF && Palette.onTintWhite.dark == 0xFFFFFF)
    }

    // MARK: contrast

    /// The sheet puts white on steel blue #4682B4 (4.11:1) and on dusk violet #8A7BB3 (3.77:1) in
    /// light. Both miss 4.5 for 15 pt text and are kept as the user chose them, at the large-text
    /// 3:1 floor. No other pair may be listed here.
    private static let knownBelowAA: Set<String> = [
        "light ink on tintEasy", "light ink on tintHidden",
    ]

    @Test(arguments: Palette.Appearance.allCases)
    func everyTextPairClearsFourPointFive(appearance: Palette.Appearance) {
        let pairs = Palette.textPairs(appearance)
        #expect(Set(pairs.map(\.label)).isSuperset(of: [
            "ink on canvas", "ink on tintHidden", "ink on chip", "clay on clayBg", "onFill on fill",
            "cardInk on surface", "cardInkSecondary on surface", "cardClay on surface",
            "cardInk on cardPill", "cardOnFill on cardFill"]))
        for pair in pairs {
            let measured = ratio(pair.foreground, pair.background)
            let key = "\(appearance) \(pair.label)"
            if Self.knownBelowAA.contains(key) {
                // The pair label names the tint, not the foreground: only a white foreground may be here.
                #expect(pair.foreground == 0xFFFFFF)
                #expect(measured < 4.5, "\(key) is listed as below AA but is \(measured)")
                #expect(measured >= Palette.largeTextBar, "\(key): \(measured)")
            } else {
                #expect(measured >= 4.5, "\(key): \(measured)")
            }
        }
    }

    @Test func theTwoKnownPairsAreExactlyTheMeasuredOnes() {
        let light = Palette.textPairs(.light).filter { Self.knownBelowAA.contains("light \($0.label)") }
        #expect(light.count == 2)
        #expect(abs(ratio(light[0].foreground, light[0].background) - 4.11) < 0.01)   // white on steel blue
        #expect(abs(ratio(light[1].foreground, light[1].background) - 3.77) < 0.01)   // white on dusk violet
    }

    @Test func theOptionalNudgeWouldClearFourPointFive() {
        // Not applied: the smallest change that lifts the two light pairs over AA.
        #expect(ratio(0xFFFFFF, 0x4179A7) >= 4.5)
        #expect(ratio(0x25232F, 0x9386B9) >= 4.5)
    }

    @Test func theCardSideTextPairsHaveTheirMeasuredRatios() {
        let expected: [(Palette.Appearance, String, Double)] = [
            (.light, "cardInk on surface", 12.26), (.dark, "cardInk on surface", 13.35),
            (.light, "cardInkSecondary on surface", 6.54), (.dark, "cardInkSecondary on surface", 4.71),
        ]
        for (appearance, label, value) in expected {
            let pair = Palette.textPairs(appearance).first { $0.label == label }!
            #expect(abs(ratio(pair.foreground, pair.background) - value) < 0.01, "\(appearance) \(label)")
        }
    }

    @Test(arguments: Palette.Appearance.allCases)
    func shapesThatCarryMeaningClearThreeToOne(appearance: Palette.Appearance) {
        let pairs = Palette.nonTextPairs(appearance)
        #expect(pairs.count == 5)
        for pair in pairs {
            let measured = ratio(pair.foreground, pair.background)
            #expect(measured >= Palette.nonTextBar, "\(appearance) \(pair.label): \(measured)")
        }
    }

    @Test func theMeasuredRatiosOfTheRestOfTheSheet() {
        let expected: [(Palette.Appearance, QuestTint, Double)] = [
            (.light, .medium, 9.34), (.light, .trivial, 6.54), (.light, .hard, 4.69),
            (.dark, .medium, 7.77), (.dark, .trivial, 5.57),
            (.dark, .easy, 4.83), (.dark, .hard, 5.02), (.dark, .hidden, 4.63),
        ]
        for (appearance, tint, value) in expected {
            let measured = ratio(Palette.ink(on: tint).value(appearance), Palette.tint(tint).value(appearance))
            #expect(abs(measured - value) < 0.01, "\(appearance) \(tint): \(measured)")
        }
    }

    @Test(arguments: Palette.Appearance.allCases)
    func theAccentCarriesLargeHandLabels(appearance: Palette.Appearance) {
        for pair in Palette.largeTextPairs(appearance) {
            #expect(ratio(pair.foreground, pair.background) >= Palette.largeTextBar, Comment(rawValue: "\(appearance) \(pair.label)"))
        }
        // Caveat 22 pt is large text: 3.96 on the light canvas, 8.08 on the dark one.
        #expect(abs(ratio(Palette.accent.light, Palette.canvas.light) - 3.96) < 0.01)
        #expect(abs(ratio(Palette.accent.dark, Palette.canvas.dark) - 8.08) < 0.01)
        #expect(Palette.largeTextPairs(.light).map(\.label) == ["accent on canvas"])
    }

    @Test func anchorsHoldInBothAppearances() {
        #expect(ratio(Palette.ink.light, Palette.canvas.light) > 14)
        #expect(ratio(Palette.ink.dark, Palette.canvas.dark) > 13)
        #expect(ratio(Palette.onFill.light, Palette.fill.light) > 14)
        #expect(ratio(Palette.cardInk.light, Palette.surface.light) > 12)
        #expect(ratio(Palette.cardInk.dark, Palette.surface.dark) > 12)
    }

    @Test func everyRegisteredTokenHasBothAppearances() {
        #expect(Set(Palette.tokens.map(\.name)).count == Palette.tokens.count)
        for (name, token) in Palette.tokens {
            #expect((0...0xFFFFFF).contains(token.light) && (0...0xFFFFFF).contains(token.dark), Comment(rawValue: name))
            // A token identical in both appearances is a forgotten dark value, except the one that is
            // white on purpose.
            if name != "onTintWhite" { #expect(token.light != token.dark, "\(name) has no dark value") }
        }
    }

    // MARK: edges and pills

    @Test(arguments: Palette.Appearance.allCases)
    func aNeutralCardStandsClearOfThePageAndKeepsItsEdge(appearance: Palette.Appearance) {
        // Inverted, so the card no longer leans on its hairline to separate from the page.
        #expect(ratio(Palette.surface.value(appearance), Palette.canvas.value(appearance)) >= 10)
        #expect(ratio(Palette.hairline.value(appearance), Palette.surface.value(appearance)) >= 1.1)
    }

    @Test(arguments: Palette.Appearance.allCases)
    func aPillHasAVisibleShapeOnACardAndOnTheCanvas(appearance: Palette.Appearance) {
        let onCard = ratio(Palette.cardPill.value(appearance), Palette.surface.value(appearance))
        #expect(onCard >= 1.1, "cardPill vs surface in \(appearance): \(onCard)")
        let onCanvas = ratio(Palette.pillFill.value(appearance), Palette.canvas.value(appearance))
        #expect(onCanvas >= 1.1, "pillFill vs canvas in \(appearance): \(onCanvas)")
    }

    @Test(arguments: Palette.Appearance.allCases)
    func anEmptyDotIsVisibleOnTheCardWithoutShoutingOverAFilledOne(appearance: Palette.Appearance) {
        let empty = ratio(Palette.dotEmpty.value(appearance), Palette.surface.value(appearance))
        #expect(empty >= 1.1 && empty < 2, "dotEmpty vs surface in \(appearance): \(empty)")
    }

    @Test(arguments: Palette.Appearance.allCases)
    func theChipOnATintIsVisibleAgainstIt(appearance: Palette.Appearance) {
        for tint in Palette.tints {
            let measured = ratio(Palette.chip.value(appearance), tint.token.value(appearance))
            #expect(measured >= 1.5, "chip over \(tint.name) in \(appearance): \(measured)")
        }
    }

    @Test func shadowsAreSoftAndTintedOnlyInLight() {
        #expect(Palette.shadow(.light) == Palette.CardShadow(surface: 0.14, tint: 0.22, tintedByCard: true))
        #expect(Palette.shadow(.dark) == Palette.CardShadow(surface: 0.1, tint: 0.4, tintedByCard: false))
    }

    @Test func blendingMatchesHandComputedChannels() {
        #expect(Palette.blend(0xFFFFFF, over: 0x000000, alpha: 0.5) == 0x808080)
        #expect(Palette.blend(0x102030, over: 0x102030, alpha: 0.3) == 0x102030)
        #expect(Palette.blend(0xFF0000, over: 0x0000FF, alpha: 1) == 0xFF0000)
        #expect(Palette.blend(0xFF0000, over: 0x0000FF, alpha: 0) == 0x0000FF)
    }
}
