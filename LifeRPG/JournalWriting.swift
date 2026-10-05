import LifeRPGCore
import Observation
import SwiftData
import SwiftUI

/// What a free-writing editor holds while the user types: the draft (Core's `FreeWritingDraft`)
/// and when it reaches the store. A keystroke only changes the draft in memory; the store is
/// written about a second after the last one, and at once on `flush` (Close, Done, leaving the
/// foreground). The page that shows it reads `draft` only inside the small views that need it, so
/// typing re-renders those and nothing around them.
@MainActor @Observable
final class FreeWritingModel {
    enum Status { case blank, typing, savedNow, saved, failed }

    private(set) var draft: FreeWritingDraft
    private(set) var status: Status
    let dayKey: String
    /// The text the model opened with, for an editor to start from. Not observed, so building the
    /// editor inside its parent's body does not make the parent depend on every keystroke.
    @ObservationIgnored private(set) var openingText: String

    @ObservationIgnored private let language: JournalLanguage
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var settling: Task<Void, Never>?

    private static let autosaveDelay = Duration.seconds(1)
    private static let justNowFor = Duration.seconds(4)

    init(dayKey: String, language: JournalLanguage, context: ModelContext) {
        self.dayKey = dayKey
        self.language = language
        self.context = context
        let stored = (try? JournalService.freeWritingDraft(on: dayKey, in: context)) ?? FreeWritingDraft()
        draft = stored
        openingText = stored.text
        status = stored.text.isEmpty ? .blank : .saved
    }

    func edit(_ text: String) {
        // The editor reports its binding on every update; only a real change is a keystroke.
        guard text != draft.text else { return }
        draft.edit(to: text, at: Date())
        changed()
    }

    func insert(_ starter: JournalStarter) {
        draft.insert(starter, at: Date())
        changed()
    }

    /// Writes what is unsaved now. False when the store refused, so the caller keeps the page open
    /// rather than closing over words that are not saved.
    @discardableResult
    func flush() -> Bool {
        pendingSave?.cancel()
        pendingSave = nil
        return save()
    }

    /// Picks the store's text up again after another screen (the question flow) may have written
    /// the day's free-writing turn. Unsaved words win: the draft is never replaced under the user.
    func reload() {
        guard !draft.hasUnsavedChanges,
              let stored = try? JournalService.freeWritingDraft(on: dayKey, in: context) else { return }
        draft = stored
        openingText = stored.text
        set(draft.text.isEmpty ? .blank : .saved)
    }

    private func changed() {
        set(.typing)
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: Self.autosaveDelay)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    @discardableResult
    private func save() -> Bool {
        guard draft.hasUnsavedChanges else { return true }
        do {
            try JournalService.saveFreeWriting(draft.text, writingSeconds: draft.writingSeconds, on: dayKey,
                                               language: language, in: context, now: Date())
            try context.save()
            draft.markSaved()
            set(.savedNow)
            settling?.cancel()
            settling = Task { [weak self] in
                try? await Task.sleep(for: Self.justNowFor)
                guard !Task.isCancelled, self?.status == .savedNow else { return }
                self?.set(.saved)
            }
            return true
        } catch {
            set(.failed)
            return false
        }
    }

    /// Observation fires on every assignment, equal or not; the status changes a few times an
    /// hour, so the label must not be told on every keystroke.
    private func set(_ next: Status) {
        if status != next { status = next }
    }
}

// MARK: the editor and what sits around it

/// The text, with no chrome. The editor binds to its own `@State`, which keeps the cursor where
/// the user put it, and tells the model about each change; a change the model makes itself (a
/// starter) is copied back. Reading the draft here means a keystroke re-renders this view only.
struct FreeWritingEditor: View {
    let model: FreeWritingModel
    var focus: FocusState<Bool>.Binding

    @State private var text: String

    init(model: FreeWritingModel, focus: FocusState<Bool>.Binding) {
        self.model = model
        self.focus = focus
        _text = State(initialValue: model.openingText)
    }

    var body: some View {
        let modelText = model.draft.text
        TextEditor(text: $text)
            .lr(.journalBody).foregroundStyle(LR.Color.ink)
            .scrollContentBackground(.hidden)
            .focused(focus)
            // The editor's own text inset, taken back so the words line up with the heading.
            .padding(.horizontal, -5)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Start anywhere.").lr(.journalBody).foregroundStyle(LR.Color.inkSecondary)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onChange(of: text) { _, new in model.edit(new) }
            .onChange(of: modelText) { _, new in if new != text { text = new } }
            .accessibilityLabel("Free writing")
    }
}

