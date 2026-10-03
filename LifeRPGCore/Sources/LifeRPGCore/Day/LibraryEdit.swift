import Foundation
import SwiftData

/// Turning a library row off, and changing what a routine pays.
///
/// Both only reach forward. What is already on the page keeps its own state: an open occurrence
/// still runs its ladder or its week, and keeps the points it was created with (an occurrence
/// snapshots `basePoints`). That is also what stops "turn it off, then on again" from being a free
/// cancel — a cancel costs coins (`Redemption.cancel`). There is no way to delete a row: history
/// and ratings point at it by id, so "off" is as gone as it gets.
public enum LibraryEdit {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notFound
        case belowMinimum(Int)

        public var description: String {
            switch self {
            case .notFound: "that library row is gone"
            case .belowMinimum(let n): "a routine pays at least \(n)"
            }
        }
    }

    /// The least a routine can pay: a penalty is a share of it, so zero would charge nothing.
    public static let minimumPoints = 5
    /// What a step on the points control moves it by.
    public static let pointsStep = 5

    public static func setActive(_ active: Bool, _ target: FeedbackTarget, id: UUID,
                                 in context: ModelContext) throws {
        switch target {
        case .quest:
            guard let row = try context.fetch(FetchDescriptor<QuestTemplate>(predicate: #Predicate { $0.id == id })).first
            else { throw Failure.notFound }
            row.isActive = active
        case .routine:
            guard let row = try context.fetch(FetchDescriptor<RoutineTask>(predicate: #Predicate { $0.id == id })).first
            else { throw Failure.notFound }
            row.isActive = active
        }
        try context.save()
    }

    /// No ceiling (decided with the user: it is their own ledger); never under `minimumPoints`.
    public static func setBasePoints(_ points: Int, forRoutine id: UUID, in context: ModelContext) throws {
        guard points >= minimumPoints else { throw Failure.belowMinimum(minimumPoints) }
        guard let row = try context.fetch(FetchDescriptor<RoutineTask>(predicate: #Predicate { $0.id == id })).first
        else { throw Failure.notFound }
        row.basePoints = points
        try context.save()
    }
}
