import Foundation
import LifeRPGCore
import SwiftUI
import UniformTypeIdentifiers

/// The rating and comment logs, exported as a folder of CSVs.
///
/// A folder rather than one file because the two logs have different shapes, and CSV rather than
/// JSON because the destination is a spreadsheet or a diff against `doc/*.csv` — the history dump
/// next to it already covers the machine-readable case.
struct FeedbackCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }

    let files: [CSVExport.File]

    init(files: [CSVExport.File]) { self.files = files }

    /// Export only — ratings and comments come back in with the JSON restore (`JSONImport`).
    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        var children: [String: FileWrapper] = [:]
        for file in files {
            children[file.name] = FileWrapper(regularFileWithContents: Data(file.contents.utf8))
        }
        return FileWrapper(directoryWithFileWrappers: children)
    }
}
