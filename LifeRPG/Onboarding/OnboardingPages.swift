import EventKit
import LifeRPGCore
import SwiftData
import SwiftUI

// The intro's pages. The examples are drawn with the app's own pieces (tints, doodles, the reel,
// the journal's prompt), so what the intro shows is what the app looks like.

// MARK: - name

struct OnboardingNamePage: View {
    @Binding var name: String
    let submit: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        OnboardingPage {
            Spacer(minLength: 40)
            AvatarView(size: 72)
            HandText("hello, adventurer", .handTitle).foregroundStyle(LR.Color.accent)
            Text("What should we call you?").lr(.titleCard).foregroundStyle(LR.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            TextField("Your name", text: $name, prompt: Text("Your name").foregroundStyle(LR.Color.inkSecondary))
                .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused)
                .onSubmit { if UserProfile.cleanName(name) != nil { submit() } }
                .frame(minHeight: 44)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lrCard(.surface, radius: LR.Radius.row)
                .padding(.top, 8)
        }
    }
}

// MARK: - quests

struct OnboardingQuestsPage: View {
    private static let samples: [(Difficulty, String)] = [
        (.trivial, "Add a song to a playlist"),
        (.easy, "Do a face mask"),
        (.medium, "Ask someone a question"),
        (.hard, "Day trip to a new town"),
    ]

    var body: some View {
        OnboardingPage {
            OnboardingHeader(hand: "your day", title: "Every morning, a fresh draw")
            label("Quests")
            ForEach(Self.samples, id: \.0) { difficulty, text in
                TintRow(tint: QuestTint(difficulty), doodle: .forText(text),
                        title: difficulty.rawValue.capitalized, caption: text,
                        pill: PresentationText.range(difficulty.range))
            }
            label("Also on your page").padding(.top, 6)
            TintRow(tint: .routine, doodle: .forText("Do the laundry"),
                    title: "Routines", caption: "On their own days, for a set pay")
            TintRow(tint: .epic, doodle: .flag, title: "One epic a week", caption: "The big one, all week long")
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).lr(.heading).foregroundStyle(LR.Color.sectionTitle)
    }
}

/// A Today-style row on a tint: the doodle in its disc, a title and a caption, a pill.
private struct TintRow: View {
    let tint: QuestTint
    let doodle: DoodleKey
    let title: String
    let caption: String
    var pill: String?

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(LR.Color.chip).frame(width: 44, height: 44)
                .overlay { DoodleView(key: doodle, size: 26) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lr(.bodyStrong).foregroundStyle(LR.Color.ink(on: tint))
                Text(caption).lr(.caption).foregroundStyle(LR.Color.ink(on: tint))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let pill { PillLabel(text: pill, style: .onTint) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .lrCard(.tint(tint), radius: LR.Radius.row)
        .accessibilityElement(children: .combine)
    }
}

private extension QuestTint {
    init(_ difficulty: Difficulty) {
        switch difficulty {
        case .trivial: self = .trivial
        case .easy: self = .easy
        case .medium: self = .medium
        case .hard: self = .hard
        case .epic: self = .epic
        }
    }
}

// MARK: - loot

/// What a finish pays: a quest rolls inside its range, a routine pays its set amount. The quest's
/// reel plays once each time the page comes into view; the numbers are an example, nothing is paid.
struct OnboardingLootPage: View {
    let isCurrent: Bool

    private static let quest = "Compliment a stranger"
    private static let range = Difficulty.medium.range
    private static let awarded = 24

    @State private var stage = MomentStage.landed
    @State private var frames: [Int] = []
    @State private var clock = ReelClock.frozen(0)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingPage {
            OnboardingHeader(hand: "loot", title: "Every clear pays coins")
            card(tint: .medium, doodle: .forText(Self.quest), title: Self.quest,
                 caption: "quest · rolled \(PresentationText.range(Self.range))") {
                ReelBox(stage: stage, tint: .medium, awarded: Self.awarded, range: Self.range,
                        frames: frames, clock: clock)
            }
            card(tint: .routine, doodle: .forText("Do the laundry"), title: "Do the laundry",
                 caption: "routine · fixed") {
                HandText("+15", .handDisplay, balanced: true).foregroundStyle(LR.Color.ink)
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .accessibilityLabel("Pays 15 coins")
            }
            Text("Spend coins on rewards you set, or reroll a quest. Routines left undone cost coins, and Sunday night settles the week. Your day resets at 5 am.")
                .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .task(id: isCurrent) { if isCurrent { await roll() } }
    }

    private func card<Middle: View>(tint: QuestTint, doodle: DoodleKey, title: String, caption: String,
                                    @ViewBuilder middle: () -> Middle) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Circle().fill(tint.color).frame(width: 28, height: 28)
                    .overlay { DoodleView(key: doodle, size: 19, tint: LR.Color.ink(on: tint)) }
                Text(title).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
            }
            middle()
            HandText(caption, .hand, balanced: true).foregroundStyle(LR.Color.inkSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .lrCard(.surface, radius: 24)
    }

    private func roll() async {
        guard !reduceMotion else { stage = .landed; return }
        var rng = SystemRandomNumberGenerator()
        frames = PayoutReel.frames(range: Self.range, awarded: Self.awarded, count: 16, using: &rng)
        stage = .rolling
        clock = .running(since: Date(), duration: 1.5)
        try? await Task.sleep(for: .seconds(1.6))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { stage = .landed }
        Haptics.impact(.rigid)
    }
}

// MARK: - journal

