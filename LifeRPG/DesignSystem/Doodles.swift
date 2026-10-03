import LifeRPGCore
import SwiftUI

/// An SVG elliptical arc (spec F.6.5) as at most four cubic curves, so the parser needs no second
/// kind of segment. Rotation is honoured; an out-of-range radius is scaled up as the spec says.
private func addArc(to path: inout Path, from p0: CGPoint, to p1: CGPoint, radii: CGPoint,
                    rotation degrees: CGFloat, large: Bool, sweep: Bool) {
    guard p0 != p1 else { return }
    var rx = abs(radii.x), ry = abs(radii.y)
    guard rx > 0, ry > 0 else { path.addLine(to: p1); return }
    let phi = degrees * .pi / 180, cosPhi = cos(phi), sinPhi = sin(phi)
    let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
    let x1 = cosPhi * dx + sinPhi * dy, y1 = -sinPhi * dx + cosPhi * dy
    let lambda = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
    if lambda > 1 { rx *= lambda.squareRoot(); ry *= lambda.squareRoot() }
    let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
    let coefficient = (large == sweep ? -1 : 1) * max(0, numerator / denominator).squareRoot()
    let cx1 = coefficient * rx * y1 / ry, cy1 = -coefficient * ry * x1 / rx
    let cx = cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2
    let cy = sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2
    let start = atan2((y1 - cy1) / ry, (x1 - cx1) / rx)
    var sweepAngle = atan2((-y1 - cy1) / ry, (-x1 - cx1) / rx) - start
    if sweep && sweepAngle < 0 { sweepAngle += 2 * .pi }
    if !sweep && sweepAngle > 0 { sweepAngle -= 2 * .pi }
    let pieces = Int((abs(sweepAngle) / (.pi / 2)).rounded(.up))
    let step = sweepAngle / CGFloat(pieces)
    let handle = 4 / 3 * tan(step / 4)
    func point(_ a: CGFloat) -> CGPoint {
        CGPoint(x: cx + rx * cos(a) * cosPhi - ry * sin(a) * sinPhi,
                y: cy + rx * cos(a) * sinPhi + ry * sin(a) * cosPhi)
    }
    func tangent(_ a: CGFloat) -> CGPoint {
        CGPoint(x: -rx * sin(a) * cosPhi - ry * cos(a) * sinPhi,
                y: -rx * sin(a) * sinPhi + ry * cos(a) * cosPhi)
    }
    for i in 0..<pieces {
        let a = start + step * CGFloat(i), b = a + step
        let ta = tangent(a), tb = tangent(b), pa = point(a), pb = i == pieces - 1 ? p1 : point(b)
        path.addCurve(to: pb,
                      control1: CGPoint(x: pa.x + handle * ta.x, y: pa.y + handle * ta.y),
                      control2: CGPoint(x: pb.x - handle * tb.x, y: pb.y - handle * tb.y))
    }
}

/// A parsed SVG path (`M L H V C S Q A Z`, absolute and relative) so a doodle is edited as
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
        case "A":
            guard let rx = number(), let ry = number(), let rotation = number(),
                  let large = number(), let sweep = number(), let p = point(rel) else { return path }
            addArc(to: &path, from: current, to: p, radii: CGPoint(x: rx, y: ry), rotation: rotation,
                   large: large != 0, sweep: sweep != 0)
            current = p; lastControl = nil
        case "Z":
            path.closeSubpath(); current = start; lastControl = nil
            command = "M"
        default:
            return path
        }
    }
    return path
}

