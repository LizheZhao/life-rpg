import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// The starter library is the file a fresh install is seeded from (`doc/starter_library.json`,
/// bundled into the app). These tests read the real file, so a bad edit to it fails here rather
/// than on a friend's phone, and check the loader's rules on small inline files.
struct StarterLibraryTests {
    private let shipped = Fixtures.docDir.appendingPathComponent("starter_library.json")

    private func shippedData() throws -> Data { try Data(contentsOf: shipped) }

    // MARK: the shipped file

    @Test func theShippedFileDecodes() throws {
        let lib = try StarterLibrary.decode(try shippedData())
        #expect(lib.quests.count > 60 && lib.routines.count > 10)
        for tier in Difficulty.allCases {
            #expect(lib.quests.contains { $0.difficulty == tier }, "no \(tier) quest")
        }
    }

    /// Epic is drawn on its own (`Epic`), which reads neither flag; `LibrarySave` already forces
    /// both off for an epic, so a starter epic must not claim them either.
    @Test func noEpicClaimsHiddenOrWeekend() throws {
        let lib = try StarterLibrary.decode(try shippedData())
        for q in lib.quests where q.difficulty == .epic {
            #expect(!q.hiddenEligible && !q.weekendOnly, "\(q.text)")
        }
    }

    @Test func everyRoutinePaysWithinItsTier() throws {
        let lib = try StarterLibrary.decode(try shippedData())
        for r in lib.routines {
            #expect(r.difficulty != .trivial && r.difficulty != .epic, "\(r.text) uses a tier a routine can't have")
            #expect(r.difficulty.range.contains(r.basePoints), "\(r.text): \(r.basePoints) is outside \(r.difficulty)")
        }
    }

