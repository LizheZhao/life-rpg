import LifeRPGCore
import SwiftData
import SwiftUI

/// Everything that is not the daily loop: the library, export and restore, the design gallery and
/// the developer page. Library and Debug are pushed here, so they carry no stack of their own.
struct SettingsView: View {
    let seedStatus: String
    let today: String
    let sensorReport: String
    let check: WorkoutCheck?
    let refresh: () async -> Void
    /// Re-runs the day after a restore, so a backup that ends before today catches up at once
    /// instead of on the next foreground.
    let onImported: () -> Void
    /// Set while the restore confirmation card is up, so the floating tab bar fades out under the dim.
    var hidesTabBar: Binding<Bool> = .constant(false)
    /// Plays the first-launch intro again.
    var showIntro: () -> Void = {}

    /// The pages the rows push. A row is a button with a chevron of its own: the system disclosure
    /// indicator cannot be coloured, and the chevron is `iconNeutral`.
    private enum Page: Hashable { case library, workoutDetection, reminders, journal, design, debug }

    @Environment(\.modelContext) private var context
    @State private var transfer = DataTransfer()
    @State private var path: [Page] = []
    @AppStorage(ProfileKeys.name) private var userName = ""
    @State private var editingName = false
    @AppStorage(RecoveryKeys.first) private var recoveryFirst = ""
    @AppStorage(RecoveryKeys.last) private var recoveryLast = ""

    /// On: from today through two weeks out. Off: cleared; days already planned as recovery keep
    /// their mark, so they are still judged without a charge.
    private var recoveryOn: Binding<Bool> {
        Binding(get: { !recoveryLast.isEmpty }, set: { on in
            recoveryFirst = on ? today : ""
            recoveryLast = on ? (DayKey.adding(13, to: today) ?? today) : ""
            Task { await refresh() }
        })
    }

