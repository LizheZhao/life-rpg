import LifeRPGCore
import SwiftUI

enum OnboardingKeys {
    /// Set once the intro has been gone through, or skipped because the store already had history.
    /// Erasing every record clears it, so a new person starting gets the intro.
    static let done = "onboarding.done"
}

/// The first-launch intro: a name, how the day works, what a finish pays, the journal, reminders,
/// and Health and Calendar. Shown when `Onboarding.shouldShow` says so, and again from Settings.
struct OnboardingView: View {
    let onFinish: () -> Void

    enum Page: Int, CaseIterable { case name, quests, loot, journal, reminders, connect }

    @AppStorage(ProfileKeys.name) private var storedName = ""
    @State private var page = Page.name
    @State private var name = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            dots.padding(.top, 12)
            TabView(selection: $page) {
                OnboardingNamePage(name: $name, submit: next).tag(Page.name)
                OnboardingQuestsPage().tag(Page.quests)
                OnboardingLootPage(isCurrent: page == .loot).tag(Page.loot)
                OnboardingJournalPage().tag(Page.journal)
                OnboardingRemindersPage().tag(Page.reminders)
                OnboardingConnectPage().tag(Page.connect)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: page)
            controls
        }
        .background(LR.Color.canvas.ignoresSafeArea())
        .onAppear { name = storedName }
        .onChange(of: page) { old, _ in
            guard old == .name else { return }
            saveName()
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(Page.allCases, id: \.self) { p in
                Capsule().fill(p == page ? LR.Color.ink : LR.Color.dotEmpty)
                    .frame(width: p == page ? 18 : 6, height: 6)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(page.rawValue + 1) of \(Page.allCases.count)")
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: 0) {
            switch page {
            case .name:
                ConfirmBar(title: "Continue", enabled: UserProfile.cleanName(name) != nil, action: next)
                quiet(storedName.isEmpty ? "Skip" : "Not now") { name = storedName; next() }
            case .quests, .loot, .journal:
                ConfirmBar(title: "Next", enabled: true, action: next)
                quiet("Skip to setup") { withAnimation(reduceMotion ? nil : .default) { page = .reminders } }
            case .reminders:
                ConfirmBar(title: "Next", enabled: true, action: next)
                quiet("") {}.hidden()
            case .connect:
                ConfirmBar(title: "Start my day", enabled: true, action: finish)
                quiet("") {}.hidden()
            }
        }
        .padding(.bottom, 4)
    }

    private func quiet(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .lr(.bodyStrong).foregroundStyle(LR.Color.inkSecondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }

    private func next() {
        guard let following = Page(rawValue: page.rawValue + 1) else { return finish() }
        Haptics.selection()
        withAnimation(reduceMotion ? nil : .default) { page = following }
    }

    /// A name typed and then swiped past still counts; an empty field keeps whatever was there.
    private func saveName() {
        if let clean = UserProfile.cleanName(name) { storedName = clean }
    }

    private func finish() {
        saveName()
        Haptics.notify(.success)
        onFinish()
    }
}

/// The top of every page after the name: a hand-written label over a bold title.
struct OnboardingHeader: View {
    let hand: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HandText(hand, .hand).foregroundStyle(LR.Color.accent)
            Text(title).lr(.titleCard).foregroundStyle(LR.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A page's scrolling body, inset like the rest of the app.
struct OnboardingPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
