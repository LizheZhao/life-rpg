import Foundation
import SwiftData

public enum StarterLibraryError: Error, Equatable, CustomStringConvertible {
    /// Not JSON, or not this file's shape.
    case unreadable
    /// Written for a newer build than this one.
    case unsupportedVersion(Int)
    /// A value nothing could read back (`where` says which row).
    case invalid(String)

    public var description: String {
        switch self {
        case .unreadable: "The starter library isn't readable."
        case .unsupportedVersion(let v): "The starter library is version \(v); this build reads version \(StarterLibrary.fileVersion)."
        case .invalid(let why): "The starter library has a bad value: \(why)"
        }
    }
}

/// The library a fresh install starts from: `doc/starter_library.json`, bundled into the app.
/// Quests and routines as the user would have written them in the Library — a quest's tier, the
/// two flags, its cooldown and prompt variants; a routine's tier, points and schedule, with its
/// lighter versions as routines of their own that name their parents (`downgradeOf`).
///
/// Decoding checks everything the app would otherwise fail on silently: an unparseable schedule
/// never comes due (no penalty, no row on the Today page), a target above the days offered is a
/// shortfall every Sunday, and a lighter version pointing at nothing is never offered. It then
/// installs once, into an empty store (`SeedImporter`), stamping each row with its key; from then on
/// the store is the truth, and `StarterUpdate` can offer what a later version of the file adds.
public struct StarterLibrary: Equatable, Sendable {
    public static let fileVersion = 1

    public var quests: [SideQuestSeed]
    public var routines: [RoutineSeed]

    public static func decode(_ data: Data) throws -> StarterLibrary {
        struct Probe: Decodable { var schemaVersion: Int }
        guard let probe = try? JSONDecoder().decode(Probe.self, from: data) else { throw StarterLibraryError.unreadable }
        guard probe.schemaVersion <= fileVersion else { throw StarterLibraryError.unsupportedVersion(probe.schemaVersion) }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { throw StarterLibraryError.unreadable }
        return try file.library()
    }

    /// Starts an empty store from `data`, once; a store with any library row is left as it is.
    @discardableResult
    public static func install(_ data: Data, into context: ModelContext) throws -> SeedImporter.Result {
        let library = try decode(data)
        return try SeedImporter.seedIfEmpty(context, quests: library.quests, routines: library.routines)
    }

    // MARK: the file's shape

    private struct File: Decodable {
        var schemaVersion: Int
        var quests: [Quest]
        var routines: [Routine]

        struct Quest: Decodable {
            var key: String
            var text: String
            var difficulty: String
            var hiddenEligible: Bool
            var weekendOnly: Bool
            var cooldownDays: Int?
            var variants: [String]?
            var launchURL: String?
            var autoVerifyRule: String?
        }

        struct Routine: Decodable {
            var key: String
            var text: String
            var difficulty: String
            var basePoints: Int
            var kind: String
            var spec: String
            var weeklyTarget: Int
            var flexibleWithinWeek: Bool
            var countsForClear: Bool
            var autoVerifyRule: String?
            var downgradeOf: [String]?
        }

        func library() throws -> StarterLibrary {
            var seen = Set<String>()
            var keys = Set<String>()
            let quests = try quests.map { q -> SideQuestSeed in
                let text = q.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = try Self.checkKey(q.key, on: text, seen: &keys)
                guard !text.isEmpty else { throw invalid("a quest has no text") }
                guard seen.insert(text).inserted else { throw invalid("quest '\(text)' is listed twice") }
                guard let tier = Difficulty(rawValue: q.difficulty) else { throw invalid("'\(text)' has the tier '\(q.difficulty)'") }
                if let rule = q.autoVerifyRule { try Self.checkRule(rule, on: text) }
                return SideQuestSeed(text: text, difficulty: tier, hiddenEligible: q.hiddenEligible,
                                     weekendOnly: q.weekendOnly, cooldownDays: q.cooldownDays,
                                     autoVerifyRule: q.autoVerifyRule, launchURLString: q.launchURL,
                                     variants: q.variants ?? [], isActive: true, starterKey: key)
            }

            seen.removeAll()
            keys.removeAll()
            let texts = Set(routines.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) })
            let routines = try routines.map { r -> RoutineSeed in
                let text = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = try Self.checkKey(r.key, on: text, seen: &keys)
                guard !text.isEmpty else { throw invalid("a routine has no text") }
                guard seen.insert(text).inserted else { throw invalid("routine '\(text)' is listed twice") }
                guard let tier = Difficulty(rawValue: r.difficulty) else { throw invalid("'\(text)' has the tier '\(r.difficulty)'") }
                guard let kind = RecurrenceKind(rawValue: r.kind) else { throw invalid("'\(text)' has the kind '\(r.kind)'") }
                if let rule = r.autoVerifyRule { try Self.checkRule(rule, on: text) }
                let parents = (r.downgradeOf ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                for parent in parents where !texts.contains(parent) {
                    throw invalid("'\(text)' is a lighter version of '\(parent)', which isn't in the file")
                }
                var spec = r.spec
                var target = r.weeklyTarget
                if parents.isEmpty {
                    // A scheduled routine must be readable by the calendar, and its target reachable.
                    let frequency: FrequencySpec
                    do { frequency = try FrequencySpec.parse(kind: kind, spec: r.spec) } catch let error as FrequencyError {
                        throw invalid("'\(text)': \(error.reason)")
                    }
                    guard target >= 1 else { throw invalid("'\(text)' needs a weekly target of at least 1") }
                    if let available = frequency.nominalWeeklyCount, target > available {
                        throw invalid("'\(text)': '\(r.spec)' only comes due \(available)x a week, not \(target)x")
                    }
                } else {
                    // Never scheduled on its own; whatever was written there would be data nothing reads.
                    spec = ""; target = 1
                }
                return RoutineSeed(text: text, kind: parents.isEmpty ? kind : .weekly, spec: spec,
                                   weeklyTarget: target, basePoints: r.basePoints, difficulty: tier,
                                   flexibleWithinWeek: r.flexibleWithinWeek, countsForClear: r.countsForClear,
                                   isActive: true, downgradeOf: parents, autoVerifyRule: r.autoVerifyRule,
                                   launchURLString: nil, starterKey: key)
            }
            return StarterLibrary(quests: quests, routines: routines)
        }

        private func invalid(_ why: String) -> StarterLibraryError { .invalid(why) }

        /// The row's stable identity across starter-library versions: never reused, never changed once
        /// a build has shipped it (the text may be reworded freely, the key may not).
        private static func checkKey(_ raw: String, on text: String, seen: inout Set<String>) throws -> String {
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw StarterLibraryError.invalid("'\(text)' has no key") }
            guard seen.insert(key).inserted else { throw StarterLibraryError.invalid("the key '\(key)' is used twice") }
            return key
        }

        private static func checkRule(_ raw: String, on text: String) throws {
            do { _ = try AutoVerifyRule.parse(raw) } catch let error as AutoVerifyError {
                throw StarterLibraryError.invalid("'\(text)': \(error.reason)")
            }
        }
    }
}
