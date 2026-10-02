import LifeRPGCore
import SwiftUI

/// A parsed SVG path (`M L H V C S Q Z`, absolute and relative; no arcs) so a doodle is edited as
/// the same string a vector tool exports, and the app has no second drawing format.
private func svgPath(_ d: String) -> Path {
    var path = Path()
    let scanner = Scanner(string: d)
    scanner.charactersToBeSkipped = nil
    let separators = CharacterSet(charactersIn: " ,\n")
    var current = CGPoint.zero, start = CGPoint.zero, lastControl: CGPoint?
    var command: Character = "M"

    func number() -> CGFloat? {
        _ = scanner.scanCharacters(from: separators)
        return scanner.scanDouble().map { CGFloat($0) }
    }
    func point(_ relative: Bool) -> CGPoint? {
        guard let x = number(), let y = number() else { return nil }
        return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
    }

    while true {
        _ = scanner.scanCharacters(from: separators)
        guard let next = scanner.string[scanner.currentIndex...].first else { break }
        if next.isLetter {
            command = next
            scanner.currentIndex = scanner.string.index(after: scanner.currentIndex)
        }
        let rel = command.isLowercase
        switch command.uppercased() {
        case "M":
            guard let p = point(rel) else { return path }
            path.move(to: p); current = p; start = p; lastControl = nil
            command = rel ? "l" : "L"           // extra pairs after a move are lines
        case "L":
            guard let p = point(rel) else { return path }
            path.addLine(to: p); current = p; lastControl = nil
        case "H":
            guard let x = number() else { return path }
            current = CGPoint(x: rel ? current.x + x : x, y: current.y)
            path.addLine(to: current); lastControl = nil
        case "V":
            guard let y = number() else { return path }
            current = CGPoint(x: current.x, y: rel ? current.y + y : y)
            path.addLine(to: current); lastControl = nil
        case "C":
            guard let c1 = point(rel), let c2 = point(rel), let p = point(rel) else { return path }
            path.addCurve(to: p, control1: c1, control2: c2); current = p; lastControl = c2
        case "S":
            let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
            guard let c2 = point(rel), let p = point(rel) else { return path }
            path.addCurve(to: p, control1: c1, control2: c2); current = p; lastControl = c2
        case "Q":
            guard let c = point(rel), let p = point(rel) else { return path }
            path.addQuadCurve(to: p, control: c); current = p; lastControl = nil
        case "Z":
            path.closeSubpath(); current = start; lastControl = nil
            command = "M"
        default:
            return path
        }
    }
    return path
}

/// One doodle per `DoodleKey`, drawn in a 100 x 100 box. Closed shapes stop a unit or two short of
/// where they began and no two lines are exactly parallel; the hand-made look is the point.
struct DoodleShape: Shape {
    let key: DoodleKey

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for d in Self.strokes(for: key) { path.addPath(svgPath(d)) }
        for dot in Self.dots(for: key) {
            path.addEllipse(in: CGRect(x: dot.x - dot.r, y: dot.y - dot.r, width: dot.r * 2, height: dot.r * 2))
        }
        return path.applying(CGAffineTransform(scaleX: rect.width / 100, y: rect.height / 100)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }

