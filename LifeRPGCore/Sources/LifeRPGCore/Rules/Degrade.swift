import Foundation
import SwiftData

/// `degraded_text` (`PLAN.md` §4): on a low day (`Tier.isLow`) a routine with a light version is
/// swapped for it, decided once when the occurrence is created. The point is to lower the
/// intensity rather than skip, so the swap is automatic — but the original can still be chosen,
/// for the same points. Either version pays the routine's full points.
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

    /// The light version `routine` is swapped for on a `tier` day, or nil: not a low day, or no
    /// non-empty `degraded_text`.
    public static func text(for routine: RoutineTask, tier: Tier) -> String? {
        guard tier.isLow,
              let text = routine.degradedText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
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
