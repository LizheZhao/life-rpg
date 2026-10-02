import LifeRPGCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// History export (JSON), the ratings-and-comments export (CSV folder) and restoring from JSON.
/// Moved out of the Today page unchanged: the state, the handlers, the save and open panels and
/// the "Replace all history?" confirmation. `error` is what the page used to call `actionError`.
@MainActor @Observable
final class DataTransfer {
    var error: String?
    /// One export at a time, through one `fileExporter` — the JSON dump and the CSV folder are
    /// the same kind of thing to the save dialog, so they don't need a presentation each.
    var pendingExport: ExportDocument?
    var exporting = false
    var importing = false
    /// A decoded backup waiting for the overwrite to be confirmed. Nothing is written until then.
    var importPlan: JSONImport.Plan?

    func prepareJSONExport(_ context: ModelContext) {
        export { .json(try JSONExport.data(context), name: JSONExport.filename()) }
    }

    func prepareCSVExport(_ context: ModelContext) {
        export { .folder(try CSVExport.files(context), name: CSVExport.folderName()) }
    }

    /// Reads and maps the file; writes nothing — the alert asks first.
    func prepareImport(_ result: Result<URL, Error>, _ context: ModelContext) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            importPlan = try JSONImport.plan(try Data(contentsOf: url), against: context)
            error = nil
        } catch {
            self.error = "Import failed: \(error)"
        }
    }

    func performImport(_ plan: JSONImport.Plan, _ context: ModelContext, onImported: () -> Void) {
        do {
            try JSONImport.apply(plan, to: context)
            error = nil
            onImported()
        } catch {
            self.error = "Import failed: \(error)"
        }
    }

    func importMessage(_ s: JSONImport.Summary) -> String {
        let days = [s.firstDayKey, s.lastDayKey].compactMap { $0 }
        var lines = [
            "Backup exported \(s.exportedAt.formatted(date: .abbreviated, time: .shortened))"
                + (days.isEmpty ? "" : ", covering \(days.joined(separator: " – "))") + ".",
            "\(s.dailyQuests) quests, \(s.routineOccurrences) routines, \(s.ledgerEntries) ledger entries, "
                + "\(s.ratings) ratings, \(s.comments) comments, \(s.rewards) rewards.",
            "Balance after restoring: \(s.balance).",
            "Everything in this app's history is replaced by the backup.",
        ]
        if !s.unmatchedLibrary.isEmpty {
            lines.append("\(s.unmatchedLibrary.count) quest(s) or routine(s) in the backup aren't in this library; "
                         + "their history is kept but won't link back.")
        }
        return lines.joined(separator: "\n\n")
    }

    /// Builds the document, then opens the system save dialog. The dialog is a separate process
    /// and can take a second or two to come up the first time — it is not instant.
    private func export(_ build: () throws -> ExportDocument) {
        do {
            pendingExport = try build()
            exporting = true
        } catch {
            self.error = "Export failed: \(error)"
        }
    }
}

extension View {
    /// Attaches the open panel, the save panel and the overwrite confirmation for `transfer`.
    /// `onImported` runs after a restore has been applied.
    func dataTransfer(_ transfer: DataTransfer, onImported: @escaping () -> Void) -> some View {
        modifier(DataTransferModifier(transfer: transfer, onImported: onImported))
    }
}

private struct DataTransferModifier: ViewModifier {
    @Bindable var transfer: DataTransfer
    let onImported: () -> Void

    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $transfer.importing, allowedContentTypes: [.json]) { result in
                transfer.prepareImport(result, context)
            }
            .fileExporter(isPresented: $transfer.exporting,
                          document: transfer.pendingExport,
                          contentType: transfer.pendingExport?.contentType ?? .json,
                          defaultFilename: transfer.pendingExport?.filename) { result in
                if case .failure(let error) = result { transfer.error = "Export failed: \(error)" }
                transfer.pendingExport = nil
            }
            .alert("Replace all history?", isPresented: Binding(
                get: { transfer.importPlan != nil }, set: { if !$0 { transfer.importPlan = nil } }
            ), presenting: transfer.importPlan) { plan in
                Button("Replace", role: .destructive) {
                    transfer.performImport(plan, context, onImported: onImported)
                }
                Button("Cancel", role: .cancel) {}
            } message: { plan in
                Text(transfer.importMessage(plan.summary))
            }
    }
}

/// Anything the page exports: the JSON history dump, or the feedback logs as a folder of CSVs.
/// One document type, because one `fileExporter` has to be able to present either.
/// Export only — the JSON comes back in through `fileImporter` and `JSONImport`, not this type.
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .folder] }

    let contentType: UTType
    let filename: String
    private let wrapper: FileWrapper

    static func json(_ data: Data, name: String) -> ExportDocument {
        ExportDocument(contentType: .json, filename: name,
                       wrapper: FileWrapper(regularFileWithContents: data))
    }

    static func folder(_ files: [CSVExport.File], name: String) -> ExportDocument {
        var children: [String: FileWrapper] = [:]
        for file in files {
            children[file.name] = FileWrapper(regularFileWithContents: Data(file.contents.utf8))
        }
        return ExportDocument(contentType: .folder, filename: name,
                              wrapper: FileWrapper(directoryWithFileWrappers: children))
    }

    private init(contentType: UTType, filename: String, wrapper: FileWrapper) {
        self.contentType = contentType
        self.filename = filename
        self.wrapper = wrapper
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { wrapper }
}
