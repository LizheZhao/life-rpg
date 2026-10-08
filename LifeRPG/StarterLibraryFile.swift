import Foundation
import LifeRPGCore

/// The starter library bundled with the app (`doc/starter_library.json`, through a symlink in
/// `LifeRPG/Seed/`). Seeds an empty store at launch and is what Library offers new rows from.
enum StarterLibraryFile {
    static func data() throws -> Data {
        guard let url = Bundle.main.url(forResource: "starter_library", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "starter_library.json"])
        }
        return try Data(contentsOf: url)
    }

    static func library() throws -> StarterLibrary { try StarterLibrary.decode(try data()) }
}
