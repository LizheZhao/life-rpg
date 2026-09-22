import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// The enum getters fall back (`?? .easy`), which keeps the app usable but would hide a quest
/// silently downgraded to E. The audit is what turns that into a visible count.
struct StoreAuditTests {
    private func makeContext() throws -> ModelContext {
        try Fixtures.context()
    }

    @Test func realSeedDataIsClean() throws {
        let ctx = try makeContext()
        try SeedImporter.mergeSeeds(ctx,
                                    sideQuestsCSV: Fixtures.csv("side_quests.csv"),
                                    routinesCSV: Fixtures.csv("routine_quests.csv"))
        #expect(try StoreAudit.issues(ctx).isEmpty)
    }

    @Test func unknownEnumRawIsCountedNotHidden() throws {
        let ctx = try makeContext()
        for _ in 0..<3 {
            let q = QuestTemplate()
            q.text = "legacy row"
            q.difficultyRaw = "legendary"
            ctx.insert(q)
        }
        let issues = try StoreAudit.issues(ctx)
        #expect(issues == [.init(model: "QuestTemplate", field: "difficultyRaw", value: "legendary", count: 3)])
        // The getter still falls back, which is exactly why the audit has to exist.
        #expect(try ctx.fetch(FetchDescriptor<QuestTemplate>()).allSatisfy { $0.difficulty == .easy })
    }

    @Test func badSpecsAndKeysAreReported() throws {
        let ctx = try makeContext()
        let r = RoutineTask()
        r.text = "typo routine"
        r.kindRaw = RecurrenceKind.weekly.rawValue
        r.spec = "TUES"
        r.autoVerifyRule = "mindfull:15"
        r.anchorWeekKey = "2026-W99"
        ctx.insert(r)

        let d = DailyQuest()
        d.dayKey = "2026-9-17"
        d.weekKey = "2026-W38"
        d.slotRaw = Difficulty.easy.rawValue
        ctx.insert(d)

        let issues = try StoreAudit.issues(ctx)
        #expect(issues.contains(.init(model: "RoutineTask", field: "spec", value: "TUES", count: 1)))
        #expect(issues.contains(.init(model: "RoutineTask", field: "autoVerifyRule", value: "mindfull:15", count: 1)))
        #expect(issues.contains(.init(model: "RoutineTask", field: "anchorWeekKey", value: "2026-W99", count: 1)))
        #expect(issues.contains(.init(model: "DailyQuest", field: "dayKey", value: "2026-9-17", count: 1)))
        #expect(!issues.contains { $0.field == "weekKey" })
    }

    /// An unreadable kind makes the spec unjudgeable, so only the kind is reported.
    @Test func unknownKindSuppressesTheSpecCheck() throws {
        let ctx = try makeContext()
        let r = RoutineTask()
        r.kindRaw = "fortnightly"
        r.spec = "MON"
        ctx.insert(r)
        let issues = try StoreAudit.issues(ctx)
        #expect(issues == [.init(model: "RoutineTask", field: "kindRaw", value: "fortnightly", count: 1)])
    }

    @Test func weekKeyValidation() {
        #expect(StoreAudit.isWeekKey("2026-W38"))
        #expect(StoreAudit.isWeekKey("2026-W53"))
        #expect(!StoreAudit.isWeekKey("2026-W54"))
        #expect(!StoreAudit.isWeekKey("2026-W00"))
        #expect(!StoreAudit.isWeekKey("2026-W3"))
        #expect(!StoreAudit.isWeekKey("2026-38"))
        #expect(!StoreAudit.isWeekKey(""))
    }
}
