import Foundation

/// Reads the real seed CSVs from `doc/` — they are the single source of truth.
enum Fixtures {
    static let docDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // LifeRPGCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // LifeRPGCore
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("doc")

    static func csv(_ name: String) throws -> String {
        try String(contentsOf: docDir.appendingPathComponent(name), encoding: .utf8)
    }
}
