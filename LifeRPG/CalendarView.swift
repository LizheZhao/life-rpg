import LifeRPGCore
import SwiftData
import SwiftUI

/// The month page (`PLAN.md` §9). Under each day number: up to three dots coloured by the tier of
/// a random quest done (easiest first, `DayMarks.randomTiers`), a tick when every routine was done
/// on the day, and a violet star for the hidden quest. A week whose epic was completed sits on a
/// soft band in the epic's tint. Tap a day for its detail.
struct CalendarView: View {
    let today: String

    @Query private var quests: [DailyQuest]
    @Query private var occurrences: [RoutineOccurrence]
    /// Only the settlement's `skip` entries: what tells a routine it gave up on from one you cancelled.
    @Query(filter: #Predicate<LedgerEntry> { $0.kind == "skip" }) private var skips: [LedgerEntry]

    @State private var month: MonthKey?
    /// Collapsed on every launch and every visit; not worth remembering.
    @State private var missedExpanded = false
    @State private var selected: SelectedDay?
    /// -1 / 1 for the way the last month change went, so the new month slides in from that side.
    @State private var direction = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct SelectedDay: Identifiable { let id: String }

    private var currentMonth: MonthKey { MonthKey(dayKey: today) ?? MonthKey(year: 2026, month: 1)! }
    private var shownMonth: MonthKey { month ?? currentMonth }

    /// The epic week's band: the epic's own tint at low opacity.
    private static let epicTint = QuestTint(.epic)
    private static let epicBandOpacity = 0.14

    private let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        // Both rules live in Core; the page only hands over the rows its queries hold.
        let marks = CalendarMarks.marks(quests: quests, occurrences: occurrences)
        let epicWeeks = CalendarMarks.epicWeeks(quests)
        NavigationStack {
            ScrollView {
                VStack(spacing: LR.Spacing.sectionGap) {
                    header
                    gridCard(marks: marks, epicWeeks: epicWeeks)
                    legend
                    missedBlock
                    ratingsLink
                }
                .padding(.horizontal, 16)
            }
            .reservingTabBarSpace()
            .background(LR.Color.canvas.ignoresSafeArea())
            .navigationTitle("Calendar")
            .sheet(item: $selected) { DayDetailView(dayKey: $0.id) }
        }
    }

    // MARK: header

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

