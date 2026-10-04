import LifeRPGCore
import SwiftData
import SwiftUI

/// The evening journal, one question at a time. The view only renders: Core's planner picks the
/// question from the store, `JournalConversation` decides whether the model's wording or the pool
/// row is shown, and every response is a `JournalTurn` as soon as it is given. There is no cursor,
/// so closing the sheet or killing the app mid-way resumes at the next question.
struct JournalView: View {
    let today: String

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(JournalShortcutStatus.self) private var shortcut
    @AppStorage(JournalShortcutLink.nameKey) private var shortcutName = ""
    @Query private var turns: [JournalTurn]

    @State private var phase = Phase.thinking
    @State private var answer = ""
    /// Writing with no question above it: recorded as the closing turn, which ends the day.
    @State private var freeWriting = false
    @State private var wording: (any JournalWording)?
    @FocusState private var editing: Bool

    /// What was put in front of the user, kept so the response is recorded against it.
    private struct Shown {
        let kind: JournalPromptKind
        let presented: JournalPresented
        let subject: JournalSubject?
        let askedAt: Date
    }

    private enum Phase {
        case thinking
        case ask(Shown)
        case safety
        case done
        case failed(String)
    }

    private let language = JournalLanguage.resolve(preferred: Locale.preferredLanguages)

