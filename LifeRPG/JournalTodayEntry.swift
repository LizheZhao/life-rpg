import LifeRPGCore
import SwiftData
import SwiftUI

/// The evening's way into the journal, under the greeting: a dark card that opens the free-writing
/// page, and on its right what the journal already has ("Last night · 412 words", or once today has
/// words, "Tonight · 86 words"). Reads only today's turns live; last night is read once when the
/// card appears and again after a sheet closes (`reloadToken`), so the autosave of the page above
/// does not recompose every old day.
struct JournalTonightCard: View {
    let today: String
    /// Bumped when a journal sheet closes, to read last night again.
    let reloadToken: Int
    let write: () -> Void
    let read: (String) -> Void

    @Environment(\.modelContext) private var context
    @Query private var turns: [JournalTurn]
    @State private var lastNight: JournalToday.LastNight?

    private let language = JournalLanguage.resolve(preferred: Locale.preferredLanguages)

    init(today: String, reloadToken: Int, write: @escaping () -> Void, read: @escaping (String) -> Void) {
        self.today = today
        self.reloadToken = reloadToken
        self.write = write
        self.read = read
        _turns = Query(filter: #Predicate<JournalTurn> { $0.dayKey == today })
    }

    private var summary: JournalToday.Summary {
        JournalToday.summary(days: JournalHistory.days(from: turns, language: language), today: today)
    }

    private var written: Bool {
        if case .written = summary { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HandText("tonight", .hand).foregroundStyle(LR.Color.nightAccent)
                Spacer()
                Image(systemName: "moon")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(LR.Color.nightAccent)
                    .accessibilityHidden(true)
            }
            Text("Write about today").lr(.titleCard).foregroundStyle(LR.Color.onNight)
                .padding(.top, 2)
            Text("Free writing. A few lines or a full page, both count.")
                .lr(.caption).foregroundStyle(LR.Color.onNightSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            HStack(alignment: .center, spacing: 12) {
                Button(action: write) {
                    Label(written ? "Keep writing" : "Start writing", systemImage: "pencil")
                        .lr(.bodyStrong).foregroundStyle(LR.Color.nightCard)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 46)
                        .background(Capsule().fill(LR.Color.onNight))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableCardStyle())
                Spacer(minLength: 0)
                trailing
            }
            .padding(.top, 16)
        }
        .padding(.top, 20).padding(.bottom, 18).padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: LR.Radius.card, style: .continuous).fill(LR.Color.nightCard))
        // The day can change under an open page (the refresh at launch, midnight), and last night with it.
        .task(id: "\(today)#\(reloadToken)") { loadLastNight() }
    }

    @ViewBuilder private var trailing: some View {
        switch summary {
        case .written(let words):
            link("Tonight · \(JournalPageText.words(words))", day: today)
        case .notStarted:
            if let lastNight { link("Last night · \(JournalPageText.words(lastNight.words))", day: lastNight.dayKey) }
        }
    }

    private func link(_ text: String, day: String) -> some View {
        Button { read(day) } label: {
            Text(text).lr(.caption).foregroundStyle(LR.Color.onNightSecondary)
                .multilineTextAlignment(.trailing)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens it to read")
    }

    private func loadLastNight() {
        let days = (try? JournalService.history(language: language, in: context)) ?? []
        if case .notStarted(let last) = JournalToday.summary(days: days, today: today) { lastNight = last }
    }
}

/// The round book button next to `+`: opens the free-writing page, with a small dot while today has
/// no writing.
struct JournalBookButton: View {
    let today: String
    let action: () -> Void

    @Query private var turns: [JournalTurn]

    private let language = JournalLanguage.resolve(preferred: Locale.preferredLanguages)

    init(today: String, action: @escaping () -> Void) {
        self.today = today
        self.action = action
        _turns = Query(filter: #Predicate<JournalTurn> { $0.dayKey == today })
    }

    private var hasWritten: Bool { !JournalHistory.days(from: turns, language: language).isEmpty }

    var body: some View {
        Button(action: action) {
            Image(systemName: "book")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(LR.Color.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(LR.Color.surface))
                .overlay(alignment: .topTrailing) {
                    if !hasWritten {
                        Circle().fill(LR.Color.tintHidden)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(LR.Color.surface, lineWidth: 2).padding(-2))
                            .padding(9)
                    }
                }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel("Journal")
        .accessibilityValue(hasWritten ? "Written today" : "Nothing written today")
        .accessibilityHint("Opens the page to write")
    }
}

/// What the user's Shortcut last answered, kept on Today after the sheet that started it has gone.
struct JournalShortcutLine: View {
    @Environment(JournalShortcutStatus.self) private var shortcut

    var body: some View {
        if let message = shortcut.message {
            Text(message).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
        }
    }
}