/// One doodle per `DoodleKey`, drawn in a 100 x 100 box (the ten added later on a 48 x 48 grid, see
/// `grid(for:)`, so a sketch exported from a vector tool pastes in as it is). Closed shapes stop a unit
/// or two short of where they began and no two lines are exactly parallel; the hand-made look is the point.
struct DoodleShape: Shape {
    let key: DoodleKey

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for d in Self.strokes(for: key) { path.addPath(svgPath(d)) }
        for dot in Self.dots(for: key) {
            path.addEllipse(in: CGRect(x: dot.x - dot.r, y: dot.y - dot.r, width: dot.r * 2, height: dot.r * 2))
        }
        let grid = Self.grid(for: key)
        return path.applying(CGAffineTransform(scaleX: rect.width / grid, y: rect.height / grid)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }

    private static func grid(for key: DoodleKey) -> CGFloat {
        switch key {
        case .headphones, .camera, .paw, .forkKnife, .moon, .heart, .speechBubble, .mapPin, .screen, .broom: 48
        default: 100
        }
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
        case .headphones:
            ["M9 28v-4a15 15 0 0 1 30 0v4",
             "M10.5 27h1a3.5 3.5 0 0 1 3.5 3.5v6a3.5 3.5 0 0 1-3.5 3.5h-1a3.5 3.5 0 0 1-3.5-3.5v-6a3.5 3.5 0 0 1 3.5-3.5z",
             "M36.5 27h1a3.5 3.5 0 0 1 3.5 3.5v6a3.5 3.5 0 0 1-3.5 3.5h-1a3.5 3.5 0 0 1-3.5-3.5v-6a3.5 3.5 0 0 1 3.5-3.5z"]
        case .camera:
            ["M7 16h8l3-5h12l3 5h8a1 1 0 0 1 1 1v21a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V17a1 1 0 0 1 1-1z"]
        case .paw:
            ["M24 25c-6 0-11 5-11 9 0 4 3 5 6 5 2 0 3-1 5-1s3 1 5 1c3 0 6-1 6-5 0-4-5-9-11-9z"]
        case .forkKnife:
            ["M13 7v10a4 4 0 0 0 4 4M21 7v10a4 4 0 0 1-4 4M17 7v34",
             "M33 41V7c-4 3-6 8-6 14h6"]
        case .moon:
            ["M33 9a16 16 0 1 0 6 25A13 13 0 0 1 33 9z",
             "M37 8v6M34 11h6"]
        case .heart:
            ["M24 40C10 30 7 22 7 16.5A9 9 0 0 1 24 12a9 9 0 0 1 17 4.5C41 22 38 30 24 40z"]
        case .speechBubble:
            ["M8 11h32a2 2 0 0 1 2 2v18a2 2 0 0 1-2 2H22l-9 8v-8H8a2 2 0 0 1-2-2V13a2 2 0 0 1 2-2z"]
        case .mapPin:
            ["M24 43C14 31 10 25 10 19a14 14 0 0 1 28 0c0 6-4 12-14 24z"]
        case .screen:
            ["M11 10h26a5 5 0 0 1 5 5v16a5 5 0 0 1-5 5H11a5 5 0 0 1-5-5V15a5 5 0 0 1 5-5z",
             "M20 17.5v11l9-5.5z",
             "M16 42h16"]
        case .broom:
            ["M38 6L24 24",
             "M19 22l7 7c1 5-2 11-9 14-6 1-11-2-11-2 4-4 5-8 7-13 2-3 5-5 6-6z",
             "M13 36l4 4M18 31l4 4"]
        }
    }

    private static func dots(for key: DoodleKey) -> [(x: CGFloat, y: CGFloat, r: CGFloat)] {
        switch key {
        case .avatar: [(40, 58, 1.5), (62, 57, 1.5)]
        case .potion: [(46, 78, 3), (58, 56, 2)]
        case .camera: [(24, 27, 7.5)]
        case .paw: [(12, 22, 3.6), (19.5, 14.5, 3.6), (28.5, 14.5, 3.6), (36, 22, 3.6)]
        case .speechBubble: [(16, 22, 0.8), (24, 22, 0.8), (32, 22, 0.8)]
        case .mapPin: [(24, 19, 5)]
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