    private var recoveryLastDate: Binding<Date> {
        Binding(get: { DayKey.date(recoveryLast) ?? Date() }, set: { date in
            recoveryLast = max(date.dayKey, today)
            Task { await refresh() }
        })
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button { editingName = true } label: {
                        HStack {
                            Text("Your name").lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                            Spacer()
                            Text(userName.isEmpty ? "Not set" : userName)
                                .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                                .lineLimit(1)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(LR.Color.iconNeutral).accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .accessibilityHint("Changes the name the greeting uses")
                    Button(action: showIntro) {
                        row("Show the intro again", systemImage: "sparkles", tint: .hidden, pushes: true)
                    }
                    .accessibilityHint("Walks through how the app works")
                } header: {
                    header("You")
                }
                .listRowBackground(LR.Color.surface)

                Section {
                    Toggle(isOn: recoveryOn) {
                        Text("Recovery").lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                    }
                    .tint(LR.Color.accent)
                    .frame(minHeight: 44)
                    .accessibilityHint("Only trivial and easy quests, no epic and no penalties until the last day")
                    if !recoveryLast.isEmpty {
                        DatePicker(selection: recoveryLastDate,
                                   in: (DayKey.date(today) ?? Date())...,
                                   displayedComponents: .date) {
                            Text("Last day").lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                        }
                    }
                } header: {
                    header("Recovery")
                } footer: {
                    Text("Each day draws only trivial and easy quests. Routines harder than easy switch to an easy light version, or wait until you're back. No new epic, and nothing is charged for what stays undone.")
                        .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                }
                .listRowBackground(LR.Color.surface)

                Section {
                    Button { path.append(.library) } label: {
                        row("Library", systemImage: "books.vertical", tint: .trivial, pushes: true)
                    }
                    .accessibilityHint("Opens your quests and routines")
                } header: {
                    header("Library")
                }
                .listRowBackground(LR.Color.surface)

                Section {
                    Button { path.append(.workoutDetection) } label: {
                        row("Workout detection", systemImage: "figure.run", tint: .easy, pushes: true)
                    }
                    .accessibilityHint("Opens which calendars and keywords verify workouts")
                } header: {
                    header("Auto-verify")
                }
                .listRowBackground(LR.Color.surface)

                Section {
                    Button { path.append(.reminders) } label: {
                        row("Reminders", systemImage: "bell", tint: .medium, pushes: true)
                    }
                    .accessibilityHint("Opens the morning and evening reminders and their times")
                    Button { path.append(.journal) } label: {
                        row("Journal", systemImage: "book.closed", tint: .hidden, pushes: true)
                    }
                    .accessibilityHint("Opens Apple Journal sending and what Ask me something may send")
                } header: {
                    header("Reminders and journal")
                }
                .listRowBackground(LR.Color.surface)

                Section {
                    Button { transfer.prepareJSONExport(context) } label: {
                        row("Output records to JSON", systemImage: "clock.arrow.circlepath", tint: .hidden)
                    }
                    .accessibilityHint("Saves all your history as a JSON file")
                    Button { transfer.prepareCSVExport(context) } label: {
                        row("Tables (CSV)", systemImage: "tablecells", tint: .hidden)
                    }
                    .accessibilityHint("Saves the full history with its library rows joined, and your ratings and comments, as CSV files")
                    Button { transfer.importing = true } label: {
                        row("Restore from JSON…", systemImage: "square.and.arrow.down", tint: .hidden)
                    }
                    .accessibilityHint("Picks a backup file. You confirm before anything is replaced")
                    Button { transfer.prepareErase(context) } label: {
                        row("Erase all records…", systemImage: "trash", tint: .hard)
                    }
                    .accessibilityHint("Deletes your history, ratings, rewards and journal after you confirm. Your library stays")
                    if let error = transfer.error {
                        BannerView(message: error)
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    header("Data")
                }
                .listRowBackground(LR.Color.surface)

                Section {
                    Button { path.append(.design) } label: {
                        row("Design gallery", systemImage: "paintpalette", tint: .medium, pushes: true)
                    }
                    .accessibilityHint("Opens the sample components")
                } header: {
                    header("Design")
                }
                .listRowBackground(LR.Color.surface)

                Section {
                    Button { path.append(.debug) } label: {
                        row("Debug", systemImage: "wrench.and.screwdriver", tint: .hard, pushes: true)
                    }
                    .accessibilityHint("Opens row counts, the data audit and test tools")
                } header: {
                    header("Developer")
                }
                .listRowBackground(LR.Color.surface)

                Section {
                    Text(about)
                        .lr(.caption)
                        .foregroundStyle(LR.Color.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .accessibilityLabel(aboutSpoken)
                }
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
                    WorkoutDetectionView(check: check, refresh: refresh)
                case .reminders:
                    RemindersView()
                case .journal:
                    JournalSettingsView()
                case .design:
                    DesignGalleryView()
                        .navigationTitle("Design")
                        .navigationBarTitleDisplayMode(.inline)
                case .debug:
                    DebugView(seedStatus: seedStatus, today: today, sensorReport: sensorReport,
                              refresh: refresh)
                }
            }
        }
        .dataTransfer(transfer, hidesTabBar: hidesTabBar, onImported: onImported)
        .sheet(isPresented: $editingName) { NamePromptSheet(title: "Your name", caption: "Used for the greeting on Today.") }
        .reservingTabBarSpace()
    }

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
    private var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?" }
    private var about: String { "LifeRPG \(version) (\(build))" }
    private var aboutSpoken: String { "LifeRPG, version \(version), build \(build)" }

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
                 check: nil, refresh: {}, onImported: {})
        .modelContainer(for: LifeRPGSchema.models, inMemory: true)
}


/// The recovery stretch set in Settings (`Recovery`). Empty strings = off.
enum RecoveryKeys {
    static let first = "recovery.firstDayKey"
    static let last = "recovery.lastDayKey"

    static func period(_ defaults: UserDefaults = .standard) -> RecoveryPeriod? {
        guard let first = defaults.string(forKey: first), !first.isEmpty,
              let last = defaults.string(forKey: last), !last.isEmpty else { return nil }
        return RecoveryPeriod(firstDayKey: first, lastDayKey: last)
    }
}
