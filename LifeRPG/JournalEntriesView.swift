import LifeRPGCore
import SwiftData
import SwiftUI

/// Every entry, newest first in month sections, with today's draft as a dark card on top and a
/// search over text, answers and questions. What the page says (subtitle, tags, sections, the empty
/// line) comes from one `JournalEntriesList.Page` (Core); this only lays it out.
struct JournalEntriesView: View {
    let today: String

    @Environment(\.dismiss) private var dismiss
    @Query private var entries: [JournalEntry]

    @State private var searching = false
    @State private var query = ""
    @State private var presented: Presented?
    @FocusState private var searchFocused: Bool

    private enum Presented: Identifiable {
        case read(String), write

        var id: String {
            switch self {
            case .read(let day): "read-\(day)"
            case .write: "write"
            }
        }
    }

    var body: some View {
        let page = JournalEntriesList.page(days: JournalEntryHistory.days(from: entries), today: today, query: query)
        VStack(alignment: .leading, spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Journal").lr(.pageTitle).foregroundStyle(LR.Color.ink)
                        .accessibilityAddTraits(.isHeader)
                    HandText(page.subtitle, .hand).foregroundStyle(LR.Color.trendDeep)
                        .padding(.top, 6)
                    if searching { searchField.padding(.top, 14) }
                    if let tonight = page.tonight { tonightCard(tonight).padding(.top, 18) }
                    ForEach(page.sections, id: \.monthKey) { section in
                        Text(section.label).lr(.pill).tracking(1.2).textCase(.uppercase)
                            .foregroundStyle(LR.Color.sectionTitle)
                            .padding(.top, 22)
                            .accessibilityAddTraits(.isHeader)
                        VStack(spacing: 8) {
                            ForEach(section.rows, id: \.dayKey) { row in entryRow(row) }
                        }
                        .padding(.top, 8)
                    }
                    if let empty = page.emptyText {
                        Text(empty).lr(.bodyStrong).foregroundStyle(LR.Color.inkSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 28)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            .reservingTabBarSpace()
        }
        .background(LR.Color.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: $presented) { target in
            switch target {
            case .read(let day): JournalReadingView(startDay: day)
            case .write: JournalEditorView(dayKey: today, today: today)
            }
        }
    }

    // MARK: header

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { RoundIcon(systemName: "chevron.left") }
                .buttonStyle(PressableCardStyle())
                .accessibilityLabel("Back")
            Spacer()
            Button {
                searching.toggle()
                if searching { searchFocused = true } else { query = "" }
            } label: { RoundIcon(systemName: "magnifyingglass") }
                .buttonStyle(PressableCardStyle())
                .accessibilityLabel("Search entries")
                .accessibilityAddTraits(searching ? .isSelected : [])
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(LR.Color.iconNeutral)
                .accessibilityHidden(true)
            TextField("Search your writing", text: $query)
                .lr(.chipLabel)
                .focused($searchFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(LR.Color.iconNeutral)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, query.isEmpty ? 16 : 0)
        .frame(minHeight: 46)
        .lrCard(.surface, radius: LR.Radius.row)
    }

    // MARK: tonight and rows

    private func tonightCard(_ tonight: JournalEntriesList.Tonight) -> some View {
        Button { presented = .write } label: {
            HStack(spacing: 14) {
                Image(systemName: "pencil")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(LR.Color.nightAccent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(LR.Color.onNight.opacity(0.12)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Tonight, in progress").lr(.heading).foregroundStyle(LR.Color.onNight)
                    Text(tonight.detail).lr(.caption).foregroundStyle(LR.Color.onNightSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LR.Color.nightAccent)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: LR.Radius.row, style: .continuous).fill(LR.Color.nightCard))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel("Tonight, in progress, \(tonight.detail)")
        .accessibilityHint("Opens today's page to keep writing")
    }

    private func entryRow(_ row: JournalEntriesList.Row) -> some View {
        Button { presented = .read(row.dayKey) } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 2) {
                    Text("\(row.dayNumber)").lr(.titleCard).monospacedDigit().foregroundStyle(LR.Color.ink)
                    Text(row.weekday).lr(.pill).foregroundStyle(LR.Color.sectionTitle)
                }
                .frame(width: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Text(row.preview).lr(.chipLabel).foregroundStyle(LR.Color.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        Text(row.words).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                        if let tag = row.promptTag {
                            Text(tag).lr(.pill).foregroundStyle(LR.Color.promptInk)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Capsule().fill(LR.Color.tabPill))
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lrCard(.surface, radius: LR.Radius.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(PresentationText.shortDate(row.dayKey)), \(row.preview)")
        .accessibilityValue([row.words, row.promptTag].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Opens the entry to read")
    }
}

/// A 44 pt round button face on the surface, for the header icons of the journal pages.
struct RoundIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(LR.Color.ink)
            .frame(width: 44, height: 44)
            .background(Circle().fill(LR.Color.surface).shadow(color: .black.opacity(0.08), radius: 1.5, y: 1))
            .overlay(Circle().strokeBorder(LR.Color.hairline, lineWidth: 1))
    }
}
