import SwiftUI
import UniformTypeIdentifiers

/// Shown when the `ModelContainer` can't be opened — almost always a failed migration.
/// The store file is left untouched, so reinstalling the previous build recovers the data.
struct StartupErrorView: View {
    let error: Error

    @State private var isExporting = false
    @State private var exportResult: String?

    private var storeFiles: [URL] { StoreFiles.locate() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Database didn't open", systemImage: "exclamationmark.triangle.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.orange)

                Text("Your data has not been touched or deleted. Export the raw store first, then reinstall the previous build to get back in and fix the migration.")
                    .foregroundStyle(.secondary)

                rescueSection

                Text(String(describing: error))
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                Button("Copy error") {
                    UIPasteboard.general.string = String(describing: error)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
    }

    /// Reads the store files straight off disk, bypassing SwiftData — the only export that still
    /// works when the container won't open.
    @ViewBuilder
    private var rescueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isExporting = true
            } label: {
                Label("Export raw store", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .disabled(storeFiles.isEmpty)

            if storeFiles.isEmpty {
                Text("No store file found in Application Support.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(storeFiles.count) file(s), \(ByteCountFormatter.string(fromByteCount: Int64(StoreFiles.totalBytes), countStyle: .file)) — includes the -wal sidecar, which can hold uncheckpointed writes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let exportResult {
                Text(exportResult)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .fileExporter(isPresented: $isExporting,
                      document: StoreArchiveDocument(files: storeFiles),
                      contentType: .folder,
                      defaultFilename: StoreFiles.defaultFilename()) { result in
            switch result {
            case .success(let url): exportResult = "Saved to \(url.lastPathComponent)"
            case .failure(let error): exportResult = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    StartupErrorView(error: CocoaError(.fileReadCorruptFile))
}
