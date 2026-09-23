import Foundation
import SwiftData
@testable import LifeRPGCore

/// Reads the real seed CSVs from `doc/` — they are the single source of truth.
enum Fixtures {
    static let docDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // LifeRPGCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // LifeRPGCore
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("doc")

    static func csv(_ name: String) throws -> String {
        try String(contentsOf: docDir.appendingPathComponent(name), encoding: .utf8)
    }
}

extension Fixtures {
    /// Creating containers concurrently crashes inside Core Data (SIGSEGV in
    /// `NSSQLEntity_DerivedAttributesExtension _generateTriggerSQL`: the shared model's trigger
    /// cache is mutated unlocked). Swift Testing runs suites in parallel, so creation is serialized.
    private static let containerLock = NSLock()

    /// A throwaway in-memory store with the real schema. Every test container must come from here.
    static func context() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try containerLock.withLock {
            try ModelContainer(for: LifeRPGSchema.current,
                               migrationPlan: LifeRPGMigrationPlan.self,
                               configurations: config)
        }
        return ModelContext(container)
    }

    @discardableResult
    static func quest(_ context: ModelContext,
                      _ text: String,
                      _ difficulty: Difficulty = .easy,
                      hidden: Bool = false,
                      weekendOnly: Bool = false,
                      affinity: Int = 0,
                      variants: [String] = [],
                      active: Bool = true,
                      completed: String? = nil,
                      served: String? = nil) -> QuestTemplate {
        let t = QuestTemplate()
        t.text = text
        t.difficulty = difficulty
        t.hiddenEligible = hidden
        t.weekendOnly = weekendOnly
        t.affinity = affinity
        t.variants = variants
        t.isActive = active
        t.lastCompletedDayKey = completed
        t.lastServedDayKey = served
        context.insert(t)
        return t
    }

    /// Enough of a library that a draw can't fail for want of candidates.
    static func stockLibrary(_ context: ModelContext, each: Int = 6) {
        for d in [Difficulty.trivial, .easy, .medium, .hard] {
            for i in 0..<each {
                quest(context, "\(d.rawValue) #\(i)", d, hidden: i == 0)
            }
        }
    }

    @discardableResult
    static func occurrence(_ context: ModelContext,
                           _ text: String,
                           due dayKey: String,
                           countsForClear: Bool = true,
                           completed: String? = nil) -> RoutineOccurrence {
        let o = RoutineOccurrence()
        o.textSnapshot = text
        o.dueDayKey = dayKey
        o.countsForClear = countsForClear
        o.completedDayKey = completed
        context.insert(o)
        return o
    }

    /// The timezone every date-sensitive test pins to, so a CI machine in another region agrees.
    static let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    static func date(_ dayKey: String, hour: Int = 9, in timeZone: TimeZone = tokyo) -> Date {
        var c = DateComponents()
        let parts = dayKey.split(separator: "-").map { Int($0)! }
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]; c.hour = hour
        return LifeCalendar.gregorian(timeZone).date(from: c)!
    }
}
