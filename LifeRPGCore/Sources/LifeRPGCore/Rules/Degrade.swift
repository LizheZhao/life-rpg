import Foundation
import SwiftData

/// Downgrade versions (`PLAN.md` §4): on a low day (`Tier.isLow`, which the first three cycle days
/// also produce) a routine that offers lighter versions starts out as one of them, drawn once when
/// the occurrence is created. The point is to lower the effort rather than skip, so the swap is
/// automatic — but the original can still be chosen until the occurrence is closed.
///
/// A downgrade version is a `RoutineTask` of its own, so it carries its own text, its own
/// `basePoints` (the walk pays what a walk is worth, not what the session it replaced was) and
/// its own auto-verify rule. It is never scheduled on its own.
public enum Degrade {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case noLightVersion
        /// Done or skipped: the version it ended in is part of the record.
        case closed

        public var description: String {
            switch self {
            case .noLightVersion: "this routine has no light version today"
            case .closed: "already done or skipped"
            }
        }
    }

    /// Every id that is some routine's downgrade version. These rows are completed and paid like
    /// any other routine, but never come due by themselves.
    public static func versionIDs(in routines: [RoutineTask]) -> Set<UUID> {
        Set(routines.flatMap(\.downgradeIDs))
    }

    /// The downgrade versions `routine` offers, in the order its ids are listed.
    public static func versions(of routine: RoutineTask, in routines: [RoutineTask]) -> [RoutineTask] {
        let byID = Dictionary(routines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return routine.downgradeIDs.compactMap { byID[$0] }.filter(\.isActive)
    }

    /// The version this routine is swapped for on a `tier` day, or nil: not a low day, or nothing
    /// on offer. With several on offer one is drawn at random, once, at generation.
    public static func pick(for routine: RoutineTask, tier: Tier, in routines: [RoutineTask],
                            rng: inout some RandomNumberGenerator) -> RoutineTask? {
        guard tier.isLow else { return nil }
        return versions(of: routine, in: routines).randomElement(using: &rng)
    }

    /// The same draw outside day generation — completing a flexible routine ahead, where there is
    /// no seeded RNG to thread through.
    public static func pick(for routine: RoutineTask, tier: Tier, in routines: [RoutineTask]) -> RoutineTask? {
        var rng = SystemRandomNumberGenerator()
        return pick(for: routine, tier: tier, in: routines, rng: &rng)
    }

    /// Switches an open occurrence between its light version and the original.
    public static func choose(light: Bool, for occurrence: RoutineOccurrence,
                              in context: ModelContext) throws {
        guard occurrence.degradedTextSnapshot != nil else { throw Failure.noLightVersion }
        guard Schedule.isOpen(occurrence) else { throw Failure.closed }
        let before = occurrence.usedDegraded
        occurrence.usedDegraded = light
        do {
            try context.save()
        } catch {
            occurrence.usedDegraded = before
            throw error
        }
    }
}
