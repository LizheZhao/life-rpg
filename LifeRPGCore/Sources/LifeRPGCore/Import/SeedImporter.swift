import Foundation
import SwiftData

public enum SeedImporter {
    public struct Result: Equatable, Sendable {
        public var questTemplates: Int
        public var routineTasks: Int
    }

    /// Additive merge keyed on `text`: rows the DB doesn't have yet are inserted, rows it already
    /// has are left untouched — edits and soft-deletes made in the app always win. Rows removed
    /// from the CSV stay in the DB. Returns how many rows were inserted.
    ///
    /// Consequence: editing a text in the CSV reads as a new row, so the old one lives on next to
    /// it; and a hard-deleted quest comes back on the next launch (deactivate instead).
    @discardableResult
    public static func mergeSeeds(_ context: ModelContext,
                                  sideQuestsCSV: String,
                                  routinesCSV: String) throws -> Result {
        var result = Result(questTemplates: 0, routineTasks: 0)

        var knownQuests = Set(try context.fetch(FetchDescriptor<QuestTemplate>()).map(\.text))
        for seed in try SeedParser.sideQuests(csv: sideQuestsCSV)
        where knownQuests.insert(seed.text).inserted {          // also dedupes within the CSV
            context.insert(QuestTemplate(seed: seed))
            result.questTemplates += 1
        }

        var knownRoutines = Set(try context.fetch(FetchDescriptor<RoutineTask>()).map(\.text))
        for seed in try SeedParser.routines(csv: routinesCSV)
        where knownRoutines.insert(seed.text).inserted {
            context.insert(RoutineTask(seed: seed))
            result.routineTasks += 1
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
