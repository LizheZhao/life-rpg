import LifeRPGCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// History export (JSON), the ratings-and-comments export (CSV folder) and restoring from JSON.
/// Moved out of the Today page unchanged: the state, the handlers, the save and open panels and
/// the "Replace all history?" confirmation (now the centered `MomentCard`). `error` is what the
/// page used to call `actionError`.
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
    /// What "Erase all records" is about to remove, while its confirmation is up. Nothing is deleted before then.
    var eraseCounts: EraseRecords.Result?

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

    func prepareErase(_ context: ModelContext) {
        do {
            eraseCounts = try EraseRecords.preview(in: context)
            error = nil
        } catch {
            self.error = "Couldn't read the records: \(error)"
        }
    }

    /// Erases, gives the opening balance again (a fresh start is a first launch for the economy) and
    /// forgets which days were handed to Apple Journal; the caller then draws today again.
    func performErase(_ context: ModelContext, onDone: () -> Void) {
        do {
            try EraseRecords.erase(in: context)
            try Economy.grantStartingBalanceIfNeeded(context, dayKey: Date().dayKey)
            UserDefaults.standard.removeObject(forKey: JournalSentLog.key)
            error = nil
            onDone()
        } catch {
            self.error = "Erase failed: \(error)"
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
        if s.libraryQuests + s.libraryRoutines > 0 {
            lines.append("The library is replaced too: \(s.libraryQuests) quest(s) and \(s.libraryRoutines) routine(s)"
                         + (s.libraryArchived > 0 ? ", \(s.libraryArchived) of them deleted (kept under Archived)" : "") + ".")
        }
        if !s.unmatchedLibrary.isEmpty {
            lines.append("\(s.unmatchedLibrary.count) quest(s) or routine(s) in the backup aren't in this library; "
                         + "their history is kept but won't link back.")
        }
        // An older backup (before the whole library was written): only put back, never taken from.
        let mine = s.userQuests + s.userRoutines
        if mine > 0 || s.libraryChanges > 0 {
            lines.append("Your library: " + [mine > 0 ? "\(s.userQuests) quest(s) and \(s.userRoutines) routine(s) of your own, "
                                              + "put back if missing" : nil,
                                              s.libraryChanges > 0 ? "\(s.libraryChanges) default(s) turned off or re-priced" : nil]
                .compactMap { $0 }.joined(separator: "; ") + ".")
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
    /// `onImported` runs after a restore has been applied. `hidesTabBar` is set while the
    /// confirmation card is up, so the floating bar fades out under the dim. Apply it outside the
    /// navigation stack, so the dim covers the navigation bar too.
    func dataTransfer(_ transfer: DataTransfer, hidesTabBar: Binding<Bool> = .constant(false),
                      onImported: @escaping () -> Void) -> some View {
        modifier(DataTransferModifier(transfer: transfer, hidesTabBar: hidesTabBar, onImported: onImported))
    }
}

private struct DataTransferModifier: ViewModifier {
    @Bindable var transfer: DataTransfer
    let hidesTabBar: Binding<Bool>
    let onImported: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            // Behind the card the page is not reachable, for VoiceOver either.
            .accessibilityHidden(transfer.importPlan != nil || transfer.eraseCounts != nil)
            .overlay {
                if let plan = transfer.importPlan {
                    MomentCard(header: MomentHeader(doodle: .notebook, tint: nil,
                                                    title: "Replace all history?", clay: true),
                               content: .notice(MomentNotice(
                                   message: transfer.importMessage(plan.summary),
                                   primary: "Replace everything",
                                   quiet: "Not yet",
                                   confirm: {
                                       transfer.performImport(plan, context, onImported: onImported)
                                       transfer.importPlan = nil
                                   },
                                   dismiss: { transfer.importPlan = nil })))
                }
            }
            .overlay {
                if let counts = transfer.eraseCounts {
                    MomentCard(header: MomentHeader(doodle: .notebook, tint: nil,
                                                    title: "Erase all records?", clay: true),
                               content: .notice(MomentNotice(
                                   message: counts.message,
                                   primary: "Erase everything",
                                   quiet: "Not yet",
                                   confirm: {
                                       transfer.performErase(context, onDone: onImported)
                                       transfer.eraseCounts = nil
                                   },
                                   dismiss: { transfer.eraseCounts = nil })))
                }
            }
            .animation(.easeOut(duration: reduceMotion ? 0.2 : 0.22), value: transfer.importPlan != nil || transfer.eraseCounts != nil)
            .onChange(of: transfer.importPlan != nil || transfer.eraseCounts != nil) { _, up in hidesTabBar.wrappedValue = up }
            .onDisappear { hidesTabBar.wrappedValue = false }
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
