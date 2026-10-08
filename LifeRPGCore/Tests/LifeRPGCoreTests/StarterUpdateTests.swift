import Foundation
import SwiftData
import Testing
@testable import LifeRPGCore

/// An install that already has a library can still be offered what the starter library gained
/// since: rows are told apart by the key the starter file gives them (stamped on the row when it is
/// installed), never by their text, so a renamed or deleted row is not offered again. The user adds
/// what they want; nothing is added by itself.
struct StarterUpdateTests {
    private typealias R = (key: String, text: String, parents: [String])

    private func file(quests: [(String, String)], routines: [R] = []) -> Data {
        let q = quests.map {
            #"{"key":"\#($0.0)","text":"\#($0.1)","difficulty":"easy","hiddenEligible":false,"weekendOnly":false}"#
        }.joined(separator: ",")
        let r = routines.map { r -> String in
            let light = !r.parents.isEmpty
            let parents = r.parents.map { "\"\($0)\"" }.joined(separator: ",")
            return #"{"key":"\#(r.key)","text":"\#(r.text)","difficulty":"easy","basePoints":10,"kind":"weekly","spec":"\#(light ? "" : "MON")","weeklyTarget":1,"flexibleWithinWeek":false,"countsForClear":true\#(light ? #","downgradeOf":[\#(parents)]"# : "")}"#
        }.joined(separator: ",")
        return Data(#"{"schemaVersion":1,"quests":[\#(q)],"routines":[\#(r)]}"#.utf8)
    }

    private let v1 = [("floss", "Floss"), ("walk", "Walk outside")]
    private let v2 = [("floss", "Floss"), ("walk", "Walk outside"), ("dance", "Dance to a song"), ("tea", "Make tea")]

    private func installed(_ data: Data) throws -> ModelContext {
        let ctx = try Fixtures.context()
        try StarterLibrary.install(data, into: ctx)
        return ctx
    }

    private func quest(_ ctx: ModelContext, _ text: String) throws -> QuestTemplate {
        try #require(try ctx.fetch(FetchDescriptor<QuestTemplate>()).first { $0.text == text })
    }

    private func routine(_ ctx: ModelContext, _ text: String) throws -> RoutineTask {
        try #require(try ctx.fetch(FetchDescriptor<RoutineTask>()).first { $0.text == text })
    }

    private func offered(_ data: Data, in ctx: ModelContext, dismissed: Set<String> = []) throws -> [StarterUpdate.Item] {
        let lib = try StarterLibrary.decode(data)
        try StarterUpdate.claim(lib, in: ctx)
        return try StarterUpdate.offered(lib, in: ctx, dismissed: dismissed)
    }

    // MARK: keys in the file

    @Test func everyRowNeedsAUniqueKey() {
        let q = #"{"text":"A","difficulty":"easy","hiddenEligible":false,"weekendOnly":false"#
        for quests in [
            "[\(q)}]",                                                  // no key
            "[\(q),\"key\":\"  \"}]",                                   // blank key
            "[\(q),\"key\":\"a\"},\(q.replacingOccurrences(of: "\"A\"", with: "\"B\"")),\"key\":\"a\"}]",   // twice
        ] {
            let data = Data(#"{"schemaVersion":1,"quests":\#(quests),"routines":[]}"#.utf8)
            #expect(throws: StarterLibraryError.self, "\(quests)") { try StarterLibrary.decode(data) }
        }
    }

    @Test func theShippedFileKeysEveryRowAndKeepsThemUnique() throws {
        let data = try Data(contentsOf: Fixtures.docDir.appendingPathComponent("starter_library.json"))
        let lib = try StarterLibrary.decode(data)
        let keys = lib.quests.compactMap(\.starterKey) + lib.routines.compactMap(\.starterKey)
        #expect(keys.count == lib.quests.count + lib.routines.count)
        #expect(Set(lib.quests.compactMap(\.starterKey)).count == lib.quests.count)
        #expect(Set(lib.routines.compactMap(\.starterKey)).count == lib.routines.count)
    }

    @Test func installStampsTheKeysOnTheRows() throws {
        let ctx = try installed(file(quests: v1, routines: [("w", "Walk", [])]))
        #expect(try quest(ctx, "Floss").starterKey == "floss")
        #expect(try routine(ctx, "Walk").starterKey == "w")
    }

