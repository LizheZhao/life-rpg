import LifeRPGCore
import SwiftData
import SwiftUI
import UserNotifications

/// Settings → Journal & reminders: the evening nudge to write and the morning note of what is due
/// (local notifications, both off until switched on, each with its own time), what goes to Apple
/// Journal and when, what "Ask me something" may send to the on-device model, and the one-time
/// Shortcut set-up. Switching a reminder on asks for permission; a refusal puts the switch back and
/// says where to change it.
struct JournalRemindersView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @AppStorage(NotificationService.journalKey) private var journal = false
    @AppStorage(NotificationService.morningKey) private var morning = false
    @AppStorage(NotificationService.morningMinuteKey) private var morningMinute = NotificationService.morningMinute
    @AppStorage(NotificationService.eveningMinuteKey) private var eveningMinute = NotificationService.eveningMinute
    /// The sent log, watched so the status line changes when the Shortcut hands a day over.
    @AppStorage(JournalSentLog.key) private var sentLog = Data()
    @AppStorage(JournalAskSettings.sendWritingKey) private var sendWriting = JournalAskSettings.sendWritingDefault
    @State private var denied = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(get: { journal }, set: { switchJournal($0) })) {
                    Text("Write about today").lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                }
                .tint(LR.Color.trendDeep)
                .frame(minHeight: 44)
                if journal {
                    timeRow("Time", minute: $eveningMinute, range: NotificationPlan.eveningRange)
                }
            } header: {
                header("Evening")
            }
            .listRowBackground(LR.Color.surface)

            Section {
                Toggle(isOn: Binding(get: { morning }, set: { switchMorning($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("What is due today").lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                        Text("How many routines are due.")
                            .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(LR.Color.trendDeep)
                .frame(minHeight: 44)
                if morning {
                    timeRow("Time", minute: $morningMinute, range: NotificationPlan.morningRange)
                }
            } header: {
                header("Morning")
            }
            .listRowBackground(LR.Color.surface)

            if denied {
                Section {
                    Text("Notifications are off in iOS Settings.")
                        .lr(.caption).foregroundStyle(LR.Color.clay)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(PillButtonStyle())
                }
                .listRowBackground(LR.Color.surface)
            }

            Section {
                Text(JournalSentLog.statusLine(JournalSentLog.latest(JournalSentLog.decode(sentLog))))
                    .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                    .frame(minHeight: 44, alignment: .leading)
                Text(Self.explanation)
                    .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                header("Apple Journal")
            }
            .listRowBackground(LR.Color.surface)

            Section {
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
                header("Ask me something")
            }
            .listRowBackground(LR.Color.surface)

            Section {
                Text(Self.steps)
                    .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                header("Set up once")
            }
            .listRowBackground(LR.Color.surface)
        }
        .listRowSeparatorTint(LR.Color.divider)
        .scrollContentBackground(.hidden)
        .background(LR.Color.canvas)
        .reservingTabBarSpace()
        .navigationTitle("Journal & reminders")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshDenied() }
        .onChange(of: morningMinute) { Task { await NotificationService.reschedule(in: context) } }
        .onChange(of: eveningMinute) { Task { await NotificationService.reschedule(in: context) } }
    }

    private static let explanation = "Each day goes to Apple Journal once, after it ends."

    /// What the user builds once in Shortcuts.
    private static let steps = """
        1. In Shortcuts, make a new Shortcut and add Get Journal Text to Send, from LifeRPG.
        2. Add If, and set it to that text has any value.
        3. Inside the If, add Create Journal Entry and give it that text.
        4. In Shortcuts, add a Personal Automation: Time of Day, 5:00 AM, Run Immediately, running that Shortcut.
        """

    /// A wheel-free time picker over a minutes-after-midnight value, held to `range`.
    private func timeRow(_ title: LocalizedStringKey, minute: Binding<Int>, range: ClosedRange<Int>) -> some View {
        let midnight = Calendar.current.startOfDay(for: Date())
        func date(_ m: Int) -> Date { midnight.addingTimeInterval(TimeInterval(m * 60)) }
        let binding = Binding<Date>(
            get: { date(minute.wrappedValue) },
            set: { picked in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: picked)
                minute.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            })
        return DatePicker(selection: binding, in: date(range.lowerBound)...date(range.upperBound),
                          displayedComponents: .hourAndMinute) {
            Text(title).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
        }
        .tint(LR.Color.trendDeep)
        .frame(minHeight: 44)
    }

    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title).lr(.heading).foregroundStyle(LR.Color.sectionTitle).textCase(nil)
    }

    private func switchJournal(_ on: Bool) { change(NotificationService.journalKey, on) { journal = $0 } }
    private func switchMorning(_ on: Bool) { change(NotificationService.morningKey, on) { morning = $0 } }

    /// Switching off needs no permission. Switching on asks; a refusal leaves the switch off.
    private func change(_ key: String, _ on: Bool, apply: @escaping (Bool) -> Void) {
        if !on { apply(false) }
        Task {
            let now = await NotificationService.set(key, on: on, in: context)
            apply(now)
            if on { denied = !now } else { await refreshDenied() }
        }
    }

    private func refreshDenied() async {
        denied = await NotificationService.authorization() == .denied && (journal || morning)
    }
}
