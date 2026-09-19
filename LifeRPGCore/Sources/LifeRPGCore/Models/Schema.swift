import SwiftData

public enum LifeRPGSchema {
    public static let models: [any PersistentModel.Type] = [
        QuestTemplate.self,
        RoutineTask.self,
        DailyQuest.self,
        RoutineOccurrence.self,
        Reward.self,
        LedgerEntry.self,
        DailyContext.self,
    ]
}