    // MARK: what is offered

    @Test func aFreshInstallIsOfferedNothing() throws {
        let ctx = try installed(file(quests: v1))
        #expect(try offered(file(quests: v1), in: ctx).isEmpty)
    }

    @Test func aGrownFileOffersExactlyTheNewRows() throws {
        let ctx = try installed(file(quests: v1))
        let items = try offered(file(quests: v2), in: ctx)
        #expect(items.map(\.text) == ["Dance to a song", "Make tea"])
        #expect(items.allSatisfy { $0.kind == .quest && $0.difficulty == .easy })
    }

    @Test func aRenamedRowIsNeverOfferedAgain() throws {
        let ctx = try installed(file(quests: v1))
        try LibraryEdit.rename("Floss every night", .quest, id: try quest(ctx, "Floss").id, in: ctx)
        #expect(try offered(file(quests: v1), in: ctx).isEmpty)
    }

    @Test func aDeletedRowIsNeverOfferedAgain() throws {
        let ctx = try installed(file(quests: v1))
        try LibraryEdit.archive(.quest, id: try quest(ctx, "Walk outside").id, in: ctx)
        #expect(try offered(file(quests: v1), in: ctx).isEmpty)
    }

    /// Rows from before keys existed carry none; they are matched by their words once, then keyed.
    @Test func rowsWithoutAKeyAreClaimedByTheirText() throws {
        let ctx = try Fixtures.context()
        Fixtures.quest(ctx, "floss")                      // another case
        let old = Fixtures.quest(ctx, "Walk outside")
        try ctx.save()
        try LibraryEdit.archive(.quest, id: old.id, in: ctx)    // an archived one counts as present
        let items = try offered(file(quests: v2), in: ctx)
        #expect(items.map(\.text) == ["Dance to a song", "Make tea"])
        #expect(try quest(ctx, "floss").starterKey == "floss" && old.starterKey == "walk")
    }

    @Test func aRowThatWasRenamedBeforeKeysExistedIsOfferedOnce() throws {
        let ctx = try Fixtures.context()
        Fixtures.quest(ctx, "Floss nightly")
        try ctx.save()
        #expect(try offered(file(quests: [("floss", "Floss")]), in: ctx).map(\.text) == ["Floss"])
    }

