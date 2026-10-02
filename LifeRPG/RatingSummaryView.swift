import LifeRPGCore
import SwiftData
import SwiftUI

/// "What has been landing well lately" — the rating log averaged over a window, best first.
/// The ranking is `Feedback.topRated`; this only picks the window.
struct RatingSummaryView: View {
    let today: String

    @Environment(\.modelContext) private var context
    @AppStorage("ratingSummaryDays") private var days = 30

    private var since: String? {
        days > 0 ? DayKey.adding(-(days - 1), to: today) : nil
    }

    var body: some View {
        let rows = (try? Feedback.topRated(context, since: since, limit: 50)) ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                PillSegmentedControl(options: [("7 days", 7), ("30 days", 30), ("90 days", 90), ("All", 0)],
                                     selection: $days, accessibilityLabel: "Window")
                    .padding(.bottom, 4)
                SectionTitle(title: since.map { "Since \(PresentationText.shortDate($0))" } ?? "All time")
                if rows.isEmpty {
                    RecordRowView(title: "No ratings in this window yet", secondary: true) { EmptyView() }
                }
                ForEach(rows, id: \.text) { row in
                    ratingRow(row)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .reservingTabBarSpace()
        .background(LR.Color.canvas.ignoresSafeArea())
        .navigationTitle("Ratings")
    }

    private func ratingRow(_ row: (text: String, average: Double, count: Int)) -> some View {
        let average = row.average.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.text).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(row.count)×").lr(.caption).monospacedDigit().foregroundStyle(LR.Color.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PillLabel(text: average, style: row.average > 0 ? .tint(.trivial) : row.average < 0 ? .clay : .plain)
                .monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard(.surface, radius: LR.Radius.row)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.text)
        .accessibilityValue("average \(average), rated \(row.count) time\(row.count == 1 ? "" : "s")")
    }
}
