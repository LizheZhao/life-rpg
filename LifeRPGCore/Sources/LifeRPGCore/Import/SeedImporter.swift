import Foundation
import SwiftData

public enum SeedImporter {
    public struct Result: Equatable, Sendable {
        public var questTemplates: Int
        public var routineTasks: Int
    }

    /// Seeds each table from CSV only if that table is empty. After the first launch the DB copy
    /// is the user's own data; the CSVs in `doc/` are never re-applied over it.
    @discardableResult
    public static func seedIfEmpty(_ context: ModelContext,
                                   sideQuestsCSV: String,
                                   routinesCSV: String) throws -> Result {
        var result = Result(questTemplates: 0, routineTasks: 0)

        if try context.fetchCount(FetchDescriptor<QuestTemplate>()) == 0 {
            for seed in try SeedParser.sideQuests(csv: sideQuestsCSV) {
                context.insert(QuestTemplate(seed: seed))
                result.questTemplates += 1
            }
        }
        if try context.fetchCount(FetchDescriptor<RoutineTask>()) == 0 {
            for seed in try SeedParser.routines(csv: routinesCSV) {
                context.insert(RoutineTask(seed: seed))
                result.routineTasks += 1
            }
        }
        try context.save()
        return result
    }
}

extension QuestTemplate {
    convenience init(seed: SideQuestSeed) {
        self.init()
        text = seed.text
        difficulty = seed.difficulty
        intensity = seed.intensity
        hiddenEligible = seed.hiddenEligible
        weekendOnly = seed.weekendOnly
        // Only store an override when it differs from the difficulty default.
        if let days = seed.cooldownDays, days != seed.difficulty.cooldownDays {
            cooldownDaysOverride = days
        }
        variants = seed.variants
        launchURLString = seed.launchURLString
        autoVerifyRule = seed.autoVerifyRule
        isActive = seed.isActive
    }
}

extension RoutineTask {
    convenience init(seed: RoutineSeed) {
        self.init()
        text = seed.text
        basePoints = seed.basePoints
        difficulty = seed.difficulty
        intensity = seed.intensity
        kind = seed.kind
        spec = seed.spec
        weeklyTarget = seed.weeklyTarget
        flexibleWithinWeek = seed.flexibleWithinWeek
        countsForClear = seed.countsForClear
        degradedText = seed.degradedText
        launchURLString = seed.launchURLString
        autoVerifyRule = seed.autoVerifyRule
        isActive = seed.isActive
    }
}
