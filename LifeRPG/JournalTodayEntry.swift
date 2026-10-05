import LifeRPGCore
import SwiftData
import SwiftUI

/// The evening's way into the journal, under the greeting: a dark card that opens today's editor,
/// and on its right "Last night · 412 words" while today has no entry. What the card says and
/// when it shows is Core (`JournalEntryToday`); this lays it out.
struct JournalTonightCard: View {
    let today: String
    /// The journal clock, which decides whether the label says "today" or "tonight".
    let now: Date
    let write: () -> Void
    let read: (String) -> Void

    @Query private var todays: [JournalEntry]
    /// The newest entry before today: one row, so the card does not decode the whole history.
    @Query private var earlier: [JournalEntry]

    init(today: String, now: Date, write: @escaping () -> Void, read: @escaping (String) -> Void) {
        self.today = today
        self.now = now
        self.write = write
        self.read = read
        _todays = Query(filter: #Predicate<JournalEntry> { $0.dayKey == today })
        var latest = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.dayKey < today },
                                                   sortBy: [SortDescriptor(\.dayKey, order: .reverse)])
        latest.fetchLimit = 1
        _earlier = Query(latest)
    }

    private var state: JournalEntryToday.State { JournalEntryToday.state(of: todays.first) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HandText(JournalEntryToday.moment(now: now), .hand).foregroundStyle(LR.Color.nightAccent)
                Spacer()
                Image(systemName: "moon")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(LR.Color.nightAccent)
                    .accessibilityHidden(true)
            }
            Text("Write about today").lr(.titleCard).foregroundStyle(LR.Color.onNight)
                .padding(.top, 2)
            Text(JournalEntryToday.cardSubtitle)
                .lr(.caption).foregroundStyle(LR.Color.onNightSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            HStack(alignment: .center, spacing: 12) {
                Button(action: write) {
                    Label(JournalEntryToday.cardCopy(state), systemImage: "pencil")
                        .lr(.bodyStrong).foregroundStyle(LR.Color.nightCard)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 46)
                        .background(Capsule().fill(LR.Color.onNight))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableCardStyle())
                Spacer(minLength: 0)
                if state == .none, let last = JournalEntryToday.lastNight(in: JournalEntryHistory.days(from: earlier),
                                                                          today: today) {
                    Button { read(last.dayKey) } label: {
                        Text(last.text).lr(.caption).foregroundStyle(LR.Color.onNightSecondary)
                            .multilineTextAlignment(.trailing)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens it to read")
                }
            }
            .padding(.top, 16)
        }
        .padding(.top, 20).padding(.bottom, 18).padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: LR.Radius.card, style: .continuous).fill(LR.Color.nightCard))
    }
}

/// The round book button next to `+`: opens today's editor. A purple dot while today is a draft
/// with words in it, a check once it is done, nothing without an entry.
struct JournalBookButton: View {
    let today: String
    let action: () -> Void

    @Query private var todays: [JournalEntry]

    init(today: String, action: @escaping () -> Void) {
        self.today = today
        self.action = action
        _todays = Query(filter: #Predicate<JournalEntry> { $0.dayKey == today })
    }

    private var state: JournalEntryToday.State { JournalEntryToday.state(of: todays.first) }

    var body: some View {
        Button(action: action) {
            Image(systemName: "book")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(LR.Color.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(LR.Color.surface))
                .overlay(alignment: .topTrailing) { badge }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel("Journal")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Opens today's page to write")
    }

    @ViewBuilder private var badge: some View {
        switch JournalEntryToday.iconBadge(state) {
        case .none:
            EmptyView()
        case .dot:
            Circle().fill(LR.Color.promptInk)
                .frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(LR.Color.surface, lineWidth: 2).padding(-2))
                .padding(9)
        case .check:
            Image(systemName: "checkmark").font(.system(size: 7, weight: .heavy))
                .foregroundStyle(LR.Color.onFill)
                .frame(width: 13, height: 13)
                .background(Circle().fill(LR.Color.dotFill))
                .overlay(Circle().strokeBorder(LR.Color.surface, lineWidth: 2).padding(-2))
                .padding(6)
        }
    }

    private var accessibilityValue: String {
        switch JournalEntryToday.iconBadge(state) {
        case .none: "Nothing written today"
        case .dot: "Draft in progress"
        case .check: "Written today"
        }
    }
}
