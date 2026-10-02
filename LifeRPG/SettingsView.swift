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

    /// The pages the rows push. A row is a button with a chevron of its own: the system disclosure
    /// indicator cannot be coloured, and the chevron is `iconNeutral`.
    private enum Page: Hashable { case library, workoutDetection, design, debug }

    @Environment(\.modelContext) private var context
    @State private var transfer = DataTransfer()
    @State private var path: [Page] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button { path.append(.library) } label: {
                        row("Library", systemImage: "books.vertical", tint: .trivial, pushes: true)
                    }
                } header: {
                    header("Library")
                }
                .listRowBackground(LR.Color.surface)

                Section {
                    Button { path.append(.workoutDetection) } label: {
                        row("Workout detection", systemImage: "figure.run", tint: .easy, pushes: true)
                    }
                } header: {
                    header("Auto-verify")
                }
                .listRowBackground(LR.Color.surface)

                Section {
                    Button { transfer.prepareJSONExport(context) } label: {
                        row("History (JSON)", systemImage: "clock.arrow.circlepath", tint: .hidden)
                    }
                    Button { transfer.prepareCSVExport(context) } label: {
                        row("Ratings & comments (CSV)", systemImage: "star.bubble", tint: .hidden)
                    }
                    Button { transfer.importing = true } label: {
                        row("Restore from JSON…", systemImage: "square.and.arrow.down", tint: .hidden)
                    }
                    if let error = transfer.error {
                        Text(error).foregroundStyle(LR.Color.clay)
                    }
                } header: {
                    header("Data")
                }
                .listRowBackground(LR.Color.surface)

                Section {
                    Button { path.append(.design) } label: {
                        row("Design gallery", systemImage: "paintpalette", tint: .medium, pushes: true)
                    }
                } header: {
                    header("Design")
                }
                .listRowBackground(LR.Color.surface)

                Section {
                    Button { path.append(.debug) } label: {
                        row("Debug", systemImage: "wrench.and.screwdriver", tint: .hard, pushes: true)
                    }
                } header: {
                    header("Developer")
                }
                .listRowBackground(LR.Color.surface)
            }
            .listRowSeparatorTint(LR.Color.divider)
            .scrollContentBackground(.hidden)
            .background(LR.Color.canvas)
            .navigationTitle("Settings")
            .navigationDestination(for: Page.self) { page in
                switch page {
                case .library:
                    LibraryView(today: today)
                case .workoutDetection:
                    WorkoutDetectionView(refresh: refresh)
                case .design:
                    DesignGalleryView()
                        .navigationTitle("Design")
                        .navigationBarTitleDisplayMode(.inline)
                case .debug:
                    DebugView(seedStatus: seedStatus, today: today, sensorReport: sensorReport,
                              refresh: refresh)
                }
            }
            .dataTransfer(transfer, onImported: onImported)
        }
        .reservingTabBarSpace()
    }

    /// The icon sits in a 32 pt circle of its section's tint at 18%, in the neutral icon colour.
    private func row(_ title: LocalizedStringKey, systemImage: String, tint: QuestTint,
                     pushes: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(LR.Color.iconNeutral)
                .frame(width: 32, height: 32)
                .background(Circle().fill(LR.Color.sectionCircle(tint)))
                .accessibilityHidden(true)
            Text(title)
                .lr(.bodyStrong)
                .foregroundStyle(LR.Color.ink)
            if pushes {
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LR.Color.iconNeutral)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .lr(.heading)
            .foregroundStyle(LR.Color.sectionTitle)
            .textCase(nil)
    }
}

#Preview {
    SettingsView(seedStatus: "Preview", today: Date().dayKey, sensorReport: "",
                 refresh: {}, onImported: {})
        .modelContainer(for: LifeRPGSchema.models, inMemory: true)
}