struct OnboardingJournalPage: View {
    var body: some View {
        OnboardingPage {
            OnboardingHeader(hand: "dear diary", title: "Write about your day")
            VStack(alignment: .leading, spacing: 14) {
                Text("Finally cooked dinner for a friend tonight.")
                    .lr(.journalBody).foregroundStyle(LR.Color.ink)
                JournalPromptLayout(question: "What surprised you about today?") {
                    Text("How easy it felt once I started.").lr(.journalBody).foregroundStyle(LR.Color.ink)
                }
                .fixedSize(horizontal: false, vertical: true)
                JournalPromptLayout(question: "You cooked a meal for a friend. What did they say first?") {
                    Text("“Can I have the recipe?”").lr(.journalBody).foregroundStyle(LR.Color.ink)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lrCard(.surface, radius: LR.Radius.row)
            .accessibilityElement(children: .combine)
            askPill.frame(maxWidth: .infinity)
            feature("book", "Save each day to Apple Journal")
            feature("chart.line.uptrend.xyaxis", "Trends unlock after 7 days of writing")
        }
    }

    /// The editor's pill, drawn still: here it only shows where questions come from.
    private var askPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LR.Color.promptRule)
            Text("Ask me something").lr(.bodyStrong).foregroundStyle(LR.Color.onNight)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .background(Capsule().fill(LR.Color.nightCard))
        .accessibilityElement(children: .combine)
    }

    private func feature(_ systemImage: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            OnboardingIcon(systemImage: systemImage, tint: .hidden)
            Text(text).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
        .lrCard(.surface, radius: LR.Radius.row)
    }
}

/// The Settings row's icon: a neutral glyph in a circle of a tint at the section strength.
struct OnboardingIcon: View {
    let systemImage: String
    let tint: QuestTint

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(LR.Color.iconNeutral)
            .frame(width: 32, height: 32)
            .background(Circle().fill(LR.Color.sectionCircle(tint)))
            .accessibilityHidden(true)
    }
}

/// A permission row: icon, title, one line, and a switch. Switching on asks iOS; what iOS answers
/// is what the switch shows.
struct OnboardingSwitchRow: View {
    let systemImage: String
    let tint: QuestTint
    let title: String
    let caption: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                OnboardingIcon(systemImage: systemImage, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                    Text(caption).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(LR.Color.trendDeep)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .lrCard(.surface, radius: LR.Radius.row)
    }
}

/// Shown under the switches when iOS has said no: the switch can't ask again, Settings can.
private struct OpenSettingsHint: View {
    let text: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).lr(.caption).foregroundStyle(LR.Color.clay)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open iOS Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(PillButtonStyle())
        }
    }
}

// MARK: - reminders

struct OnboardingRemindersPage: View {
    @Environment(\.modelContext) private var context
    @AppStorage(NotificationService.morningKey) private var morning = false
    @AppStorage(NotificationService.journalKey) private var evening = false
    @State private var denied = false

    var body: some View {
        OnboardingPage {
            OnboardingHeader(hand: "daily login", title: "Never miss a drop")
            OnboardingSwitchRow(systemImage: "sun.max", tint: .medium,
                                title: "Morning · \(time(NotificationService.morningMinute))",
                                caption: "Today's quests are in. Come claim them.",
                                isOn: binding(NotificationService.morningKey, $morning))
            OnboardingSwitchRow(systemImage: "moon", tint: .hidden,
                                title: "Evening · \(time(NotificationService.eveningMinute))",
                                caption: "Wrap up your day.",
                                isOn: binding(NotificationService.journalKey, $evening))
            if denied {
                OpenSettingsHint(text: "Notifications are off in iOS Settings.")
            }
            Text("Change the times in Settings.")
                .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
        }
    }

    private func binding(_ key: String, _ value: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue }, set: { on in
            if !on { value.wrappedValue = false }
            Task {
                let now = await NotificationService.set(key, on: on, in: context)
                value.wrappedValue = now
                if on { denied = !now }
            }
        })
    }

    private func time(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

// MARK: - Health and Calendar

/// Health sets how hard the day is; Calendar ticks off workouts. HealthKit never says what was
/// allowed, only that the sheet was answered, so its switch shows "asked" and stays on.
struct OnboardingConnectPage: View {
    @AppStorage(WorkoutSettings.calendarKey) private var calendarSetting = ""
    @State private var health = false
    @State private var calendar = CalendarService.hasAccess
    @State private var calendarDenied = false

    var body: some View {
        OnboardingPage {
            OnboardingHeader(hand: "power-ups", title: "Let the day read you")
            if HealthService.isAvailable {
                OnboardingSwitchRow(systemImage: "heart", tint: .hard, title: "Health",
                                    caption: "Slept badly? Lighter quests, bigger pay.",
                                    isOn: Binding(get: { health }, set: { if $0 { connectHealth() } }))
            }
            OnboardingSwitchRow(systemImage: "calendar", tint: .easy, title: "Calendar",
                                caption: "Workouts on your calendar tick themselves off.",
                                isOn: Binding(get: { calendar }, set: { if $0 { connectCalendar() } }))
            if calendarDenied {
                OpenSettingsHint(text: "Calendar access is off in iOS Settings.")
            }
        }
        .task { health = await HealthService().hasAsked() }
    }

    private func connectHealth() {
        Task {
            try? await HealthService().requestAuthorization()
            health = await HealthService().hasAsked()
        }
    }

    /// Access alone reads nothing until a calendar is chosen, so a first grant reads them all:
    /// `WorkoutFilter` still wants a workout word in the title, and the Workout detection page
    /// narrows it later.
    private func connectCalendar() {
        guard CalendarService.authorization == .notDetermined else {
            calendarDenied = !CalendarService.hasAccess
            return
        }
        Task {
            let granted = (try? await CalendarService().requestAccess()) ?? false
            calendar = granted
            calendarDenied = !granted
            if granted, CalendarSelection(setting: calendarSetting) == .none {
                calendarSetting = CalendarSelection.all.setting
            }
        }
    }
}
