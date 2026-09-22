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
        List {
            Section {
                Picker("Window", selection: $days) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("All").tag(0)
                }
                .pickerStyle(.segmented)
            }
            Section(since.map { "Since \($0)" } ?? "All time") {
                if rows.isEmpty {
                    Text("No ratings in this window yet").foregroundStyle(.secondary)
                }
                ForEach(rows, id: \.text) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.text)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(row.average.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())))
                                .monospacedDigit()
                                .foregroundStyle(row.average > 0 ? .green : row.average < 0 ? .red : .secondary)
                            Text("\(row.count)×").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Ratings")
    }
}
