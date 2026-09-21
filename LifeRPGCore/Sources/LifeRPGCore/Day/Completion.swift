import Foundation
import SwiftData

/// Completing a random quest: roll the points, write the ledger, start the template's cooldown.
///
/// **There is no undo.** Completion is final by design — the app is a single-user honesty system,
/// and a reversible checkbox turns the points roll into something you can re-roll until you like
/// the number. Everything here is therefore written once: the ledger entry is never deleted and
/// never reversed. A genuine mistake is corrected with a `kind = .adjust` entry.
public enum Completion {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case alreadyCompleted
        case trivialGroupIncomplete(remaining: Int)
        case indexOutOfRange

        public var description: String {
            switch self {
            case .alreadyCompleted: "already completed"
            case .trivialGroupIncomplete(let n): "\(n) item(s) of the T group still undone"
            case .indexOutOfRange: "no such T group item"
            }
        }
    }

    /// Completes a single-quest slot (or a T group whose three items are all ticked).
    /// Returns the points awarded.
    @discardableResult
    public static func complete(_ quest: DailyQuest,
                                tier: Tier,
                                in context: ModelContext,
                                now: Date = Date(),
                                rng: inout some RandomNumberGenerator) throws -> Int {
        guard quest.completedAt == nil else { throw Failure.alreadyCompleted }
        if quest.isTrivialGroup {
            let remaining = quest.trivialDone.filter { !$0 }.count
            guard remaining == 0 else { throw Failure.trivialGroupIncomplete(remaining: remaining) }
        }

        let points = Scoring.questPoints(quest, tier: tier, rng: &rng)
        let templates = try templates(of: quest, in: context)
        let cooldownBefore = templates.map(\.lastCompletedDayKey)

        quest.points = points
        quest.completedAt = now
        for template in templates {
            template.lastCompletedDayKey = quest.dayKey        // cooldown counts from completion
        }
        let entry = Economy.record(context, kind: .quest, points: points, dayKey: quest.dayKey,
                                   refID: quest.id, note: quest.textSnapshot, now: now)

        do {
            try context.save()
        } catch {
            // Nothing counts as done until the row is on disk. Without this the quest would read
            // as completed in memory while the ledger entry that pays for it was never written —
            // the page shows "+23", the balance doesn't move, and a second tap throws
            // `alreadyCompleted` because the in-memory object already looks finished.
            quest.points = nil
            quest.completedAt = nil
            for (template, previous) in zip(templates, cooldownBefore) {
                template.lastCompletedDayKey = previous
            }
            context.delete(entry)
            throw error
        }
        return points
    }

    /// Ticks one item of a T group; the group scores only once all three are ticked, which is what
    /// `complete` then does. Returns the points if that tick finished the group.
    @discardableResult
    public static func tickTrivialItem(_ quest: DailyQuest,
                                       at index: Int,
                                       tier: Tier,
                                       in context: ModelContext,
                                       now: Date = Date(),
                                       rng: inout some RandomNumberGenerator) throws -> Int? {
        guard quest.completedAt == nil else { throw Failure.alreadyCompleted }
        guard quest.trivialDone.indices.contains(index) else { throw Failure.indexOutOfRange }

        quest.trivialDone[index] = true
        do {
            guard quest.trivialDone.allSatisfy({ $0 }) else {
                try context.save()
                return nil
            }
            return try complete(quest, tier: tier, in: context, now: now, rng: &rng)
        } catch {
            quest.trivialDone[index] = false      // same rule: an unsaved tick is not a tick
            throw error
        }
    }

    /// The templates behind a quest — one, or the three of a T group. A template deleted since the
    /// draw simply drops out; the snapshot on the quest keeps the history readable either way.
    static func templates(of quest: DailyQuest, in context: ModelContext) throws -> [QuestTemplate] {
        let ids = quest.isTrivialGroup ? quest.trivialTemplateIDs : [quest.templateID].compactMap { $0 }
        guard !ids.isEmpty else { return [] }
        let wanted = Set(ids)
        return try context.fetch(FetchDescriptor<QuestTemplate>())
            .filter { wanted.contains($0.id) }
    }
}
