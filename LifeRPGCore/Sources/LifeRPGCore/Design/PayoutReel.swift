import Foundation

/// The numbers around a payout reveal that are **not** the payout. The points were rolled in
/// `Completion.complete` and are already in the ledger when the reel plays; everything here is
/// decoration drawn from the span the roll could have landed in, so the reel never shows a value
/// that could not have come up and never shows the real one early.
public enum PayoutReel {
    /// `count` throwaway frames for the reel to scroll through, each inside `range`, no two in a
    /// row equal, and the last one never `awarded`, so landing is always a visible change. A span
    /// with a single value has nothing to roll and returns no frames.
    public static func frames(range: ClosedRange<Int>, awarded: Int, count: Int,
                              using rng: inout some RandomNumberGenerator) -> [Int] {
        guard count > 0, range.count > 1 else { return [] }
        var frames = [Int](repeating: range.lowerBound, count: count)
        // Built from the end: the last frame is the only one with a rule of its own.
        frames[count - 1] = value(in: range, excluding: awarded, using: &rng)
        for index in stride(from: count - 2, through: 0, by: -1) {
            frames[index] = value(in: range, excluding: frames[index + 1], using: &rng)
        }
        return frames
    }

    /// The values drawn faintly above and below the landed number. One step either side, and
    /// nothing past an end of the span: a neighbour outside it is a number the roll could never
    /// have paid, which would read as a near miss.
    public struct Neighbours: Equatable, Sendable {
        public let before: Int?
        public let after: Int?
    }

    public static func neighbours(of awarded: Int, in range: ClosedRange<Int>) -> Neighbours {
        Neighbours(before: range.contains(awarded - 1) ? awarded - 1 : nil,
                   after: range.contains(awarded + 1) ? awarded + 1 : nil)
    }

    /// A uniform value from `range` other than `excluded` (which needs two or more values to
    /// exclude anything; outside the span it excludes nothing).
    private static func value(in range: ClosedRange<Int>, excluding excluded: Int,
                              using rng: inout some RandomNumberGenerator) -> Int {
        guard range.contains(excluded) else { return Int.random(in: range, using: &rng) }
        let draw = Int.random(in: range.lowerBound...(range.upperBound - 1), using: &rng)
        return draw >= excluded ? draw + 1 : draw
    }
}
