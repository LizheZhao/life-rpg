import Testing
@testable import LifeRPGCore

/// The contrast bar of `doc/UI_DESIGN.md` is enforced here, so a colour tweak that makes text
/// unreadable fails a test instead of shipping.
struct PaletteTests {
    @Test func contrastMatchesTheWCAGDefinition() {
        #expect(Palette.contrast(0x000000, 0xFFFFFF) == 21.0)
        #expect(Palette.contrast(0xFFFFFF, 0xFFFFFF) == 1.0)
        #expect(abs(Palette.contrast(0xFFFFFF, 0x000000) - 21.0) < 1e-9)   // order does not matter
        // The commonly quoted #777 on white is 4.48:1, just under the bar.
        #expect(abs(Palette.contrast(0x777777, 0xFFFFFF) - 4.48) < 0.01)
    }

    @Test(arguments: Palette.Appearance.allCases)
    func everyTextPairClearsFourPointFive(appearance: Palette.Appearance) {
        for pair in Palette.textPairs {
            let ratio = Palette.contrast(pair.foreground.value(appearance), pair.background.value(appearance))
            #expect(ratio >= 4.5, "\(pair.label) in \(appearance): \(ratio)")
        }
    }

    @Test func anchorsHoldInBothAppearances() {
        #expect(Palette.contrast(Palette.ink.light, Palette.canvas.light) > 15)
        #expect(Palette.contrast(Palette.ink.dark, Palette.canvas.dark) > 15)
        #expect(Palette.contrast(Palette.onFill.light, Palette.fill.light) > 17)
        // The pastel tile is why `inkOnTint` exists: the secondary ink is only ~4.2 on the sky tile.
        #expect(Palette.contrast(Palette.inkSecondary.light, Palette.tintEasy.light) < 4.5)
        #expect(Palette.contrast(Palette.inkOnTint.light, Palette.tintEasy.light) > 7)
    }

    @Test func everyTextPairUsesRegisteredTokens() {
        let registered = Set(Palette.tokens.map(\.token))
        #expect(Set(Palette.tokens.map(\.name)).count == Palette.tokens.count)
        for pair in Palette.textPairs {
            #expect(registered.contains(pair.foreground), "\(pair.label) foreground")
            #expect(registered.contains(pair.background), "\(pair.label) background")
        }
    }

    @Test func textPairsCoverEveryTintAndTheEpicCard() {
        let labels = Set(Palette.textPairs.map(\.label))
        for tint in ["tintTrivial", "tintEasy", "tintMedium", "tintHard", "tintHidden"] {
            #expect(labels.contains("ink on \(tint)"))
            #expect(labels.contains("inkOnTint on \(tint)"))
        }
        #expect(labels.contains("onEpic on epic"))
        #expect(labels.contains("clay on clayBg"))
        #expect(labels.contains("onFill on fill"))
        #expect(labels.contains("inkHand on canvas"))
    }

    @Test func appearancesDifferForEverySurfaceToken() {
        // A token that is identical in both appearances is either deliberate or a forgotten dark
        // value; only the epic card's secondary and label inks are meant to stay put.
        let sameOnPurpose: Set<String> = ["epicSecondary", "epicLabel"]
        for (name, token) in Palette.tokens where !sameOnPurpose.contains(name) {
            #expect(token.light != token.dark, "\(name) has no dark value")
        }
    }

    @Test func hexLiteralsStayRGB() {
        for (name, token) in Palette.tokens {
            #expect((0...0xFFFFFF).contains(token.light), "\(name) light")
            #expect((0...0xFFFFFF).contains(token.dark), "\(name) dark")
        }
    }

    // MARK: pills

    @Test(arguments: Palette.Appearance.allCases)
    func pillTextClearsFourPointFiveOnACardAndOnTheCanvas(appearance: Palette.Appearance) {
        let fill = Palette.pillFill.value(appearance)
        for fg in [("ink", Palette.ink), ("inkOnTint", Palette.inkOnTint)] {
            let ratio = Palette.contrast(fg.1.value(appearance), fill)
            #expect(ratio >= 4.5, "\(fg.0) on pillFill in \(appearance): \(ratio)")
        }
    }

    @Test(arguments: Palette.Appearance.allCases)
    func aPillHasAVisibleShapeOnACardAndOnTheCanvas(appearance: Palette.Appearance) {
        // The first gallery drew pills in the canvas colour, so on the canvas they had no edge.
        let fill = Palette.pillFill.value(appearance)
        for ground in [Palette.surface, Palette.canvas] {
            let ratio = Palette.contrast(fill, ground.value(appearance))
            #expect(ratio >= 1.1, "pillFill vs ground in \(appearance): \(ratio)")
        }
    }

    @Test(arguments: Palette.Appearance.allCases)
    func pillTextClearsFourPointFiveOnEveryTint(appearance: Palette.Appearance) {
        for tint in Palette.tints {
            let fill = Palette.pillOnTint(over: tint.token, appearance)
            for fg in [("ink", Palette.ink), ("inkOnTint", Palette.inkOnTint)] {
                let ratio = Palette.contrast(fg.1.value(appearance), fill)
                #expect(ratio >= 4.5, "\(fg.0) on a pill over \(tint.name) in \(appearance): \(ratio)")
            }
        }
    }

    @Test func aPillOverATintIsStillVisibleAgainstIt() {
        for appearance in Palette.Appearance.allCases {
            for tint in Palette.tints {
                let ratio = Palette.contrast(Palette.pillOnTint(over: tint.token, appearance),
                                             tint.token.value(appearance))
                #expect(ratio >= 1.15, "pill over \(tint.name) in \(appearance): \(ratio)")
            }
        }
    }

    @Test func blendingMatchesHandComputedChannels() {
        #expect(Palette.blend(0xFFFFFF, over: 0x000000, alpha: 0.5) == 0x808080)
        #expect(Palette.blend(0x102030, over: 0x102030, alpha: 0.3) == 0x102030)
        #expect(Palette.blend(0xFF0000, over: 0x0000FF, alpha: 1) == 0xFF0000)
        #expect(Palette.blend(0xFF0000, over: 0x0000FF, alpha: 0) == 0x0000FF)
    }
}
