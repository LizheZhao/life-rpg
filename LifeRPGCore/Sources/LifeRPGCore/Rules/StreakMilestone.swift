import Foundation
import SwiftData

/// The one-off bonus a streak run pays at 7, 14, 30, 60 and 100 days and every 30 after
/// (`PLAN.md` §6 "Streak milestones"). Coins, not a multiplier: a break postpones the next bonus,
/// it doesn't dock every day after it.
///
/// Nothing is stored beside the ledger. A bonus is a `streak` entry whose `note` names its
/// threshold; a threshold counts as paid **for this run** when such an entry is dated on or after
/// the run's first day (`Streak.runStart`). So a new run after a real break earns 7 and 14 again,
/// and a run joined by a freeze keeps whatever either side already paid.
public enum StreakMilestone {
    /// Asserted as literals in the tests — the table is the spec.
    public static let fixed: [(days: Int, coins: Int)] = [(7, 50), (14, 100), (30, 250), (60, 400), (100, 600)]
    public static let recurringEvery = 30
    public static let recurringCoins = 300

    public struct Award: Equatable, Sendable {
        public var days: Int
        public var coins: Int
    }

    /// What reaching `days` pays, or nil when `days` isn't a threshold.
    public static func coins(at days: Int) -> Int? {
        if let hit = fixed.first(where: { $0.days == days }) { return hit.coins }
        let last = fixed.last!.days
        if days > last, (days - last) % recurringEvery == 0 { return recurringCoins }
        return nil
    }

    /// Every threshold up to and including `count`, lowest first.
    public static func thresholds(through count: Int) -> [Int] {
        var out = fixed.map(\.days).filter { $0 <= count }
        var next = fixed.last!.days + recurringEvery
        while next <= count {
            out.append(next)
            next += recurringEvery
        }
        return out
    }

    static let notePrefix = "Streak "

    /// The threshold a `streak` entry paid, read back from its note.
    public static func threshold(of entry: LedgerEntry) -> Int? {
        guard entry.kind == Economy.Kind.streak.rawValue, entry.note.hasPrefix(notePrefix) else { return nil }
        return Int(entry.note.dropFirst(notePrefix.count))
    }

    /// Thresholds the current run has reached and not yet been paid for.
    public static func due(days: Set<String>, frozen: Set<String>, ledger: [LedgerEntry],
                           today: String, in timeZone: TimeZone = .current) -> [Award] {
        let count = Streak.current(days: days, frozen: frozen, today: today, in: timeZone)
        guard let start = Streak.runStart(days: days, frozen: frozen, today: today, in: timeZone) else {
            return []
        }
        let paid = Set(ledger.filter { $0.dayKey >= start }.compactMap(threshold(of:)))
        return thresholds(through: count)
            .filter { !paid.contains($0) }
            .map { Award(days: $0, coins: coins(at: $0)!) }
    }

    /// Pays everything `due`, booked to `today`. Called after anything that can lengthen the run —
    /// a random quest completed (by hand or by auto-verify) and a freeze — and harmless to call
    /// again: a second call finds nothing due.
    @discardableResult
    public static func settle(_ context: ModelContext, today: String,
                              in timeZone: TimeZone = .current, now: Date = Date()) throws -> [Award] {
        let kind = Economy.Kind.streak.rawValue
        let awards = due(days: try Streak.completedDayKeys(context),
                         frozen: try Streak.frozenDayKeys(context),
                         ledger: try context.fetch(FetchDescriptor<LedgerEntry>(
                            predicate: #Predicate { $0.kind == kind })),
                         today: today, in: timeZone)
        guard !awards.isEmpty else { return [] }
        let entries = awards.map {
            Economy.record(context, kind: .streak, points: $0.coins, dayKey: today,
                           note: "\(notePrefix)\($0.days)", now: now)
        }
        do {
            try context.save()
        } catch {
            entries.forEach(context.delete)
            throw error
        }
        return awards
    }
}
