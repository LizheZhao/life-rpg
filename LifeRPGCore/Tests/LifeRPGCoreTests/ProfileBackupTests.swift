import Foundation
import Testing
@testable import LifeRPGCore

/// The name travels in the backup (schema 11), so a restore onto a new phone, which skips the
/// intro because the store has history, still greets the person by name.
struct ProfileBackupTests {
    @Test func theNameIsWrittenCleaned() throws {
        let ctx = try Fixtures.context()
        let decoded = try JSONExport.decode(try JSONExport.data(ctx, profileName: "  Ryo \n Z "))
        #expect(decoded.schemaVersion == 11)
        #expect(decoded.profileName == "Ryo Z")
    }

    @Test func noNameIsWrittenAsNone() throws {
        let ctx = try Fixtures.context()
        #expect(try JSONExport.decode(try JSONExport.data(ctx)).profileName == nil)
        #expect(try JSONExport.decode(try JSONExport.data(ctx, profileName: "   ")).profileName == nil)
    }

    /// A file written before schema 11 has no name and still restores.
    @Test func anOlderFileHasNoNameAndStillReads() throws {
        let source = try Fixtures.context()
        var json = try #require(try JSONSerialization.jsonObject(with: try JSONExport.data(source, profileName: "Ryo")) as? [String: Any])
        json["schemaVersion"] = 10
        json.removeValue(forKey: "profileName")
        let data = try JSONSerialization.data(withJSONObject: json)
        let plan = try JSONImport.plan(data, against: try Fixtures.context())
        #expect(plan.snapshot.profileName == nil)
    }

    @Test func aRestoreGivesTheNameToAPhoneWithoutOne() {
        #expect(UserProfile.restoredName(fromBackup: "Ryo", local: nil) == "Ryo")
        #expect(UserProfile.restoredName(fromBackup: "Ryo", local: "  ") == "Ryo")
    }

    /// The name already on this phone is the person's latest answer; a backup never overwrites it.
    @Test func aRestoreKeepsTheNameThisPhoneHas() {
        #expect(UserProfile.restoredName(fromBackup: "Ryo", local: "Mei") == nil)
        #expect(UserProfile.restoredName(fromBackup: nil, local: nil) == nil)
        #expect(UserProfile.restoredName(fromBackup: "   ", local: nil) == nil)
    }
}
