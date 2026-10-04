import LifeRPGCore
import SwiftData
import SwiftUI

/// The words typed into the per-turn fields of an edit session, by turn. A plain class on purpose:
/// a keystroke only records the text, so nothing that holds it re-renders until editing ends.
@MainActor
final class TurnEdits {
    var texts: [UUID: String] = [:]
}

/// One answered turn in edit mode: the question it answered (if any) above its own field.
private struct TurnEditField: View {
    let entry: JournalReading.Entry
    let edits: TurnEdits

    @State private var text: String

    init(entry: JournalReading.Entry, edits: TurnEdits) {
        self.entry = entry
        self.edits = edits
        _text = State(initialValue: entry.answer)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !entry.question.isEmpty {
                Text(entry.question).lr(.bodyStrong).foregroundStyle(LR.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField("", text: $text, axis: .vertical)
                .lr(.journalBody).foregroundStyle(LR.Color.ink)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lrCard(.surface, radius: LR.Radius.row)
                .onChange(of: text) { _, new in edits.texts[entry.id] = new }
                .accessibilityLabel(entry.question.isEmpty ? "Free writing" : "Your answer")
        }
    }
}

/// The sheet's root: it only has the store's context to hand to the page, which reads its first
/// day from it before the first frame.
struct JournalReadingView: View {
    let startDay: String

    @Environment(\.modelContext) private var context

    var body: some View {
        JournalReadingPage(startDay: startDay, context: context)
    }
}

/// A day of the journal to read, with the day before and after that have writing, and a pencil to
/// edit it. Editing never drops a turn: a day that is only free writing edits as one autosaved
/// text, a day with questions edits each answer in its own field and writes them when editing
/// ends, and free writing can be added to such a day.
struct JournalReadingPage: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var dayKey: String
    /// Every day with writing, read when the page opens, after editing ends and on moving to
    /// another day, never per keystroke.
    @State private var days: [JournalDay]
    @State private var facts: JournalDayFacts?
    @State private var editing = false
    @State private var writing: FreeWritingModel?
    @State private var edits = TurnEdits()
    @State private var notice: String?
    @FocusState private var focused: Bool

    private let language = JournalLanguage.resolve(preferred: Locale.preferredLanguages)

    init(startDay: String, context: ModelContext) {
        let language = JournalLanguage.resolve(preferred: Locale.preferredLanguages)
        _dayKey = State(initialValue: startDay)
        _days = State(initialValue: (try? JournalService.history(language: language, in: context)) ?? [])
        _facts = State(initialValue: try? JournalService.facts(on: startDay, in: context))
    }

