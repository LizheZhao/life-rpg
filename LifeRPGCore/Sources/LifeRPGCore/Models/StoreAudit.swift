import Foundation
import SwiftData

/// Scans the store for strings nothing can read back.
///
/// The enum accessors fall back (`?? .easy` / `?? .low` / `?? .weekly` / `?? .normal`), which is
/// right for keeping the app usable but wrong for staying silent: a quest downgraded to E would
/// score and cool down wrong forever. Nothing invalid can get in through the CSV path — the seed
/// parser rejects it — but JSON import and any future enum rename can, so run this after an
/// import and surface the count instead of letting the fallback hide it.
public enum StoreAudit {
    public struct Issue: Equatable, Sendable, CustomStringConvertible {
        public var model: String
        public var field: String
        public var value: String
        public var count: Int

        public var description: String { "\(model).\(field) = '\(value)' ×\(count)" }
    }

    public static func issues(_ context: ModelContext) throws -> [Issue] {
        var found: [Key: Int] = [:]
        func check(_ model: String, _ field: String, _ value: String?, _ isValid: (String) -> Bool) {
            guard let value, !isValid(value) else { return }
            found[Key(model: model, field: field, value: value), default: 0] += 1
        }

        let difficulty = { Difficulty(rawValue: $0) != nil }
        let intensity = { Intensity(rawValue: $0) != nil }

        for q in try context.fetch(FetchDescriptor<QuestTemplate>()) {
            check("QuestTemplate", "difficultyRaw", q.difficultyRaw, difficulty)
            check("QuestTemplate", "intensityRaw", q.intensityRaw, intensity)
            check("QuestTemplate", "autoVerifyRule", q.autoVerifyRule, isAutoVerify)
            check("QuestTemplate", "lastServedDayKey", q.lastServedDayKey, { DayKey.isValid($0) })
            check("QuestTemplate", "lastCompletedDayKey", q.lastCompletedDayKey, { DayKey.isValid($0) })
        }

        for r in try context.fetch(FetchDescriptor<RoutineTask>()) {
            check("RoutineTask", "difficultyRaw", r.difficultyRaw, difficulty)
            check("RoutineTask", "intensityRaw", r.intensityRaw, intensity)
            check("RoutineTask", "kindRaw", r.kindRaw, { RecurrenceKind(rawValue: $0) != nil })
            // Only meaningful once the kind itself reads back.
            if RecurrenceKind(rawValue: r.kindRaw) != nil {
                check("RoutineTask", "spec", r.spec, { (try? FrequencySpec.parse(kind: r.kind, spec: $0)) != nil })
            }
            check("RoutineTask", "autoVerifyRule", r.autoVerifyRule, isAutoVerify)
            check("RoutineTask", "anchorWeekKey", r.anchorWeekKey, isWeekKey)
            check("RoutineTask", "lastCompletedDayKey", r.lastCompletedDayKey, { DayKey.isValid($0) })
        }

        for d in try context.fetch(FetchDescriptor<DailyQuest>()) {
            check("DailyQuest", "slotRaw", d.slotRaw, difficulty)
            check("DailyQuest", "dayKey", d.dayKey, { DayKey.isValid($0) })
            check("DailyQuest", "weekKey", d.weekKey, isWeekKey)
        }

        for o in try context.fetch(FetchDescriptor<RoutineOccurrence>()) {
            check("RoutineOccurrence", "dueDayKey", o.dueDayKey, { DayKey.isValid($0) })
            check("RoutineOccurrence", "weekKey", o.weekKey, isWeekKey)
            check("RoutineOccurrence", "completedDayKey", o.completedDayKey, { DayKey.isValid($0) })
        }

        for c in try context.fetch(FetchDescriptor<DailyContext>()) {
            check("DailyContext", "tierRaw", c.tierRaw, { Tier(rawValue: $0) != nil })
            check("DailyContext", "dayKey", c.dayKey, { DayKey.isValid($0) })
        }

        let feedbackTarget = { FeedbackTarget(rawValue: $0) != nil }

        for r in try context.fetch(FetchDescriptor<QuestRating>()) {
            check("QuestRating", "targetKindRaw", r.targetKindRaw, feedbackTarget)
            check("QuestRating", "dayKey", r.dayKey, { DayKey.isValid($0) })
        }

        for c in try context.fetch(FetchDescriptor<QuestComment>()) {
            check("QuestComment", "targetKindRaw", c.targetKindRaw, feedbackTarget)
            check("QuestComment", "dayKey", c.dayKey, { DayKey.isValid($0) })
        }

        for e in try context.fetch(FetchDescriptor<LedgerEntry>()) {
            check("LedgerEntry", "dayKey", e.dayKey, { DayKey.isValid($0) })
        }

        return found
            .map { Issue(model: $0.key.model, field: $0.key.field, value: $0.key.value, count: $0.value) }
            .sorted { ($0.model, $0.field, $0.value) < ($1.model, $1.field, $1.value) }
    }

    private static func isAutoVerify(_ raw: String) -> Bool {
        (try? AutoVerifyRule.parse(raw)) != nil
    }

    /// `"2026-W38"`.
    public static func isWeekKey(_ raw: String) -> Bool {
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 4, Int(parts[0]) != nil,
              parts[1].count == 3, parts[1].first == "W",
              let week = Int(parts[1].dropFirst()), (1...53).contains(week)
        else { return false }
        return true
    }

    private struct Key: Hashable {
        var model: String
        var field: String
        var value: String
    }
}
