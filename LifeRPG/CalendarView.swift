import LifeRPGCore
import SwiftData
import SwiftUI

/// The month page (`PLAN.md` §9). Each day number sits in a ring that fills with the share of the
/// day's quests and routines done (`CalendarMarks.progress`) and turns violet once the hidden quest
/// is done too. Each epic is a highlighter stroke behind the dates from the day it was drawn to the
/// day it was finished (`CalendarMarks.epicSpans`): grey while unfinished, and a colour different
/// from the epic before once it is done. Everything else is in the day sheet. Tap a day for it.
struct CalendarView: View {
    let today: String

    @Query private var quests: [DailyQuest]
    @Query private var occurrences: [RoutineOccurrence]
    @Query private var journalEntries: [JournalEntry]

    @State private var month: MonthKey?
    @State private var selected: SelectedDay?
    /// Which day-sheet sections are open; kept here so the choice lasts while the app runs.
    @State private var daySections = DaySheet.Sections()
    /// -1 / 1 for the way the last month change went, so the new month slides in from that side.
    @State private var direction = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var context

    private struct SelectedDay: Identifiable { let id: String }

    private var currentMonth: MonthKey { MonthKey(dayKey: today) ?? MonthKey(year: 2026, month: 1)! }
    private var shownMonth: MonthKey { month ?? currentMonth }

    /// Finished epics take these in turn, so two epics in a row never share a colour.
    private static let highlighters: [Color] = [LR.Color.tintMedium, LR.Color.tintTrivial,
                                                LR.Color.avatarPink, LR.Color.tintEasy]
    private static let highlighterOpacity = 0.45
    /// An unfinished epic: running or run out.
    private static let unfinishedHighlighter = LR.Color.ink.opacity(0.09)

    private static let ringSize: CGFloat = 36
    private static let ringWidth: CGFloat = 3.5

    private static func highlighter(_ span: EpicSpan) -> Color {
        guard let index = span.doneIndex else { return unfinishedHighlighter }
        return highlighters[index % highlighters.count].opacity(highlighterOpacity)
    }