/// "86 words" on the left, "Writing for 6 min" on the right.
struct FreeWritingMeta: View {
    let model: FreeWritingModel

    var body: some View {
        HStack {
            Text(JournalPageText.words(model.draft.wordCount))
            Spacer(minLength: 12)
            if let time = JournalPageText.writingTime(seconds: model.draft.writingSeconds) { Text(time) }
        }
        .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
        .padding(.vertical, 10)
    }
}

/// The dot and the one word for where the text is.
struct FreeWritingStatusLabel: View {
    let model: FreeWritingModel

    private var label: String {
        switch model.status {
        case .blank: "Not started"
        case .typing: "Saving…"
        case .savedNow: "Saved just now"
        case .saved: "Saved"
        case .failed: "Could not save"
        }
    }

    private var dot: Color {
        switch model.status {
        case .blank: LR.Color.iconNeutral
        case .typing: LR.Color.inkSecondary
        case .savedNow, .saved: LR.Color.dotFill
        case .failed: LR.Color.clay
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(dot).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(label).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: the page

/// The sheet's root: it only has the store's context to hand to the page, which builds its model
/// once from it.
struct JournalWritingView: View {
    let today: String
    /// `JournalTiming.isEvening`, or the simulator's override: it words the heading.
    let evening: Bool

    @Environment(\.modelContext) private var context

    var body: some View {
        JournalWritingPage(today: today, evening: evening, context: context)
    }
}

/// Free writing: a page of text and a row of phrases to start a sentence with, autosaved. Done
/// closes it. Nothing is sent to Apple Journal from here: the day is sent once, after it ends.
struct JournalWritingPage: View {
    let today: String
    let evening: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var model: FreeWritingModel
    @State private var starters: [JournalStarter]
    @State private var guiding = false
    @FocusState private var focused: Bool

    private let language: JournalLanguage

    init(today: String, evening: Bool, context: ModelContext) {
        self.today = today
        self.evening = evening
        let language = JournalLanguage.system
        self.language = language
        _model = State(initialValue: FreeWritingModel(dayKey: today, language: language, context: context))
        _starters = State(initialValue: (try? JournalService.starters(on: today, language: language, in: context)) ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            VStack(alignment: .leading, spacing: 0) {
                HandText(JournalPageText.writingHeading(dayKey: today, evening: evening, language: language), .hand)
                    .foregroundStyle(LR.Color.accent)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                FreeWritingEditor(model: model, focus: $focused)
                    .frame(maxHeight: .infinity)
                FreeWritingMeta(model: model)
                Button("Guide me with questions") { guide() }
                    .lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 24)
        }
        .background(LR.Color.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { starterRow }
        .task { focused = true }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.flush() }
        }
        // A swipe down closes the sheet without Close or Done; the words are saved all the same.
        .onDisappear { model.flush() }
        .sheet(isPresented: $guiding, onDismiss: { model.reload(); focused = true }) {
            JournalView(today: today)
        }
    }

    private var topBar: some View {
        HStack {
            Button("Close") { close() }.buttonStyle(PillButtonStyle())
            Spacer(minLength: 8)
            FreeWritingStatusLabel(model: model)
            Spacer(minLength: 8)
            Button("Done") { close() }.buttonStyle(InkPillButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var starterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(starters, id: \.id) { starter in
                    Button {
                        Haptics.selection()
                        model.insert(starter)
                        focused = true
                    } label: {
                        Text(starter.text).lr(.chipLabel).foregroundStyle(LR.Color.ink)
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(Capsule().fill(LR.Color.canvas))
                            .overlay(Capsule().strokeBorder(LR.Color.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                    .accessibilityHint("Adds these words to the page")
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 7)
        .background(LR.Color.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(LR.Color.hairline).frame(height: 1) }
    }

    // MARK: leaving

    /// Close and Done are the same: save, then leave.
    private func close() {
        guard model.flush() else { return }
        dismiss()
    }

    /// The question flow is a second way to write the same day: what is typed is saved first, and
    /// the page picks up whatever the flow wrote when it closes.
    private func guide() {
        guard model.flush() else { return }
        guiding = true
    }
}
