import LifeRPGCore
import SwiftData
import SwiftUI

/// Everything that is not the daily loop: the library, export and restore, the design gallery and
/// the developer page. Library and Debug are pushed here, so they carry no stack of their own.
struct SettingsView: View {
    let seedStatus: String
    let today: String
    let sensorReport: String
    let refresh: () -> Void
    /// Re-runs the day after a restore, so a backup that ends before today catches up at once
    /// instead of on the next foreground.
    let onImported: () -> Void

    @Environment(\.modelContext) private var context
    @State private var transfer = DataTransfer()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        LibraryView(today: today)
                    } label: {
                        row("Library", systemImage: "books.vertical")
                    }
                } header: {
                    header("Library")
                }
                .listRowBackground(LR.Color.surface)

                Section {
                    Button { transfer.prepareJSONExport(context) } label: {
                        row("History (JSON)", systemImage: "clock.arrow.circlepath")
                    }
                    Button { transfer.prepareCSVExport(context) } label: {
                        row("Ratings & comments (CSV)", systemImage: "star.bubble")
                    }
                    Button { transfer.importing = true } label: {
                        row("Restore from JSON…", systemImage: "square.and.arrow.down")
                    }
                    if let error = transfer.error {
                        Text(error).foregroundStyle(LR.Color.clay)
                    }
                } header: {
                    header("Data")
                }
                .listRowBackground(LR.Color.surface)

                Section {
                    NavigationLink {
                        DesignGalleryView()
                            .navigationTitle("Design")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        row("Design gallery", systemImage: "paintpalette")
                    }
                } header: {
                    header("Design")
                }
                .listRowBackground(LR.Color.surface)

                Section {
                    NavigationLink {
                        DebugView(seedStatus: seedStatus, today: today, sensorReport: sensorReport,
                                  refresh: refresh)
                    } label: {
                        row("Debug", systemImage: "wrench.and.screwdriver")
                    }
                } header: {
                    header("Developer")
                }
                .listRowBackground(LR.Color.surface)
            }
            .scrollContentBackground(.hidden)
            .background(LR.Color.canvas)
            .navigationTitle("Settings")
            .dataTransfer(transfer, onImported: onImported)
        }
        .reservingTabBarSpace()
    }

    private func row(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .lr(.bodyStrong)
            .foregroundStyle(LR.Color.ink)
    }

    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .lr(.heading)
            .foregroundStyle(LR.Color.inkSecondary)
            .textCase(nil)
    }
}

#Preview {
    SettingsView(seedStatus: "Preview", today: Date().dayKey, sensorReport: "",
                 refresh: {}, onImported: {})
        .modelContainer(for: LifeRPGSchema.models, inMemory: true)
}