    private static func strokes(for key: DoodleKey) -> [String] {
        switch key {
        case .avatar:
            ["M22 46c-4-22 14-34 30-30 18 2 28 18 24 36",
             "M26 44c6-10 20-14 48 0",
             "M50 62c-2 6 0 8 3 8",
             "M38 78c6 7 17 7 25-1"]
        case .sneaker:
            ["M12 66c6-18 18-26 34-26l14 12 22 6c6 2 8 10 0 12H14c-4 0-4-2-3-5",
             "M46 46l-5 8M54 52l-5 8",
             "M4 38c4-2 8 2 14 0M3 52c3-2 6 1 10-1"]
        case .potion:
            ["M36 14h28M44 15c1 10-1 20 0 27L24 78c-3 8 2 10 8 10h36c6 0 11-2 8-10L56 42c1-8-1-18 0-27",
             "M30 68c8-5 12 4 20-1s14 3 22-1"]
        case .braces:
            ["M36 14c-10 0-12 6-12 14v10c0 6-4 10-10 12 6 2 10 6 10 12v10c0 8 2 14 12 14",
             "M64 15c10-1 13 5 12 13v10c0 6 4 10 10 12-6 1-10 7-10 12v11c0 7-2 13-12 13",
             "M55 28L45 72"]
        case .notebook:
            ["M24 14l50 1-1 71-48-1-1-71",
             "M34 14l1 71",
             "M44 34h20M44 48h16",
             "M78 20l8 4-14 42-6-3z"]
        case .dumbbell:
            ["M30 51L70 49",
             "M22 34Q22 30 26 30Q30 30 30 34V66Q30 70 26 70Q22 70 22 66Z",
             "M70 33Q70 29 74 29Q78 29 78 33V67Q78 71 74 71Q70 71 70 67",
             "M14 42l1 16M86 41v17"]
        case .paperPlane:
            ["M10 52L90 20 66 86 48 60 11 51",
             "M48 60L90 21",
             "M48 60l-2 18"]
        case .trendLine:
            ["M12 12L11 88 92 87",
             "M20 74l16-20 16 12 34-42",
             "M68 24l19-3-1 19"]
        case .flag:
            ["M24 90L25 12",
             "M26 14c18-8 30 8 50 0v36c-20 8-32-8-50 0",
             "M40 12l1 36M58 16v36",
             "M26 31c18-8 30 8 50 0"]
        case .sparkle:
            ["M50 8l7 28 28 7-28 7-7 28-7-28-28-7 28-7 7-28",
             "M82 14l1 12M76 20h12"]
        }
    }

    private static func dots(for key: DoodleKey) -> [(x: CGFloat, y: CGFloat, r: CGFloat)] {
        switch key {
        case .avatar: [(40, 58, 1.5), (62, 57, 1.5)]
        case .potion: [(46, 78, 3), (58, 56, 2)]
        default: []
        }
    }
}

/// A one-stroke tick, drawn with a little overshoot on the long leg.
struct HandCheck: Shape {
    func path(in rect: CGRect) -> Path {
        svgPath("M16 54C24 62 30 70 38 78C50 56 68 36 86 22")
            .applying(CGAffineTransform(scaleX: rect.width / 100, y: rect.height / 100)
                .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}

/// A wavy underline that stretches to its frame: one period per ~34 pt, each a touch different.
struct Squiggle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let period: CGFloat = 34
        let count = max(2, Int((rect.width / period).rounded()))
        let step = rect.width / CGFloat(count)
        let mid = rect.midY, amp = rect.height * 0.42
        path.move(to: CGPoint(x: rect.minX, y: mid))
        for i in 0..<count {
            let x0 = rect.minX + step * CGFloat(i)
            let lean = amp * (i.isMultiple(of: 2) ? 1 : 0.85)
            path.addCurve(to: CGPoint(x: x0 + step, y: mid + (i == count - 1 ? -amp * 0.3 : 0)),
                          control1: CGPoint(x: x0 + step * 0.25, y: mid - lean),
                          control2: CGPoint(x: x0 + step * 0.75, y: mid + lean))
        }
        return path
    }
}

/// The doodle stroked at 3.5 / 100 of its size, so the line weight scales with the picture.
struct DoodleView: View {
    let key: DoodleKey
    var size: CGFloat = 40
    var tint: Color = LR.Color.ink

    var body: some View {
        DoodleShape(key: key)
            .stroke(tint, style: StrokeStyle(lineWidth: 3.5 * size / 100, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct AvatarView: View {
    var size: CGFloat = 44
    var label = "Avatar"

    var body: some View {
        Circle()
            .fill(LR.Color.avatarPink)
            .frame(width: size, height: size)
            .overlay { DoodleView(key: .avatar, size: size * 0.7) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }
}
