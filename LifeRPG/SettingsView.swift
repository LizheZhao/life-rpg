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

    /// The pages the rows push. A row is a button with a chevron of its own: the system disclosure
    /// indicator cannot be coloured, and the chevron is `iconNeutral`.
    private enum Page: Hashable { case library, workoutDetection, design, debug }

    @Environment(\.modelContext) private var context
    @State private var transfer = DataTransfer()
    @State private var path: [Page] = []
    /// The sent log, watched so the status line changes when the Shortcut hands a day over.
    @AppStorage(JournalSentLog.key) private var sentLog = Data()
    @AppStorage(JournalAskSettings.sendWritingKey) private var sendWriting = JournalAskSettings.sendWritingDefault

    var body: some View {
        NavigationStack(path: $path) {
            List {
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
                    row("Apple Journal", systemImage: "book.closed", tint: .hidden)
                    Text(Self.journalExplanation)
                        .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(JournalSentLog.statusLine(JournalSentLog.latest(JournalSentLog.decode(sentLog))))
                        .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                        .frame(minHeight: 44, alignment: .leading)
                    Toggle(isOn: $sendWriting) {
                        Text("Send my writing with the question request")
                            .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                    }
                    .tint(LR.Color.trendDeep)
                    .frame(minHeight: 44)
                    Text(JournalAskSettings.sendWritingCaption)
                        .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    header("Journal")
                } footer: {
                    Text(Self.journalSteps)
                        .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textCase(nil)
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
        .reservingTabBarSpace()
    }

    private static let journalExplanation = "Apple Journal only lets an app add an entry, never change one. So LifeRPG sends each day once, after it has ended, and nothing goes while you can still edit."

    /// What the user builds once in Shortcuts. Written plainly about what was not tried: neither
    /// the steps on a device nor an automation running unattended has been checked.
    private static let journalSteps = """
        Set up once.
        1. In Shortcuts, make a new Shortcut and add Get Journal Text to Send, from LifeRPG.
        2. Add If, and set it to that text has any value.
        3. Inside the If, add Create Journal Entry and give it that text.
        4. In Shortcuts, add a Personal Automation: Time of Day, 5:00 AM, Run Immediately, running that Shortcut.
        5:00 AM is when LifeRPG's day ends. Each day is sent once, as it was at that moment. Changes you make afterwards stay in LifeRPG, and Share is how to send a changed day by hand.
        Not verified: that the automation runs on its own while the phone is locked, and that these steps work as written on your device.
        """

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