    private var day: JournalDay? { days.first { $0.dayKey == dayKey } }
    private var turns: [JournalTurn] { day?.turns ?? [] }
    private var layout: JournalReading.Layout { JournalReading.layout(of: turns) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            VStack(alignment: .leading, spacing: 0) {
                heading
                content
            }
            .padding(.horizontal, 24)
        }
        .background(LR.Color.canvas.ignoresSafeArea())
        .overlay(alignment: .bottom) { if !editing { neighborBar } }
        // A swipe down closes the sheet mid-edit; what was typed is kept all the same.
        .onDisappear { if editing { _ = endEditing() } }
    }

    // MARK: top bar and heading

    private var topBar: some View {
        HStack(spacing: 8) {
            Button { leave() } label: { circleIcon("chevron.left") }
                .buttonStyle(PressableCardStyle())
                .accessibilityLabel("Back")
            Spacer()
            if editing {
                Button("Done") { _ = endEditing() }.buttonStyle(InkPillButtonStyle())
            } else {
                if let day {
                    ShareLink(item: day.text) { circleIcon("square.and.arrow.up") }
                        .buttonStyle(PressableCardStyle())
                        .accessibilityLabel("Share")
                }
                Button { beginEditing() } label: { circleIcon("pencil") }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityLabel("Edit")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func circleIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(LR.Color.ink)
            .frame(width: 44, height: 44)
            .background(Circle().fill(LR.Color.surface))
    }

    @ViewBuilder private var heading: some View {
        HandText(day.map { JournalPageText.readingHeading(day: $0, language: language) }
                 ?? JournalPageText.dateHeading(dayKey: dayKey, language: language), .hand)
            .foregroundStyle(LR.Color.accent)
            .padding(.top, 20)
        if let day, !editing {
            FlowRow(spacing: 6) {
                ForEach(JournalPageText.chips(day: day, facts: facts),
                        id: \.self) { PillLabel(text: $0) }
            }
            .padding(.top, 8)
        }
        if let notice {
            Text(notice).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    // MARK: the day

    @ViewBuilder private var content: some View {
        if editing { editor } else { reader }
    }

    private var reader: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                let entries = JournalReading.entries(of: turns)
                if entries.isEmpty {
                    Text("Nothing is written for this day.").lr(.bodyStrong).foregroundStyle(LR.Color.inkSecondary)
                }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        if !entry.question.isEmpty {
                            Text(entry.question).lr(.bodyStrong).foregroundStyle(LR.Color.inkSecondary)
                        }
                        Text(entry.answer).lr(.journalBody).foregroundStyle(LR.Color.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .textSelection(.enabled)
            .padding(.top, 20)
        }
        .id(dayKey)
        // The neighbours float over the end of the text, which scrolls clear of them.
        .contentMargins(.bottom, 120, for: .scrollContent)
    }

    @ViewBuilder private var editor: some View {
        switch layout {
        case .empty, .freeWriting:
            if let writing {
                FreeWritingEditor(model: writing, focus: $focused)
                    .frame(maxHeight: .infinity)
                    .padding(.top, 12)
                FreeWritingMeta(model: writing)
            }
        case .turns:
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(JournalReading.entries(of: turns)) { TurnEditField(entry: $0, edits: edits) }
                    if let writing {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add free writing").lr(.bodyStrong).foregroundStyle(LR.Color.inkSecondary)
                            FreeWritingEditor(model: writing, focus: $focused)
                                .frame(minHeight: 140)
                                .padding(.horizontal, 12)
                                .lrCard(.surface, radius: LR.Radius.row)
                        }
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            // The cards' shadows reach past the text column; the scroll view would cut them square.
            .scrollClipDisabled()
        }
    }

    // MARK: the days either side

    private var neighborBar: some View {
        let near = JournalHistory.neighbors(of: dayKey, in: days)
        return HStack(spacing: 10) {
            if let previous = near.previous { neighborButton(previous) }
            if let next = near.next { neighborButton(next) }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 36)
        .padding(.bottom, 16)
        .background(LinearGradient(colors: [LR.Color.canvas.opacity(0), LR.Color.canvas, LR.Color.canvas],
                                   startPoint: .top, endPoint: .bottom).allowsHitTesting(false))
    }

    private func neighborButton(_ key: String) -> some View {
        Button(JournalPageText.shortDate(dayKey: key, language: language)) { go(to: key) }
            .buttonStyle(PillButtonStyle())
    }

    // MARK: moving and editing

    private func reload() {
        days = (try? JournalService.history(language: language, in: context)) ?? []
        facts = try? JournalService.facts(on: dayKey, in: context)
    }

    private func go(to key: String) {
        dayKey = key
        notice = nil
        reload()
    }

    private func leave() {
        if editing, !endEditing() { return }
        dismiss()
    }

    private func beginEditing() {
        notice = nil
        switch layout {
        case .empty, .freeWriting:
            writing = FreeWritingModel(dayKey: dayKey, language: language, context: context)
        case .turns:
            edits = TurnEdits()
            writing = JournalReading.canAddFreeWriting(to: turns)
                ? FreeWritingModel(dayKey: dayKey, language: language, context: context) : nil
        }
        editing = true
        focused = layout != .turns
    }

    /// Writes what was edited and leaves edit mode. False, staying in it, when the store refused,
    /// so no words are shown as saved that are not.
    @discardableResult
    private func endEditing() -> Bool {
        if let writing, !writing.flush() {
            notice = "Could not save. Your words are still on the page."
            return false
        }
        var blanked = false
        do {
            for entry in JournalReading.entries(of: turns) {
                guard let words = edits.texts[entry.id] else { continue }
                do { try JournalService.edit(entry.turn, answer: words) } catch JournalEditError.empty { blanked = true }
            }
            try context.save()
        } catch {
            notice = "Could not save. Your words are still on the page."
            return false
        }
        notice = blanked ? "An answer can't be blank, so it was left as it was." : nil
        writing = nil
        edits = TurnEdits()
        editing = false
        reload()
        return true
    }
}