    @Test func lightVersionsPointAtRealRoutinesAndAreNeverScheduled() throws {
        let lib = try StarterLibrary.decode(try shippedData())
        let byText = Dictionary(uniqueKeysWithValues: lib.routines.map { ($0.text, $0) })
        let lights = lib.routines.filter { !$0.downgradeOf.isEmpty }
        #expect(!lights.isEmpty)
        for light in lights {
            #expect(light.spec.isEmpty, "\(light.text) is scheduled on its own")
            for parent in light.downgradeOf {
                let p = try #require(byText[parent], "\(light.text) points at missing \(parent)")
                #expect(p.downgradeOf.isEmpty, "\(parent) is itself a light version")
            }
        }
        // Every scheduled routine has something to run on.
        for r in lib.routines where r.downgradeOf.isEmpty { #expect(!r.spec.isEmpty, "\(r.text)") }
    }

    @Test func noPersonalLinksShipWithTheFile() throws {
        let lib = try StarterLibrary.decode(try shippedData())
        for q in lib.quests {
            #expect(q.launchURLString == nil || ["ibooks://", "music://"].contains(q.launchURLString!), "\(q.text): \(q.launchURLString ?? "")")
        }
    }

    // MARK: installing

    @Test func installsIntoAnEmptyStoreAndPassesTheAudit() throws {
        let ctx = try Fixtures.context()
        let lib = try StarterLibrary.decode(try shippedData())
        let result = try StarterLibrary.install(try shippedData(), into: ctx)
        #expect(result.questTemplates == lib.quests.count && result.routineTasks == lib.routines.count)
        #expect(try ctx.fetchCount(FetchDescriptor<QuestTemplate>()) == lib.quests.count)
        #expect(try StoreAudit.issues(ctx).isEmpty)
        let routines = try ctx.fetch(FetchDescriptor<RoutineTask>())
        let parents = routines.filter { !$0.downgradeIDs.isEmpty }
        #expect(!parents.isEmpty)
        let ids = Set(routines.map(\.id))
        #expect(parents.allSatisfy { $0.downgradeIDs.allSatisfy(ids.contains) })
        #expect(routines.allSatisfy { $0.origin == .seed && !$0.isArchived })
    }

    @Test func installsOnlyOnce() throws {
        let ctx = try Fixtures.context()
        _ = try StarterLibrary.install(try shippedData(), into: ctx)
        let before = try ctx.fetchCount(FetchDescriptor<QuestTemplate>())
        let again = try StarterLibrary.install(try shippedData(), into: ctx)
        #expect(again.questTemplates == 0 && again.routineTasks == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<QuestTemplate>()) == before)
    }

    @Test func aStoreThatAlreadyHasARowIsLeftAlone() throws {
        let ctx = try Fixtures.context()
        Fixtures.quest(ctx, "Mine")
        try ctx.save()
        let result = try StarterLibrary.install(try shippedData(), into: ctx)
        #expect(result == .init(questTemplates: 0, routineTasks: 0))
        #expect(try ctx.fetchCount(FetchDescriptor<QuestTemplate>()) == 1)
    }

    /// The point of a starter library: a fresh install can live a fortnight on it.
    @Test func aFortnightOnTheStarterLibraryDrawsEveryDay() throws {
        let ctx = try Fixtures.context()
        _ = try StarterLibrary.install(try shippedData(), into: ctx)
        var rng = SeededRNG(seed: 11)
        for day in DayKey.range(from: "2026-09-14", through: "2026-09-27", in: Fixtures.tokyo) {
            try DayService.ensureToday(ctx, now: Fixtures.date(day, hour: 9), in: Fixtures.tokyo, rng: &rng)
            #expect(try !DayService.quests(on: day, in: ctx).isEmpty, "\(day) drew nothing")
        }
        #expect(try StoreAudit.issues(ctx).isEmpty)
    }

    // MARK: the loader's rules

    /// A small valid file, edited per test.
    private func file(version: Int = 1, quests: String? = nil, routines: String? = nil) -> Data {
        let q = quests ?? #"[{"key":"K","text":"Floss","difficulty":"trivial","hiddenEligible":false,"weekendOnly":false}]"#
        let r = routines ?? #"[{"key":"K","text":"Walk","difficulty":"easy","basePoints":10,"kind":"weekly","spec":"MON,THU","weeklyTarget":2,"flexibleWithinWeek":false,"countsForClear":true}]"#
        return Data(#"{"schemaVersion":\#(version),"quests":\#(q),"routines":\#(r)}"#.utf8)
    }

    private func routine(_ body: String) -> String {
        #"[{"key":"K","text":"R","difficulty":"easy","basePoints":10,"kind":"weekly","spec":"MON,THU","weeklyTarget":1,"flexibleWithinWeek":false,"countsForClear":true\#(body)}]"#
    }

    @Test func aSmallValidFileDecodes() throws {
        let lib = try StarterLibrary.decode(file())
        #expect(lib.quests.map(\.text) == ["Floss"] && lib.routines.map(\.text) == ["Walk"])
        #expect(lib.quests[0].isActive && lib.routines[0].isActive)
    }

    @Test func notJSONIsUnreadable() {
        #expect(throws: StarterLibraryError.unreadable) { try StarterLibrary.decode(Data("nope".utf8)) }
    }

    @Test func aNewerFileVersionIsRefused() {
        #expect(throws: StarterLibraryError.unsupportedVersion(2)) { try StarterLibrary.decode(file(version: 2)) }
    }

    @Test(arguments: [
        #"[{"key":"K","text":"X","difficulty":"huge","hiddenEligible":false,"weekendOnly":false}]"#,
        #"[{"key":"K","text":"  ","difficulty":"easy","hiddenEligible":false,"weekendOnly":false}]"#,
        #"[{"key":"k1","text":"A","difficulty":"easy","hiddenEligible":false,"weekendOnly":false},{"key":"k2","text":"A","difficulty":"hard","hiddenEligible":false,"weekendOnly":false}]"#,
        #"[{"key":"K","text":"A","difficulty":"easy","hiddenEligible":false,"weekendOnly":false,"autoVerifyRule":"jog:3"}]"#,
    ])
    func badQuestsAreRefused(quests: String) {
        #expect(throws: StarterLibraryError.self) { try StarterLibrary.decode(file(quests: quests)) }
    }

    @Test func badRoutinesAreRefused() {
        let bad = [
            routine("").replacingOccurrences(of: "MON,THU", with: "TUES"),
            routine("").replacingOccurrences(of: #""weeklyTarget":1"#, with: #""weeklyTarget":3"#),
            routine("").replacingOccurrences(of: #""kind":"weekly""#, with: #""kind":"sometimes""#),
            routine("").replacingOccurrences(of: #""difficulty":"easy""#, with: #""difficulty":"nope""#),
            routine(#","downgradeOf":["Nobody"]"#),
            routine(#","autoVerifyRule":"calendar_workout:zero""#),
            routine("").replacingOccurrences(of: #""spec":"MON,THU""#, with: #""spec":"""#),   // scheduled with no days
        ]
        for routines in bad {
            #expect(throws: StarterLibraryError.self, "\(routines)") { try StarterLibrary.decode(file(routines: routines)) }
        }
    }

    @Test func aLightVersionNeedsNoSchedule() throws {
        let routines = #"[{"key":"w","text":"Walk","difficulty":"easy","basePoints":10,"kind":"weekly","spec":"MON","weeklyTarget":1,"flexibleWithinWeek":false,"countsForClear":true},{"key":"s","text":"Short walk","difficulty":"easy","basePoints":5,"kind":"weekly","spec":"","weeklyTarget":1,"flexibleWithinWeek":false,"countsForClear":true,"downgradeOf":["Walk"]}]"#
        let ctx = try Fixtures.context()
        let result = try StarterLibrary.install(file(routines: routines), into: ctx)
        #expect(result.routineTasks == 2)
        let walk = try #require(try ctx.fetch(FetchDescriptor<RoutineTask>()).first { $0.text == "Walk" })
        #expect(walk.downgradeIDs.count == 1)
    }
}
