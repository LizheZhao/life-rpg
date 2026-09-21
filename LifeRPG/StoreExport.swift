import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// The raw SwiftData store files on disk.
///
/// This is the rescue path: it reads the files directly and never goes through SwiftData, so it
/// works precisely when the container refuses to open — a failed migration, a schema the build
/// can't read. Get the folder off the phone first, then fix the migration.
enum StoreFiles {
    /// `default.store` plus its `-wal` / `-shm` sidecars. The WAL can hold days of writes that
    /// never got checkpointed, so exporting the `.store` alone is not enough.
    static func locate() -> [URL] {
        let fm = FileManager.default
        guard let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                        appropriateFor: nil, create: false),
              let entries = try? fm.contentsOfDirectory(at: support, includingPropertiesForKeys: nil)
        else { return [] }

        // Any `*.store` and its sidecars — the default is `default.store`, but a custom
        // `ModelConfiguration` would put a differently named one in the same directory.
        return entries
            .filter { url in
                let name = url.lastPathComponent
                return name.hasSuffix(".store") || name.hasSuffix(".store-wal") || name.hasSuffix(".store-shm")
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static var totalBytes: Int {
        locate().reduce(0) { sum, url in
            sum + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    static func defaultFilename(now: Date = Date()) -> String {
        "LifeRPG-store-\(now.dayKeyForFilename)"
    }
}

private extension Date {
    /// Local calendar day, spelled the same way as a `dayKey`.
    var dayKeyForFilename: String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let c = cal.dateComponents([.year, .month, .day], from: self)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}

/// Exports the store files as a folder, so the `.store` and its WAL stay together.
struct StoreArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }

    private let files: [URL]

    init(files: [URL]) { self.files = files }

    /// Export only — importing a store back is Stage 6's JSON path, not a file copy.
    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        var children: [String: FileWrapper] = [:]
        for url in files {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            children[url.lastPathComponent] = FileWrapper(regularFileWithContents: data)
        }
        return FileWrapper(directoryWithFileWrappers: children)
    }
}