    @Test func dismissedRowsAreLeftOut() throws {
        let ctx = try installed(file(quests: v1))
        let items = try offered(file(quests: v2), in: ctx)
        let dismissed: Set<String> = [try #require(items.first).id]
        #expect(try offered(file(quests: v2), in: ctx, dismissed: dismissed).map(\.text) == ["Make tea"])
    }

    // MARK: adding

    @Test func addingTakesExactlyTheChosenRows() throws {
        let ctx = try installed(file(quests: v1))
        let lib = try StarterLibrary.decode(file(quests: v2))
        let items = try offered(file(quests: v2), in: ctx)
        let result = try StarterUpdate.add([items[0].id], from: lib, in: ctx)
        #expect(result.questTemplates == 1 && result.routineTasks == 0)
        let added = try quest(ctx, "Dance to a song")
        #expect(added.starterKey == "dance" && added.origin == .seed && added.isActive && !added.isArchived)
        #expect(try ctx.fetch(FetchDescriptor<QuestTemplate>()).allSatisfy { $0.text != "Make tea" })
        #expect(try offered(file(quests: v2), in: ctx).map(\.text) == ["Make tea"])
    }

    @Test func addingTwiceAddsNothingTheSecondTime() throws {
        let ctx = try installed(file(quests: v1))
        let lib = try StarterLibrary.decode(file(quests: v2))
        let ids = Set(try offered(file(quests: v2), in: ctx).map(\.id))
        try StarterUpdate.add(ids, from: lib, in: ctx)
        let again = try StarterUpdate.add(ids, from: lib, in: ctx)
        #expect(again == .init(questTemplates: 0, routineTasks: 0))
        #expect(try ctx.fetchCount(FetchDescriptor<QuestTemplate>()) == 4)
    }

    @Test func addingLeavesTheUsersOwnRowsAlone() throws {
        let ctx = try installed(file(quests: v1))
        let mine = try quest(ctx, "Floss")
        mine.affinity = 2; mine.lastCompletedDayKey = "2026-10-01"
        try LibraryEdit.setActive(false, .quest, id: mine.id, in: ctx)
        let lib = try StarterLibrary.decode(file(quests: v2))
        try StarterUpdate.add(Set(try offered(file(quests: v2), in: ctx).map(\.id)), from: lib, in: ctx)
        #expect(mine.affinity == 2 && mine.lastCompletedDayKey == "2026-10-01" && !mine.isActive)
    }

    @Test func unknownIdsAreIgnored() throws {
        let ctx = try installed(file(quests: v1))
        let lib = try StarterLibrary.decode(file(quests: v2))
        let result = try StarterUpdate.add(["quest:nope", "routine:floss"], from: lib, in: ctx)
        #expect(result == .init(questTemplates: 0, routineTasks: 0))
    }

    // MARK: lighter versions

    private let withLight: [R] = [("walk", "Walk", []), ("short", "Short walk", ["Walk"])]

    @Test func aNewLightVersionIsLinkedToItsExistingParent() throws {
        let ctx = try installed(file(quests: v1, routines: [("walk", "Walk", [])]))
        let grown = file(quests: v1, routines: withLight)
        let items = try offered(grown, in: ctx)
        #expect(items.map(\.text) == ["Short walk"] && items[0].isLightVersion)
        try StarterUpdate.add(Set(items.map(\.id)), from: try StarterLibrary.decode(grown), in: ctx)
        let parent = try routine(ctx, "Walk"), light = try routine(ctx, "Short walk")
        #expect(parent.downgradeIDs == [light.id])
    }

    @Test func aNewParentPicksUpALightVersionTheUserAlreadyHas() throws {
        let ctx = try installed(file(quests: v1, routines: [("walk", "Walk", []), ("other", "Other", [])]))
        // the file grows a light version of "Other" that already exists as a row under another name
        let light = RoutineTask(); light.text = "Short walk"; light.starterKey = "short"; ctx.insert(light)
        let grown = file(quests: v1, routines: [("walk", "Walk", []), ("other", "Other", []), ("run", "Run", []), ("short", "Short walk", ["Run"])])
        let items = try offered(grown, in: ctx)
        #expect(items.map(\.text) == ["Run"])
        try StarterUpdate.add(Set(items.map(\.id)), from: try StarterLibrary.decode(grown), in: ctx)
        #expect(try routine(ctx, "Run").downgradeIDs == [light.id])
    }

    @Test func aParentAndItsLightVersionAreAddedTogether() throws {
        let ctx = try installed(file(quests: v1))
        let grown = file(quests: v1, routines: withLight)
        let items = try offered(grown, in: ctx)
        #expect(items.map(\.text).sorted() == ["Short walk", "Walk"])
        let result = try StarterUpdate.add(Set(items.map(\.id)), from: try StarterLibrary.decode(grown), in: ctx)
        #expect(result.routineTasks == 2)
        #expect(try routine(ctx, "Walk").downgradeIDs == [try routine(ctx, "Short walk").id])
    }

    /// A lighter version is only ever reached through a routine; offering one nobody can reach is noise.
    @Test func aLightVersionWithNoParentAnywhereIsNotOffered() throws {
        let ctx = try installed(file(quests: v1))
        let grown = file(quests: v1, routines: [("walk", "Walk", []), ("short", "Short walk", ["Walk"])])
        let items = try offered(grown, in: ctx)
        let light = try #require(items.first { $0.isLightVersion })
        let withoutParent = try StarterUpdate.offered(try StarterLibrary.decode(grown), in: ctx, dismissed: [items.first { !$0.isLightVersion }!.id])
        #expect(!withoutParent.contains { $0.id == light.id })
    }

    @Test func addingPassesTheStoreAudit() throws {
        let ctx = try installed(file(quests: v1))
        let grown = file(quests: v2, routines: withLight)
        try StarterUpdate.add(Set(try offered(grown, in: ctx).map(\.id)), from: try StarterLibrary.decode(grown), in: ctx)
        #expect(try StoreAudit.issues(ctx).isEmpty)
    }
}