    private func gridCard(marks: [String: DayMarks], epicWeeks: Set<String>) -> some View {
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
                    // Judged by the row's own weekKey, so a week spanning two months is
                    // highlighted in both.
                    let epic = epicWeeks.contains(week.weekKey)
                    HStack(spacing: 0) {
                        ForEach(week.days, id: \.dayKey) { day in
                            cell(day, marks[day.dayKey] ?? DayMarks(), epic: epic)
                        }
                    }
                    .background {
                        if epic {
                            RoundedRectangle(cornerRadius: LR.Radius.pill + 6, style: .continuous)
                                .fill(Self.epicTint.color.opacity(Self.epicBandOpacity))
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

    private func cell(_ day: MonthGrid.Day, _ marks: DayMarks, epic: Bool) -> some View {
        let future = day.dayKey > today
        let isToday = day.dayKey == today
        return Button {
            Haptics.selection()
            selected = SelectedDay(id: day.dayKey)
        } label: {
            VStack(spacing: 3) {
                Text("\(day.dayOfMonth)")
                    .lr(.bodyStrong)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(LR.Color.ink)
                    .frame(minWidth: 32, minHeight: 32)
                    .background {
                        if isToday { Capsule().strokeBorder(LR.Color.accent, lineWidth: 2) }
                    }
                HStack(spacing: 3) {
                    ForEach(Array(marks.randomTiers.enumerated()), id: \.offset) { _, tier in
                        Circle().fill(QuestTint(tier).color).frame(width: 6, height: 6)
                    }
                }
                .frame(height: 6)
                HStack(spacing: 4) {
                    if marks.routinesCleared {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(LR.Color.ink)
                    }
                    if marks.hiddenDone {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(LR.Color.tintHidden)
                    }
                }
                .frame(height: 10)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .opacity(future ? 0.35 : day.inMonth ? 1 : 0.4)
        }
        .buttonStyle(PressableCardStyle())
        .disabled(future)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PresentationText.shortDate(day.dayKey) + (isToday ? ", today" : ""))
        .accessibilityValue(spokenMarks(marks, epic: epic, future: future))
    }

    private func spokenMarks(_ marks: DayMarks, epic: Bool, future: Bool) -> String {
        if future { return "" }
        var parts: [String] = []
        if !marks.randomTiers.isEmpty {
            parts.append("\(marks.randomsDone) quest\(marks.randomsDone == 1 ? "" : "s") done: "
                + marks.randomTiers.map(\.rawValue).joined(separator: ", "))
        }
        if marks.routinesCleared { parts.append("routines cleared") }
        if marks.hiddenDone { parts.append("hidden quest done") }
        if epic { parts.append("epic week") }
        return parts.isEmpty ? "nothing recorded" : parts.joined(separator: ", ")
    }

    // MARK: legend and ratings

    private var legend: some View {
        FlowRow(spacing: 6) {
            ForEach([QuestTint.trivial, .easy, .medium, .hard], id: \.self) { tint in
                LegendChip(text: tierName(tint)) {
                    Circle().fill(tint.color).frame(width: 7, height: 7)
                }
            }
            LegendChip(text: "Routines") {
                Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(LR.Color.ink)
            }
            LegendChip(text: "Hidden") {
                Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(LR.Color.tintHidden)
            }
            LegendChip(text: "Epic week") {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Self.epicTint.color.opacity(Self.epicBandOpacity * 2))
                    .frame(width: 12, height: 9)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Legend: dots are quests done, coloured trivial, easy, medium or hard. "
            + "A tick is routines cleared, a star the hidden quest, a tinted row an epic week.")
    }

    // MARK: did not finish

    /// What the settlement gave up on in the month on show. Core's rule (`Schedule.missed`); a tap
    /// opens the day it was due, where the row says the same. Nothing to show, nothing drawn.
    @ViewBuilder private var missedBlock: some View {
        let missed = Schedule.missed(occurrences, ledger: skips, in: shownMonth)
        if !missed.isEmpty {
            VStack(spacing: 8) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { missedExpanded.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        HistoryMark(kind: .missed).scaleEffect(0.7).frame(width: 32, height: 32)
                        Text("Did not finish").lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                        Text("\(missed.count)").lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LR.Color.iconNeutral)
                            .rotationEffect(.degrees(missedExpanded ? 180 : 0))
                            .accessibilityHidden(true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .lrCard(.surface, radius: LR.Radius.row)
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityLabel("Did not finish, \(missed.count) this month")
                .accessibilityValue(missedExpanded ? "expanded" : "collapsed")
                .accessibilityHint("Shows what was given up on")

                if missedExpanded {
                    ForEach(missed) { o in
                        Button { selected = SelectedDay(id: o.dueDayKey) } label: {
                            RecordRowView(title: o.displayText, caption: "Due \(o.dueDayKey)", secondary: true) {
                                if o.penaltyApplied > 0 {
                                    PillLabel(text: "−\(o.penaltyApplied)", style: .clay)
                                }
                            }
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                }
            }
        }
    }

    private func tierName(_ tint: QuestTint) -> String {
        switch tint {
        case .trivial: "Trivial"
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        case .hidden: "Hidden"
        case .routine: "Routines"
        case .epic: "Epic week"
        }
    }

    private var ratingsLink: some View {
        NavigationLink { RatingSummaryView(today: today) } label: {
            HStack(spacing: 12) {
                Image(systemName: "star.bubble")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LR.Color.iconNeutral)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(LR.Color.sectionCircle(.hidden)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ratings").lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                    Text("What has been landing well lately").lr(.caption)
                        .foregroundStyle(LR.Color.inkSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LR.Color.iconNeutral)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .lrCard(.surface, radius: LR.Radius.row)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ratings, what has been landing well lately")
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
