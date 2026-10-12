import LifeRPGCore
import SwiftData
import SwiftUI

/// One day's journal, full screen: the save state and Done in the header, the date in script, the
/// blocks, and the question bar over the keyboard. Every entry point opens this same page. Nothing
/// in it ever locks: leaving, by Done or any other way, saves and marks an entry that has writing
/// in it, and reopening shows the same blocks, editable.
struct JournalEditorView: View {
    let dayKey: String
    /// The app's day, which decides whether the date line names the moment. The simulator's time
    /// travel passes its own.
    var today = JournalEntries.entryDayKey(now: Date())
    /// The clock the date line's "today" or "tonight" is read from.
    var now = JournalClock.now()

    @Environment(\.modelContext) private var context

    var body: some View {
        JournalEditorPage(dayKey: dayKey, today: today, now: now, context: context)
    }
}

private struct JournalEditorPage: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: JournalEditorModel

    private let today: String
    private let now: Date

    init(dayKey: String, today: String, now: Date, context: ModelContext) {
        self.today = today
        self.now = now
        _model = State(initialValue: JournalEditorModel(dayKey: dayKey, context: context))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HandText(JournalPageText.editorHeading(dayKey: model.dayKey, today: today, now: now, language: model.language),
                             .hand)
                        .foregroundStyle(LR.Color.trendDeep)
                        .padding(.bottom, -2)
                    ForEach(model.document.blocks, id: \.id) { block in blockView(block) }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(LR.Color.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                JournalAskNoticeView(model: model)
                JournalAskCappedHint(model: model)
                JournalPromptBar(model: model) { JournalAskPill(model: model) }
            }
            .animation(.easeOut(duration: 0.2), value: model.notice)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.flush() }
        }
        .onDisappear { model.done() }
        .task { model.prewarm() }
    }

    // MARK: header

    private var header: some View {
        HStack {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let label = model.saveLabel(at: timeline.date)
                HStack(spacing: 8) {
                    Circle().fill(model.pendingSave ? LR.Color.iconNeutral : LR.Color.dotFill).frame(width: 7, height: 7)
                    Text(label).lr(.caption).foregroundStyle(LR.Color.inkSecondary).lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
            }
            Spacer(minLength: 8)
            Button("Done") {
                if model.done() { dismiss() }
            }
            .buttonStyle(InkPillButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: blocks

    @ViewBuilder private func blockView(_ block: JournalBlock) -> some View {
        switch block {
        case .text(let id, let text):
            JournalTextField(blockID: id, text: text, isAnswer: false, focus: model.focusRequest, model: model)
        case .prompt(let id, let question, let answer, _, _):
            JournalPromptLayout(question: question,
                                remove: { model.removeQuestion(id) }) {
                JournalTextField(blockID: id, text: answer, isAnswer: true, focus: model.focusRequest, model: model)
            }
        }
    }
}

/// A prompt: its question in small purple text over the answer, with a purple rule down the left.
/// The reader draws the same thing with a `Text` for the answer. The question is read-only; when
/// `remove` is set a small `x` beside it removes the question, and a long press offers the same.
struct JournalPromptLayout<Answer: View>: View {
    let question: String
    var remove: (() -> Void)?
    @ViewBuilder var answer: Answer

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Rectangle().fill(LR.Color.promptRule).frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 4) {
                    Text(question).lr(.promptQuestion).foregroundStyle(LR.Color.promptInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .contextMenu {
                            if let remove {
                                Button(role: .destructive, action: remove) {
                                    Label("Remove question", systemImage: "text.badge.minus")
                                }
                            }
                        }
                        .accessibilityAddTraits(.isHeader)
                    if let remove {
                        Button(action: remove) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(LR.Color.promptInk.opacity(0.7))
                                .frame(width: 32, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove question")
                    }
                }
                answer
            }
        }
    }
}
