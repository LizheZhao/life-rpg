import LifeRPGCore
import SwiftData
import SwiftUI

/// The sheet's root: it only has the store's context to hand to the page, which reads the day's
/// facts from it before the first frame.
struct JournalReadingView: View {
    let startDay: String

    @Environment(\.modelContext) private var context

    var body: some View {
        JournalReadingPage(startDay: startDay, context: context)
    }
}

/// A day's entry to read: the blocks drawn as the editor draws them, without a cursor. Share sends
/// the plain text, Edit opens the editor on this date, and the floating buttons go to the days
/// either side that have an entry.
struct JournalReadingPage: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var rows: [JournalEntry]

    @State private var dayKey: String
    @State private var facts: JournalDayFacts?
    @State private var editing: JournalEditTarget?
    /// The sent log, watched so a day handed over while the page is open shows at once.
    @AppStorage(JournalSentLog.key) private var sentLog = Data()

    private let language = JournalLanguage.system

    init(startDay: String, context: ModelContext) {
        _dayKey = State(initialValue: startDay)
        _facts = State(initialValue: try? JournalDayFacts.read(dayKey: startDay, in: context))
    }

    private var days: [JournalEntryDay] { JournalEntryHistory.days(from: rows) }
    private var day: JournalEntryDay? { days.first { $0.dayKey == dayKey } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heading
                    blocks.padding(.top, 22)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }
            .id(dayKey)
            // The neighbours float over the end of the text, which scrolls clear of them.
            .contentMargins(.bottom, 120, for: .scrollContent)
        }
        .background(LR.Color.canvas.ignoresSafeArea())
        .overlay(alignment: .bottom) { neighborBar }
        .fullScreenCover(item: $editing, onDismiss: { facts = try? JournalDayFacts.read(dayKey: dayKey, in: context) }) {
            JournalEditorView(dayKey: $0.dayKey)
        }
    }

    // MARK: top bar and heading

    private var topBar: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: { circleIcon("chevron.left") }
                .buttonStyle(PressableCardStyle())
                .accessibilityLabel("Back")
            Spacer()
            if let day {
                ShareLink(item: day.plainText()) { circleIcon("square.and.arrow.up") }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityLabel("Share")
            }
            Button { editing = JournalEditTarget(dayKey: dayKey) } label: { circleIcon("pencil") }
                .buttonStyle(PressableCardStyle())
                .accessibilityLabel("Edit")
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
        HandText(day.map { JournalPageText.readingHeading(entry: $0, language: language) }
                 ?? JournalPageText.dateHeading(dayKey: dayKey, language: language), .hand)
            .foregroundStyle(LR.Color.trendDeep)
        if let day {
            FlowRow(spacing: 6) {
                ForEach(JournalPageText.chips(entry: day, facts: facts), id: \.self) { PillLabel(text: $0) }
            }
            .padding(.top, 8)
            if let line = sentLine(for: day) {
                Text(line).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
    }

    /// Whether this day went to Apple Journal, and if it was edited afterwards. Reading only: the
    /// page has no send button, because Journal can not replace an entry (Share is the way out).
    private func sentLine(for day: JournalEntryDay) -> String? {
        guard let entry = JournalSentLog.decode(sentLog)[day.dayKey] else { return nil }
        switch JournalSend.sentState(text: day.plainText(), lastSentFingerprint: entry.fingerprint) {
        case .notSent: return nil
        case .sent: return "Sent to Apple Journal, \(JournalSentLog.timeText(entry.sentAt))"
        case .editedSince: return "Edited since sending"
        }
    }

    // MARK: the blocks

    @ViewBuilder private var blocks: some View {
        if let day {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(day.document.blocks, id: \.id) { block in
                    switch block {
                    case .text(_, let text):
                        paragraph(text)
                    case .prompt(_, let question, let answer, _, _):
                        JournalPromptLayout(question: question) {
                            if answer.isEmpty {
                                Text("Not answered").lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                            } else {
                                paragraph(answer)
                            }
                        }
                    }
                }
            }
            .textSelection(.enabled)
        } else {
            Text("Nothing is written for this day.").lr(.bodyStrong).foregroundStyle(LR.Color.inkSecondary)
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(text).lr(.journalBody).foregroundStyle(LR.Color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: the days either side

    private var neighborBar: some View {
        let near = JournalEntryHistory.neighbors(of: dayKey, in: days)
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
        Button(JournalPageText.shortDate(dayKey: key, language: language)) {
            dayKey = key
            facts = try? JournalDayFacts.read(dayKey: key, in: context)
        }
        .buttonStyle(PillButtonStyle())
    }
}

/// The date an editor is opened on, as the item a cover is presented for.
struct JournalEditTarget: Identifiable, Equatable {
    let dayKey: String
    var id: String { dayKey }
}
