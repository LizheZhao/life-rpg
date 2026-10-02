import CoreText
import OSLog
import SwiftUI
import UIKit

/// Plus Jakarta Sans and Caveat, registered from the bundle at launch so neither the Info.plist nor
/// the project file has to know about them. Both are variable fonts: a weight is a value on the
/// `wght` axis, not a separate face, so a style asks for one through a font descriptor.
enum LRFonts {
    enum Family {
        case jakarta, caveat

        var postScriptName: String {
            switch self {
            case .jakarta: "PlusJakartaSans-Regular"
            case .caveat: "Caveat-Regular"
            }
        }

        var familyName: String {
            switch self {
            case .jakarta: "Plus Jakarta Sans"
            case .caveat: "Caveat"
            }
        }

        var weights: ClosedRange<CGFloat> {
            switch self {
            case .jakarta: 200...800
            case .caveat: 400...700
            }
        }
    }

    private static let weightAxis = 2003265652      // 'wght'
    private static let log = Logger(subsystem: "LifeRPG", category: "fonts")

    static func register() {
        for file in ["PlusJakartaSans", "Caveat"] {
            guard let url = Bundle.main.url(forResource: file, withExtension: "ttf") else {
                log.error("\(file).ttf is not in the bundle; falling back to the system font")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                log.error("\(file).ttf failed to register: \(String(describing: error?.takeRetainedValue()))")
            }
        }
    }

    /// The custom face at a weight on its axis, or the system font at the nearest weight if the
    /// file did not register. A missing font must never take a screen down.
    static func uiFont(_ family: Family, weight: CGFloat, size: CGFloat) -> UIFont {
        let clamped = min(max(weight, family.weights.lowerBound), family.weights.upperBound)
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: family.postScriptName,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [weightAxis: clamped],
        ])
        let font = UIFont(descriptor: descriptor, size: size)
        guard font.familyName == family.familyName else {
            return .systemFont(ofSize: size, weight: systemWeight(clamped))
        }
        return font
    }

    /// Whether the custom faces are in use; the gallery says so, since a silent fallback looks fine.
    static var isActive: Bool {
        uiFont(.jakarta, weight: 400, size: 12).familyName == Family.jakarta.familyName
            && uiFont(.caveat, weight: 400, size: 12).familyName == Family.caveat.familyName
    }

    private static func systemWeight(_ wght: CGFloat) -> UIFont.Weight {
        switch wght {
        case ..<250: .ultraLight
        case ..<350: .light
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        case ..<750: .bold
        default: .heavy
        }
    }
}