    init(today: String) {
        self.today = today
        _turns = Query(filter: #Predicate<JournalTurn> { $0.dayKey == today }, sort: \.index)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LR.Spacing.sectionGap) {
                    HandText("tonight", .hand).foregroundStyle(LR.Color.accent)
                    switch phase {
                    case .thinking: thinkingCard
                    case .ask(let shown): questionBlock(shown)
                    case .safety: safetyBlock
                    case .done: doneBlock
                    case .failed(let message): BannerView(title: "The journal could not continue", message: message)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(LR.Color.canvas.ignoresSafeArea())
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundStyle(LR.Color.ink)
                }
            }
        }
        .task {
            shortcut.outcome = nil
            wording = JournalWordingProvider.current(language: language)
            await advance()
        }
    }

    // MARK: pieces

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lrCard(.surface, radius: LR.Radius.row)
    }

    private func caption(_ text: String) -> some View {
        Text(text).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
    }

    private var thinkingCard: some View {
        card {
            HStack(spacing: 12) {
                ProgressView()
                Text("Thinking of a question").lr(.bodyStrong).foregroundStyle(LR.Color.inkSecondary)
            }
            .frame(minHeight: 44)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: a question

    private func questionBlock(_ shown: Shown) -> some View {
        VStack(alignment: .leading, spacing: LR.Spacing.sectionGap) {
            if !freeWriting {
                card {
                    VStack(alignment: .leading, spacing: 10) {
                        if let subject = shown.subject { PillLabel(text: subject.text) }
                        Text(shown.presented.text).lr(.titleCard).foregroundStyle(LR.Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                if shown.presented.source == .model { caption("Worded on this device") }
            }
            card {
                TextEditor(text: $answer)
                    .lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                    .scrollContentBackground(.hidden)
                    .focused($editing)
                    .frame(minHeight: 150)
                    .accessibilityLabel(freeWriting ? "Free writing" : "Your answer")
            }
            actions(shown)
            Button(freeWriting ? "Back to the question" : "Write freely instead") {
                Haptics.selection()
                freeWriting.toggle()
            }
            .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
            .frame(minHeight: 44)
            .padding(.horizontal, 6)
        }
        .onAppear { editing = true }
    }

    private func actions(_ shown: Shown) -> some View {
        HStack(spacing: 8) {
            if !freeWriting {
                Button("Skip") { respond(.skipped, to: shown) }
                    .buttonStyle(PillButtonStyle())
                Button("Doesn't fit") { respond(.misfit, to: shown) }
                    .buttonStyle(PillButtonStyle())
            }
            Spacer(minLength: 0)
            Button("Send") { respond(.answered, to: shown) }
                .buttonStyle(InkPillButtonStyle())
                .disabled(trimmedAnswer.isEmpty)
        }
    }

    private var trimmedAnswer: String { answer.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: the safety line

    private var safetyBlock: some View {
        VStack(alignment: .leading, spacing: LR.Spacing.sectionGap) {
            card {
                Text(JournalSafety.line(language: language)).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Continue") { Task { await advance() } }
                .buttonStyle(SheetPrimaryButtonStyle())
        }
    }

    // MARK: the day's text

    private var composed: String { JournalComposer.text(turns: turns, language: language) }

    private var doneBlock: some View {
        VStack(alignment: .leading, spacing: LR.Spacing.sectionGap) {
            if composed.isEmpty {
                card {
                    Text("Nothing was written today.").lr(.bodyStrong).foregroundStyle(LR.Color.inkSecondary)
                }
            } else {
                card {
                    Text(composed).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    ShareLink(item: composed) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PillButtonStyle())
                    Spacer(minLength: 0)
                    if let url = JournalShortcutLink.runURL(shortcutName: shortcutName) {
                        Button("Save to Journal") { save(through: url) }
                            .buttonStyle(InkPillButtonStyle())
                    }
                }
                if let message = shortcut.message {
                    caption(message)
                } else if JournalShortcutLink.runURL(shortcutName: shortcutName) == nil {
                    caption("Name a Shortcut in Settings to save to Journal from here.")
                }
            }
            Button("Done") { dismiss() }
                .buttonStyle(SheetPrimaryButtonStyle())
        }
    }

    // MARK: the loop

    /// Asks Core what comes next and puts it on screen. Planning is cheap and has no side effect;
    /// only the safety line is recorded here, because Core defines "shown" as recorded.
    @MainActor private func advance() async {
        phase = .thinking
        answer = ""
        freeWriting = false
        do {
            let signals = try JournalService.signals(on: today, in: context)
            let habits = try JournalService.habits(asOf: today, in: context)
            let step = JournalPlanner.next(signals: signals, habits: habits,
                                           today: try JournalService.turns(on: today, in: context),
                                           language: language)
            switch step {
            case .ask(let question):
                let presented = await JournalConversation.present(question, signals: signals, habits: habits,
                                                                  wording: wording, language: language)
                phase = .ask(Shown(kind: question.kind, presented: presented, subject: question.subject,
                                   askedAt: Date()))
            case .followUp(let request):
                let presented = await JournalConversation.present(request, signals: signals, habits: habits,
                                                                  wording: wording)
                phase = .ask(Shown(kind: .followUp, presented: presented, subject: request.subject,
                                   askedAt: Date()))
            case .safety:
                let now = Date()
                try JournalService.record(context, dayKey: today, kind: .safety, promptID: "safety",
                                          question: JournalSafety.line(language: language), language: language,
                                          askedAt: now, answeredAt: now)
                try context.save()
                phase = .safety
            case .done:
                phase = .done
            }
        } catch {
            phase = .failed("\(error)")
        }
    }

    /// The text is not sent: the Shortcut asks the app for it (`GetTodaysJournalTextIntent`).
    private func save(through url: URL) {
        Haptics.selection()
        shortcut.outcome = nil
        openURL(url) { accepted in
            if !accepted { shortcut.outcome = .failed }
        }
    }

    private func respond(_ outcome: JournalOutcome, to shown: Shown) {
        Haptics.selection()
        do {
            if freeWriting {
                try JournalService.record(context, dayKey: today, kind: .closing, question: "",
                                          answer: trimmedAnswer, language: language,
                                          askedAt: shown.askedAt, answeredAt: Date())
            } else {
                try JournalService.record(context, dayKey: today, kind: shown.kind,
                                          promptID: shown.presented.promptID, question: shown.presented.text,
                                          subject: shown.subject,
                                          answer: outcome == .answered ? trimmedAnswer : "", outcome: outcome,
                                          source: shown.presented.source, language: language,
                                          askedAt: shown.askedAt, answeredAt: Date())
            }
            try context.save()
        } catch {
            phase = .failed("\(error)")
            return
        }
        Task { await advance() }
    }
}

/// The Today page's way in: what the journal says about tonight, and a tap to open it.
struct JournalEntryCard: View {
    let today: String
    let open: () -> Void

    @Query private var turns: [JournalTurn]

    init(today: String, open: @escaping () -> Void) {
        self.today = today
        self.open = open
        _turns = Query(filter: #Predicate<JournalTurn> { $0.dayKey == today })
    }

    private var state: String {
        switch JournalProgress.of(turns) {
        case .notStarted: "Not started"
        case .inProgress(let answered): answered == 0 ? "Started" : "\(answered) answered today"
        case .done: "Done for today"
        }
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "book.closed")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LR.Color.iconNeutral)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(LR.Color.sectionCircle(.hidden)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Journal").lr(.heading).foregroundStyle(LR.Color.ink)
                    Text(state).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LR.Color.iconNeutral)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .lrCard(.surface, radius: LR.Radius.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Journal")
        .accessibilityValue(state)
        .accessibilityHint("Opens tonight's questions")
    }
}
