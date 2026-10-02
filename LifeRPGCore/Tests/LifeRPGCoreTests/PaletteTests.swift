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
        #expect(Palette.surface == Palette.Token(light: 0xFFFFFF, dark: 0x23222C))
        #expect(Palette.hairline == Palette.Token(light: 0xECECE6, dark: 0x2F2E3A))
        #expect(Palette.divider == Palette.Token(light: 0xECECE6, dark: 0x34323F))
        #expect(Palette.ink == Palette.Token(light: 0x25232F, dark: 0xE8E6EE))
        #expect(Palette.iconNeutral == Palette.Token(light: 0x6E6C7A, dark: 0x8A8896))
        #expect(Palette.sectionTitle == Palette.Token(light: 0x7A7886, dark: 0x9C9AA8))
        #expect(Palette.tabPill == Palette.Token(light: 0xE9E7F2, dark: 0x3A3848))
        #expect(Palette.accent == Palette.Token(light: 0x4682B4, dark: 0x8FB0CC))
        #expect(Palette.chip == Palette.Token(light: 0xFFFFFF, dark: 0x14141A))
        // sage, steel blue, amber, crimson, dusk violet: trivial, easy, medium, hard, hidden.
        #expect(Palette.tints.map { $0.token.light } == [0x9CAF88, 0x4682B4, 0xFFBF00, 0xC8465A, 0x8A7BB3])
        #expect(Palette.tints.map { $0.token.dark } == [0x86987A, 0x3F76A5, 0xD8A645, 0xB84A60, 0x7A6CA8])
        #expect(Palette.onTintDark == Palette.Token(light: 0x25232F, dark: 0x1B1A22))
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
        #expect(Set(pairs.map(\.label)).isSuperset(of: ["ink on canvas", "ink on tintHidden", "ink on chip",
                                                         "clay on clayBg", "onFill on fill"]))
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

    /// Settings section headers use the sheet's secondary text colour, which is 4.32:1 on a card and
    /// 4.17:1 on the page in light. Headers are 17 pt weight 700 (large text), so the bar is 3:1.
    /// Every other secondary text is `inkSecondary` and stays in `textPairs` at 4.5.
    private static let sectionTitleBelowAA: Set<String> = [
        "light sectionTitle on canvas", "light sectionTitle on surface",
    ]

    @Test(arguments: Palette.Appearance.allCases)
    func sectionTitleClearsTheLargeTextBar(appearance: Palette.Appearance) {
        for pair in Palette.sectionTitlePairs(appearance) {
            let measured = ratio(pair.foreground, pair.background)
            let key = "\(appearance) \(pair.label)"
            #expect(measured >= Palette.largeTextBar, "\(key): \(measured)")
            if Self.sectionTitleBelowAA.contains(key) {
                #expect(measured < 4.5, "\(key) is listed as below AA but is \(measured)")
            } else {
                #expect(measured >= 4.5, "\(key): \(measured)")
            }
        }
    }

    @Test func sectionTitleRatiosAreTheMeasuredOnes() {
        #expect(abs(ratio(Palette.sectionTitle.light, Palette.surface.light) - 4.32) < 0.01)
        #expect(abs(ratio(Palette.sectionTitle.light, Palette.canvas.light) - 4.17) < 0.01)
        #expect(abs(ratio(Palette.sectionTitle.dark, Palette.surface.dark) - 5.69) < 0.01)
        #expect(abs(ratio(Palette.sectionTitle.dark, Palette.canvas.dark) - 6.64) < 0.01)
        // Not applied: the smallest nudge that would make the light header pass 4.5 on the page.
        #expect(ratio(0x747281, Palette.canvas.light) >= 4.5)
        #expect(ratio(0x747281, Palette.surface.light) >= 4.5)
    }

    @Test(arguments: Palette.Appearance.allCases)
    func iconsAndChevronsClearThreeToOne(appearance: Palette.Appearance) {
        let pairs = Palette.iconPairs(appearance)
        #expect(pairs.count == 8)
        for pair in pairs {
            let measured = ratio(pair.foreground, pair.background)
            #expect(measured >= 3.0, "\(appearance) \(pair.label): \(measured)")
        }
        #expect(abs(ratio(Palette.iconNeutral.light, Palette.surface.light) - 5.14) < 0.01)
        #expect(abs(ratio(Palette.iconNeutral.dark, Palette.surface.dark) - 4.52) < 0.01)
        #expect(abs(ratio(Palette.iconNeutral.light, Palette.tabPill.light) - 4.20) < 0.01)
        #expect(abs(ratio(Palette.iconNeutral.dark, Palette.tabPill.dark) - 3.29) < 0.01)
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
    }

    @Test func anchorsHoldInBothAppearances() {
        #expect(ratio(Palette.ink.light, Palette.canvas.light) > 14)
        #expect(ratio(Palette.ink.dark, Palette.canvas.dark) > 13)
        #expect(ratio(Palette.onFill.light, Palette.fill.light) > 14)
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

    @Test func aNeutralCardSitsOneStepOffThePageInBothAppearances() {
        // No black or white block: the card is a hair above the page, and text and tints do the rest.
        #expect(ratio(Palette.surface.light, Palette.canvas.light) < 1.1)
        let dark = ratio(Palette.surface.dark, Palette.canvas.dark)
        #expect(dark >= 1.1 && dark < 1.25, "dark card vs page: \(dark)")
        for appearance in Palette.Appearance.allCases {
            #expect(ratio(Palette.hairline.value(appearance), Palette.surface.value(appearance)) >= 1.1)
            #expect(ratio(Palette.divider.value(appearance), Palette.surface.value(appearance)) >= 1.1)
        }
    }

    @Test func theTabPillIsVisibleOnTheBar() {
        for appearance in Palette.Appearance.allCases {
            #expect(ratio(Palette.tabPill.value(appearance), Palette.surface.value(appearance)) >= 1.15)
        }
    }

    @Test(arguments: Palette.Appearance.allCases)
    func aPillHasAVisibleShapeOnACardAndOnTheCanvas(appearance: Palette.Appearance) {
        for ground in [Palette.surface, Palette.canvas] {
            let measured = ratio(Palette.pillFill.value(appearance), ground.value(appearance))
            #expect(measured >= 1.1, "pillFill vs ground in \(appearance): \(measured)")
        }
    }

    @Test(arguments: Palette.Appearance.allCases)
    func theChipOnATintIsVisibleAgainstIt(appearance: Palette.Appearance) {
        for tint in Palette.tints {
            let measured = ratio(Palette.chip.value(appearance), tint.token.value(appearance))
            #expect(measured >= 1.5, "chip over \(tint.name) in \(appearance): \(measured)")
        }
    }

    @Test func shadowsAreSoftAndTintedOnlyInLight() {
        #expect(Palette.shadow(.light) == Palette.CardShadow(surface: 0.055, tint: 0.22, tintedByCard: true))
        // A neutral dark card has no shadow, only its hairline.
        #expect(Palette.shadow(.dark) == Palette.CardShadow(surface: 0, tint: 0.4, tintedByCard: false))
    }

    @Test func blendingMatchesHandComputedChannels() {
        #expect(Palette.blend(0xFFFFFF, over: 0x000000, alpha: 0.5) == 0x808080)
        #expect(Palette.blend(0x102030, over: 0x102030, alpha: 0.3) == 0x102030)
        #expect(Palette.blend(0xFF0000, over: 0x0000FF, alpha: 1) == 0xFF0000)
        #expect(Palette.blend(0xFF0000, over: 0x0000FF, alpha: 0) == 0x0000FF)
    }
}