    private let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        // Both rules live in Core; the page only hands over the rows its queries hold.
        let journalDays = JournalEntryHistory.days(from: journalEntries)
        let journalLevels = JournalMarks.levels(entryDays: journalDays)
        let marks = CalendarMarks.marks(quests: quests, occurrences: occurrences, journalLevels: journalLevels)
        let progress = CalendarMarks.progress(quests: quests, occurrences: occurrences)
        let epics = CalendarMarks.epicSpans(quests)
        NavigationStack {
            ScrollView {
                VStack(spacing: LR.Spacing.sectionGap) {
                    titleRow
                    header
                    gridCard(marks: marks, progress: progress, epics: epics, journalDays: journalDays)
                    legend
                    entriesLink(count: journalDays.count)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            .reservingTabBarSpace()
            .background(LR.Color.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selected) { day in
                DayDetailView(dayKey: day.id, today: today, sections: $daySections)
                    .presentationDetents([.custom(DaySheetDetent.self), .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(34)
                    .presentationBackground(LR.Color.canvas)
            }
        }
    }

    // MARK: header

    /// The page title with the round book that opens the entries list.
    private var titleRow: some View {
        HStack {
            Text("Calendar").lr(.pageTitle).foregroundStyle(LR.Color.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            NavigationLink { JournalEntriesView(today: today) } label: { RoundIcon(systemName: "book") }
                .buttonStyle(PressableCardStyle())
                .accessibilityLabel("All journal entries")
        }
        .padding(.top, 8)
    }

    private var header: some View {
        HStack(spacing: 12) {
            monthButton(systemImage: "chevron.left", label: "Previous month", enabled: true) { go(-1) }
            VStack(spacing: 6) {
                HandText(title(shownMonth), .handTitle, balanced: true).foregroundStyle(LR.Color.ink)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if shownMonth != currentMonth {
                    Button { jump(to: nil) } label: { PillLabel(text: "This month") }
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .padding(.vertical, -10)
                        .accessibilityLabel("Back to this month")
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            // Nothing to review in the future.
            monthButton(systemImage: "chevron.right", label: "Next month", enabled: shownMonth < currentMonth) { go(1) }
        }
        .padding(.top, 4)
    }

    private func monthButton(systemImage: String, label: String, enabled: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LR.Color.iconNeutral)
                .frame(width: 44, height: 44)
                .background(Circle().fill(LR.Color.tabPill))
        }
        .buttonStyle(PressableCardStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }

    private func go(_ delta: Int) {
        jump(to: shownMonth.adding(delta), direction: delta)
    }

    private func jump(to target: MonthKey?, direction: Int? = nil) {
        Haptics.selection()
        let goal = target ?? currentMonth
        self.direction = direction ?? (goal < shownMonth ? 1 : -1)
        withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.25)) { month = target }
    }

    // MARK: grid

    private func gridCard(marks: [String: DayMarks], progress: [String: DayProgress], epics: [EpicSpan],
                          journalDays: [JournalEntryDay]) -> some View {
        let grid = MonthGrid(shownMonth)
        return VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) {
                    Text($0).lr(.pill).foregroundStyle(LR.Color.sectionTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 2)
            .accessibilityHidden(true)
            VStack(spacing: 2) {
                ForEach(grid.weeks, id: \.weekKey) { week in
                    // Cells touch, so a stroke reads as one line across the row and breaks at the
                    // row's end like a highlighted sentence that wraps.
                    HStack(spacing: 0) {
                        ForEach(week.days, id: \.dayKey) { day in
                            cell(day, marks[day.dayKey] ?? DayMarks(), progress: progress[day.dayKey],
                                 epic: epics.first { $0.covers(day.dayKey) }, journalDays: journalDays)
                        }
                    }
                }
            }
            .id(shownMonth)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(x: reduceMotion ? 0 : CGFloat(direction) * -18)),
                removal: .opacity))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .lrCard(.surface, radius: LR.Radius.card)
        // Seven columns of a phone's width cannot hold accessibility-size numbers (the weekday
        // names wrap letter by letter), so the grid stops growing at xxxLarge. Every cell still
        // reads its date and marks to VoiceOver, and the rest of the page scales fully.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// An empty day opens nothing (`DaySheet.opens`). A day whose rows can't be read opens the sheet,
    /// which says so.
    private func openSheet(for dayKey: String, journalDays: [JournalEntryDay]) {
        let hasEntry = journalDays.contains { $0.dayKey == dayKey }
        if let record = try? DayRecord.load(dayKey, in: context), !DaySheet.opens(record, hasEntry: hasEntry) { return }
        Haptics.selection()
        selected = SelectedDay(id: dayKey)
    }

    private func cell(_ day: MonthGrid.Day, _ marks: DayMarks, progress: DayProgress?, epic: EpicSpan?,
                      journalDays: [JournalEntryDay]) -> some View {
        let future = day.dayKey > today
        let isToday = day.dayKey == today
        return Button {
            openSheet(for: day.dayKey, journalDays: journalDays)
        } label: {
            ZStack {
                if !future, let progress {
                    ring(progress.fraction, cleared: marks.hiddenDone)
                }
                if isToday {
                    Circle().fill(LR.Color.tabPill).frame(width: Self.ringSize - 12, height: Self.ringSize - 12)
                }
                Text("\(day.dayOfMonth)")
                    .lr(.bodyStrong)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(isToday ? LR.Color.accent : LR.Color.ink)
            }
            .frame(width: Self.ringSize, height: Self.ringSize)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background { if let epic { stroke(epic, on: day.dayKey) } }
            .contentShape(Rectangle())
            .opacity(future ? 0.35 : day.inMonth ? 1 : 0.4)
        }
        .buttonStyle(PressableCardStyle())
        .disabled(future)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PresentationText.shortDate(day.dayKey) + (isToday ? ", today" : ""))
        .accessibilityValue(spokenMarks(marks, progress: progress, epic: epic, future: future))
    }

