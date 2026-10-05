import LifeRPGCore
import SwiftData
import SwiftUI

/// One day's journal, full screen: Close and Done around the save state, the date in script, the
/// blocks, and the chip bar over the keyboard. Every entry point opens this same page. Nothing in
/// it ever locks: Done only marks the entry, and reopening shows the same blocks, editable.
struct JournalEditorView: View {
    let dayKey: String
    /// The app's day, which decides whether the date line says "tonight". The simulator's time
    /// travel passes its own.
    var today = JournalEntries.entryDayKey(now: Date())

    @Environment(\.modelContext) private var context

    var body: some View {
        JournalEditorPage(dayKey: dayKey, today: today, context: context)
    }
}

private struct JournalEditorPage: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: JournalEditorModel

    private let today: String

    init(dayKey: String, today: String, context: ModelContext) {
        self.today = today
        _model = State(initialValue: JournalEditorModel(dayKey: dayKey, context: context))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HandText(JournalPageText.editorHeading(dayKey: model.dayKey, today: today, language: model.language),
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
        .onDisappear { model.flush() }
    }

    // MARK: header

    private var header: some View {
        HStack {
            Button { model.flush(); dismiss() } label: {
                Text("Close").lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(LR.Color.surface).shadow(color: .black.opacity(0.08), radius: 1.5, y: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableCardStyle())
            Spacer(minLength: 8)
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
/// The reader draws the same thing with a `Text` for the answer. The question is read-only; a long
/// press on it offers `Remove question` when `remove` is set.
struct JournalPromptLayout<Answer: View>: View {
    let question: String
    var remove: (() -> Void)?
    @ViewBuilder var answer: Answer

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Rectangle().fill(LR.Color.promptRule).frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                Text(question).lr(.promptQuestion).foregroundStyle(LR.Color.promptInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .contextMenu {
                        if let remove {
                            Button(role: .destructive, action: remove) {
                                Label("Remove question", systemImage: "text.badge.minus")
                            }
                        }
                    }
                    .accessibilityAddTraits(.isHeader)
                answer
            }
        }
    }
}
