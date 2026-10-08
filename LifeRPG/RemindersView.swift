import LifeRPGCore
import SwiftData
import SwiftUI
import UserNotifications

/// Settings → Reminders: an evening nudge to write and a morning note of what is due, each with its
/// own time. Both are local notifications and both start off; switching one on asks for permission,
/// and a refusal puts the switch back and says where to change it.
struct RemindersView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @AppStorage(NotificationService.journalKey) private var journal = false
    @AppStorage(NotificationService.morningKey) private var morning = false
    @AppStorage(NotificationService.morningMinuteKey) private var morningMinute = NotificationService.morningMinute
    @AppStorage(NotificationService.eveningMinuteKey) private var eveningMinute = NotificationService.eveningMinute
    @State private var denied = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(get: { journal }, set: { switchJournal($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Write about today").lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                        Text("Skipped on a day you have already written")
                            .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                        Text("Says how many routines are due; the quests are drawn when you open the app")
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
            } footer: {
                Text("Reminders are local: nothing leaves your phone. Writing and then leaving the app cancels tonight's.")
                    .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textCase(nil)
            }
            .listRowBackground(LR.Color.surface)

            if denied {
                Section {
                    Text("LifeRPG isn't allowed to send notifications. You can change that in iOS Settings.")
                        .lr(.caption).foregroundStyle(LR.Color.clay)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(PillButtonStyle())
                }
                .listRowBackground(LR.Color.surface)
            }
        }
        .listRowSeparatorTint(LR.Color.divider)
        .scrollContentBackground(.hidden)
        .background(LR.Color.canvas)
        .reservingTabBarSpace()
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshDenied() }
        .onChange(of: morningMinute) { Task { await NotificationService.reschedule(in: context) } }
        .onChange(of: eveningMinute) { Task { await NotificationService.reschedule(in: context) } }
    }

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

    private func switchJournal(_ on: Bool) { change(on) { journal = $0 } }
    private func switchMorning(_ on: Bool) { change(on) { morning = $0 } }

    /// Switching off needs no permission. Switching on asks; a refusal leaves the switch off.
    private func change(_ on: Bool, apply: @escaping (Bool) -> Void) {
        guard on else {
            apply(false)
            Task { await NotificationService.reschedule(in: context); await refreshDenied() }
            return
        }
        Task {
            let allowed = await NotificationService.requestAuthorization()
            apply(allowed)
            denied = !allowed
            await NotificationService.reschedule(in: context)
        }
    }

    private func refreshDenied() async {
        denied = await NotificationService.authorization() == .denied && (journal || morning)
    }
}