    /// Open toward the top, filling clockwise; violet once the hidden quest is done as well.
    private func ring(_ fraction: Double, cleared: Bool) -> some View {
        ZStack {
            Circle().stroke(LR.Color.divider, lineWidth: Self.ringWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(cleared ? LR.Color.tintHidden : LR.Color.trendDeep,
                        style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(Self.ringWidth / 2)
    }

    /// The day's piece of an epic's stroke: rounded only where the epic starts and ends.
    private func stroke(_ epic: EpicSpan, on dayKey: String) -> some View {
        let r: CGFloat = 9
        return UnevenRoundedRectangle(topLeadingRadius: epic.start == dayKey ? r : 0,
                                      bottomLeadingRadius: epic.start == dayKey ? r : 0,
                                      bottomTrailingRadius: epic.end == dayKey ? r : 0,
                                      topTrailingRadius: epic.end == dayKey ? r : 0,
                                      style: .continuous)
            .fill(Self.highlighter(epic))
            .frame(height: Self.ringSize - 4)
            .padding(.leading, epic.start == dayKey ? 2 : 0)
            .padding(.trailing, epic.end == dayKey ? 2 : 0)
    }

    private func spokenMarks(_ marks: DayMarks, progress: DayProgress?, epic: EpicSpan?, future: Bool) -> String {
        if future { return "" }
        var parts: [String] = []
        if let progress { parts.append("\(progress.done) of \(progress.asked) done") }
        if marks.hiddenDone { parts.append("hidden quest done") }
        if marks.journalLevel > 0 { parts.append("journal entry") }
        if let epic {
            parts.append(epic.doneIndex == nil ? "epic running or not finished" : "epic finished by \(PresentationText.shortDate(epic.end))")
        }
        return parts.isEmpty ? "nothing recorded" : parts.joined(separator: ", ")
    }

    // MARK: legend and entries

    private var legend: some View {
        FlowRow(spacing: 6) {
            LegendChip(text: "Quests and routines done") {
                Circle().trim(from: 0, to: 0.7)
                    .stroke(LR.Color.trendDeep, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: 10, height: 10)
            }
            LegendChip(text: "Hidden too") {
                Circle().stroke(LR.Color.tintHidden, lineWidth: 2).frame(width: 10, height: 10)
            }
            LegendChip(text: "Epic, grey until done") {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Self.highlighters[0].opacity(Self.highlighterOpacity))
                    .frame(width: 16, height: 9)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Legend: the ring around a day fills with the quests and routines done, "
            + "and turns violet when the hidden quest is done too. "
            + "A highlighter stroke runs from an epic's first day to the day it was finished, grey until it is.")
    }

    private func entriesLink(count: Int) -> some View {
        NavigationLink { JournalEntriesView(today: today) } label: {
            InfoRowCard(systemImage: "book", disc: LR.Color.tabPill, title: "All journal entries",
                        caption: JournalEntriesList.cardLine(entries: count), chevron: true)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("All journal entries, \(JournalEntriesList.cardLine(entries: count))")
        .accessibilityAddTraits(.isButton)
    }

    private func title(_ m: MonthKey) -> String {
        let names = DateFormatter().standaloneMonthSymbols ?? []
        let name = names.indices.contains(m.month - 1) ? names[m.month - 1] : m.description
        return "\(name) \(m.year)"
    }
}

/// A small legend pill: a glyph and a word on the neutral pill fill.
private struct LegendChip<Glyph: View>: View {
    let text: String
    @ViewBuilder let glyph: Glyph

    var body: some View {
        HStack(spacing: 5) {
            glyph
            Text(text).lr(.pill).foregroundStyle(LR.Color.ink)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: LR.Radius.pill, style: .continuous).fill(LR.Color.pillFill))
    }
}
