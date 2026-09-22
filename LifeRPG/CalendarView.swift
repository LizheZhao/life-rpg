import LifeRPGCore
import SwiftData
import SwiftUI

/// The month page (`PLAN.md` §9): green dots for random quests done, a blue dot when every routine
/// was done on the day, a star for the hidden quest, and a highlighted row for a week whose epic
/// was completed. Tap a day for its detail.
struct CalendarView: View {
    let today: String

    @Query private var quests: [DailyQuest]
    @Query private var occurrences: [RoutineOccurrence]

    @State private var month: MonthKey?
    @State private var selected: SelectedDay?

    private struct SelectedDay: Identifiable { let id: String }

    private var shownMonth: MonthKey {
        month ?? MonthKey(dayKey: today) ?? MonthKey(year: 2026, month: 1)!
    }
    // Both rules live in Core; the page only hands over the rows its queries hold.
    private var marks: [String: DayMarks] { CalendarMarks.marks(quests: quests, occurrences: occurrences) }
    private var epicWeeks: Set<String> { CalendarMarks.epicWeeks(quests) }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    grid
                    legend
                }
                .padding(.horizontal, 16)
            }
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if month != nil, month != MonthKey(dayKey: today) {
                        Button("This month") { month = nil }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { RatingSummaryView(today: today) } label: {
                        Label("Ratings", systemImage: "star.bubble")
                    }
                }
            }
            .sheet(item: $selected) { DayDetailView(dayKey: $0.id) }
        }
    }

    private var header: some View {
        HStack {
            Button { month = shownMonth.adding(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(title(shownMonth)).font(.headline).monospacedDigit()
            Spacer()
            Button { month = shownMonth.adding(1) } label: { Image(systemName: "chevron.right") }
                // Nothing to review in the future.
                .disabled(MonthKey(dayKey: today).map { shownMonth >= $0 } ?? false)
        }
        .padding(.top, 8)
    }

    private var grid: some View {
        let grid = MonthGrid(shownMonth)
        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(weekdays, id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary).padding(.bottom, 4) }
            ForEach(grid.weeks, id: \.weekKey) { week in
                // Judged by the row's own weekKey, so a week spanning two months is highlighted
                // in both.
                let epic = epicWeeks.contains(week.weekKey)
                ForEach(week.days, id: \.dayKey) { day in
                    cell(day)
                        .background(epic ? Color.orange.opacity(0.18) : Color.clear)
                }
            }
        }
    }

    private func cell(_ day: MonthGrid.Day) -> some View {
        let m = marks[day.dayKey] ?? DayMarks()
        let future = day.dayKey > today
        return Button {
            selected = SelectedDay(id: day.dayKey)
        } label: {
            VStack(spacing: 3) {
                Text("\(day.dayOfMonth)")
                    .font(.callout.weight(day.dayKey == today ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(day.dayKey == today ? Color.accentColor : .primary)
                HStack(spacing: 2) {
                    ForEach(0..<m.randomsDone, id: \.self) { _ in dot(.green) }
                    if m.routinesCleared { dot(.blue) }
                }
                .frame(height: 6)
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
                    .opacity(m.hiddenDone ? 1 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
            .opacity(day.inMonth ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(future)
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 5, height: 5)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) { dot(.green); Text("Random") }
            HStack(spacing: 4) { dot(.blue); Text("Routines") }
            HStack(spacing: 4) { Image(systemName: "star.fill").foregroundStyle(.yellow); Text("Hidden") }
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(Color.orange.opacity(0.18)).frame(width: 12, height: 10)
                Text("Epic week")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func title(_ m: MonthKey) -> String {
        let names = DateFormatter().standaloneMonthSymbols ?? []
        let name = names.indices.contains(m.month - 1) ? names[m.month - 1] : m.description
        return "\(name) \(m.year)"
    }
}
