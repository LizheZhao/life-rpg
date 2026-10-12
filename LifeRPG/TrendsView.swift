import LifeRPGCore
import SwiftData
import SwiftUI

/// The Trends tab: the journal's patterns over a week, a month or a year, and until a week of nights
/// has been written the card that says how far off that is. Every number, label and ordering comes
/// from one `TrendsPage` (Core); this view only lays it out.
///
/// The page is built off the render path: tokenizing a year of entries is real work, so it runs in a
/// `.task` keyed to what it reads, and the previous page stays on screen until the new one is ready.
struct TrendsView: View {
    let today: String

    @Query private var entries: [JournalEntry]
    @Query private var quests: [DailyQuest]
    @Query private var occurrences: [RoutineOccurrence]
    @Query private var ratings: [QuestRating]
    @Query private var contexts: [DailyContext]

    @State private var period = JournalTrends.Period.month
    /// A day of the period on screen; nil is the one holding today.
    @State private var anchor: String?
    @State private var page: TrendsPage?
    @State private var writing = false

    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.legibilityWeight) private var legibility

    /// `chipLabel`'s size at `bodyStrong`'s weight, for the number in a sentence.
    private var emphasisFont: Font {
        let size = LR.Typography.chipLabel.pointSize(dynamicType: dynamicType)
        let weight = LR.Typography.bodyStrong.spec.weight + (legibility == .bold ? 100 : 0)
        return Font(LRFonts.uiFont(LR.Typography.bodyStrong.spec.family, weight: weight, size: size) as CTFont)
    }

    private let language = JournalLanguage.system

    /// What the page reads. A row count is enough to notice an added completion; an entry is also
    /// tracked by the time it was last written, since an edit leaves the count alone.
    private struct BuildKey: Hashable {
        var period: JournalTrends.Period
        var anchor: String
        var today: String
        var counts: [Int]
        var lastWritten: Double
    }

    private var key: BuildKey {
        BuildKey(period: period, anchor: anchor ?? today, today: today,
                 counts: [entries.count, quests.count, occurrences.count, ratings.count, contexts.count],
                 lastWritten: entries.map(\.updatedAt.timeIntervalSince1970).max() ?? 0)
    }

    var body: some View {
        // The stack only carries the pushes (Ratings, the entries list); the page keeps its own title.
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if case .locked = page?.content {
                        Color.clear.frame(height: 44)
                    } else {
                        HStack {
                            Spacer(minLength: 0)
                            PeriodPicker(period: $period)
                        }
                        .padding(.top, 4)
                    }
                    Text("Trends").lr(.pageTitle).foregroundStyle(LR.Color.ink)
                        .padding(.top, 14)
                        .accessibilityAddTraits(.isHeader)
                    subtitleRow.padding(.top, 4)
                    if let page {
                        switch page.content {
                        case .locked(let locked): lockedContent(locked).padding(.top, 28)
                        case .unlocked(let unlocked): unlockedContent(unlocked, period: page.period).padding(.top, 18)
                        }
                    }
                    if !entries.isEmpty { entriesLink.padding(.top, 8) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .reservingTabBarSpace()
            .background(LR.Color.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task(id: key) {
                // Let the page draw (and a tab switch finish) before the work.
                await Task.yield()
                page = build()
            }
            .fullScreenCover(isPresented: $writing) {
                JournalEditorView(dayKey: today, today: today)
            }
            .onChange(of: period) { anchor = nil }
        }
    }

    private func build() -> TrendsPage {
        let days = JournalEntryHistory.days(from: entries)
        return TrendsPage.build(period: period, anchor: anchor ?? today, today: today, days: days,
                                quests: quests, occurrences: occurrences, ratings: ratings,
                                contexts: contexts, language: language)
    }

    // MARK: header

    private var subtitleRow: some View {
        HStack(spacing: 4) {
            HandText(page?.subtitle ?? " ", .hand).foregroundStyle(LR.Color.accent)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
            if let page, page.previousAnchor != nil || page.nextAnchor != nil {
                stepButton("chevron.left", label: "Previous \(page.period.noun)", target: page.previousAnchor)
                stepButton("chevron.right", label: "Next \(page.period.noun)", target: page.nextAnchor)
            }
        }
    }

    private func stepButton(_ symbol: String, label: String, target: String?) -> some View {
        Button {
            guard let target else { return }
            Haptics.selection()
            anchor = target
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LR.Color.iconNeutral)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
        .opacity(target == nil ? 0.3 : 1)
        .accessibilityLabel(label)
    }

    // MARK: locked

    private func lockedContent(_ locked: TrendsPage.Locked) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(locked.progress.text).lr(.titleCard).foregroundStyle(LR.Color.onNight)
                Text(locked.explanation).lr(.chipLabel).foregroundStyle(LR.Color.onNightSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                HStack(spacing: 8) {
                    ForEach(0..<locked.progress.of, id: \.self) { index in
                        let filled = index < locked.progress.written
                        // Nights written, in any order: the tiles count to the unlock, they are not weekdays.
                        Text("\(index + 1)").lr(.pill)
                            .foregroundStyle(filled ? LR.Color.onTintDark : LR.Color.onNightSecondary.opacity(0.7))
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(RoundedRectangle(cornerRadius: LR.Radius.pill, style: .continuous)
                                .fill(filled ? LR.Color.trendMid : LR.Color.onNight.opacity(0.12)))
                    }
                }
                .padding(.top, 18)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(locked.progress.text)
                Button { writing = true } label: {
                    Text(JournalEntryToday.writeButtonTitle(now: JournalClock.now())).lr(.bodyStrong).foregroundStyle(LR.Color.nightCard)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 46)
                        .background(Capsule().fill(LR.Color.onNight))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableCardStyle())
                .padding(.top, 20)
            }
            .padding(.vertical, 24).padding(.horizontal, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: LR.Radius.card, style: .continuous).fill(LR.Color.nightCard))

            Text("WHAT YOU'LL SEE HERE").lr(.pill).tracking(1.2).foregroundStyle(LR.Color.sectionTitle)
                .padding(.top, 28)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 8) {
                ForEach(locked.previews, id: \.title) { preview in
                    HStack(spacing: 14) {
                        BarGlyph().frame(width: 20, height: 20)
                            .foregroundStyle(LR.Color.inkSecondary)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(LR.Color.pillFill))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(preview.title).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                            Text(preview.subtitle).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 14).padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lrCard(.surface, radius: LR.Radius.stat)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, 10)
            // Ratings are not a chart, and this is the only way to them.
            ratingsLink.padding(.top, 12)
        }
    }

    // MARK: unlocked

    private func unlockedContent(_ page: TrendsPage.Unlocked, period: JournalTrends.Period) -> some View {
        // The calendar's cells are the chart's days at the chart's levels, so one count speaks for both.
        let daysWritten = page.calendar.filter { $0.level > 0 }.count
        return VStack(spacing: 12) {
            HStack(spacing: 8) {
                tile(page.totalWords.formatted(), "words")
                tile(page.streak.formatted(), "day streak")
                tile(page.usualHour ?? "\u{2014}", "usual hour")
            }
            if let chart = page.wordsPerDay { wordsPerDay(chart, daysWritten: daysWritten) } else { nothingWritten(period) }
            if let about = page.about { aboutCard(about) }
            if !page.calendar.isEmpty { calendarCard(page.calendar, period: period, daysWritten: daysWritten) }
            if let favorites = page.favorites { favoritesCard(favorites) }
            ratingsLink
            if let energy = page.energy { energyCard(energy) }
            if !page.gratitude.isEmpty { gratitudeCard(page.gratitude) }
            if !page.year.isEmpty { yearCard(page.year) }
        }
    }

    private var ratingsLink: some View {
        NavigationLink { LibraryView(today: today, sort: .rated) } label: {
            InfoRowCard(systemImage: "star.bubble", disc: LR.Color.sectionCircle(.hidden), title: "Ratings",
                        caption: "Your library, best rated first", chevron: true)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ratings, your library best rated first")
        .accessibilityAddTraits(.isButton)
    }

    /// A quiet row, not a card: the page is about patterns, the list is where single days are.
    private var entriesLink: some View {
        NavigationLink { JournalEntriesView(today: today) } label: {
            HStack {
                Text("All journal entries").lr(.bodyStrong)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(LR.Color.inkSecondary)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel("All journal entries")
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).lr(.statNumber).foregroundStyle(LR.Color.ink)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(label).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.top, 14).padding(.bottom, 12).padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard(.surface, radius: LR.Radius.stat)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }

    private func nothingWritten(_ period: JournalTrends.Period) -> some View {
        Text("Nothing written this \(period.noun).").lr(.chipLabel).foregroundStyle(LR.Color.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }

    /// A card with the design's title row and 18 / 16 padding.
    private func card<Content: View>(_ title: String, trailing: String? = nil, subtitle: String? = nil,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).lr(.heading).foregroundStyle(LR.Color.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let trailing { Text(trailing).lr(.caption).foregroundStyle(LR.Color.inkSecondary) }
            }
            if let subtitle {
                Text(subtitle).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            content().padding(.top, 14)
        }
        .padding(.top, 18).padding(.bottom, 16).padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrCard(.surface, radius: LR.Radius.card)
    }

    /// A bar per day standing on the baseline; past 60 days the bars pack tighter with smaller corners.
    private func barStrip(_ bars: [(dayKey: String, fraction: Double, color: Color)], height: CGFloat) -> some View {
        let dense = bars.count > 60
        return HStack(alignment: .bottom, spacing: dense ? 0.5 : 3) {
            ForEach(bars, id: \.dayKey) { bar in
                TopRoundedBar(radius: dense ? 1 : 3)
                    .fill(bar.color)
                    .frame(height: max(3, height * bar.fraction))
            }
        }
        .frame(height: height, alignment: .bottom)
    }

    private func wordsPerDay(_ chart: TrendsPage.WordsPerDay, daysWritten: Int) -> some View {
        card("Words per day", trailing: "avg \(chart.average)") {
            VStack(spacing: 8) {
                barStrip(chart.bars.map { (dayKey: $0.dayKey, fraction: $0.fraction, color: barColor($0)) },
                         height: 110)
                HStack {
                    ForEach(Array(chart.axis.enumerated()), id: \.offset) { index, label in
                        if index > 0 { Spacer(minLength: 0) }
                        Text(label)
                    }
                }
                .lr(.caption).foregroundStyle(LR.Color.sectionTitle)
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Words per day, average \(chart.average)")
        .accessibilityValue(chart.axis.first.map { first in
            "\(daysWritten) days written, from \(first) to \(chart.axis.last ?? first)"
        } ?? "")
    }

    /// Ink for the longest days, blue for the rest, and a quiet stub for a day with nothing written.
    private func barColor(_ bar: TrendsPage.WordsPerDay.Bar) -> Color {
        bar.words == 0 ? LR.Color.pillFill : bar.isTop ? LR.Color.fill : LR.Color.trendMid
    }

    private func aboutCard(_ about: TrendsPage.About) -> some View {
        let shades = [LR.Color.trendDeep, LR.Color.trendDeep, LR.Color.trendMid, LR.Color.trendMid, LR.Color.trendLight]
        return card(about.title, subtitle: about.subtitle) {
            VStack(spacing: 9) {
                ForEach(Array(about.rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 10) {
                        Text(row.word).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                            .lineLimit(2).minimumScaleFactor(0.8)
                            .frame(width: 84, alignment: .leading)
                        Capsule().fill(LR.Color.pillFill).frame(height: 14)
                            .overlay(alignment: .leading) {
                                GeometryReader { proxy in
                                    Capsule().fill(shades[min(index, shades.count - 1)])
                                        .frame(width: proxy.size.width * row.fraction)
                                }
                            }
                        Text("\(row.count)").lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                            .frame(width: 28, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(row.word), \(row.count) times")
                }
            }
        }
    }

    private func calendarCard(_ cells: [TrendsPage.CalendarCell], period: JournalTrends.Period,
                              daysWritten: Int) -> some View {
        let columns: Int = switch period {
        case .week: 7
        case .month: 16
        case .year: 31
        }
        let gap: CGFloat = period == .year ? 2 : 4
        let shades = [LR.Color.pillFill, LR.Color.trendLight, LR.Color.trendMid, LR.Color.trendDeep]
        return card("Writing calendar") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: columns), spacing: gap) {
                ForEach(cells, id: \.dayKey) { cell in
                    RoundedRectangle(cornerRadius: period == .year ? 2 : 4, style: .continuous)
                        .fill(shades[cell.level])
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Writing calendar, \(daysWritten) of \(cells.count) days written")
    }

    private func favoritesCard(_ favorites: TrendsPage.Favorites) -> some View {
        card("Favorite quests", subtitle: favorites.subtitle) {
            VStack(spacing: 10) {
                ForEach(Array(favorites.rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 12) {
                        Text("\(index + 1)").lr(.bodyStrong).fontWeight(.bold)
                            .foregroundStyle(index == 0 ? LR.Color.onTintDark : LR.Color.ink)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill([LR.Color.rankGold, LR.Color.rankSilver, LR.Color.rankBronze][min(index, 2)]))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(row.text).lr(.bodyStrong).foregroundStyle(LR.Color.ink)
                            Text(row.detail).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                        }
                        Spacer(minLength: 4)
                        HStack(spacing: 2) {
                            ForEach(0..<5, id: \.self) { star in
                                Image(systemName: "star.fill").font(.system(size: 13))
                                    .foregroundStyle(star < (row.stars ?? 0) ? LR.Color.trendGold : LR.Color.rankSilver)
                            }
                        }
                        .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Number \(index + 1), \(row.text), \(row.detail), "
                                        + (row.stars.map { "\($0) of 5 stars" } ?? "not rated"))
                }
            }
        }
    }

    private func energyCard(_ energy: TrendsPage.Energy) -> some View {
        card("Low energy days", trailing: "vs quests done",
             subtitle: "Days you set \"very low\" against how much still got done") {
            VStack(alignment: .leading, spacing: 10) {
                barStrip(energy.bars.map { bar in
                             (dayKey: bar.dayKey, fraction: bar.fraction,
                              color: bar.isLow ? LR.Color.trendGold : LR.Color.trendMid)
                         },
                         height: 100)
                    .accessibilityHidden(true)
                HStack(spacing: 14) {
                    legend(LR.Color.trendMid, "normal day")
                    legend(LR.Color.trendGold, "low energy day")
                }
                if let percent = energy.lowDayPercent {
                    // The percent is its own run: the page's fonts are fixed-weight, so markdown bold is lost.
                    Text("On low days you still finished \(Text("\(percent)%").font(emphasisFont)) of a normal day.")
                        .lr(.chipLabel).lineSpacing(3).foregroundStyle(LR.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 12).padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LR.Color.canvas))
                        .padding(.top, 2)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(energy.lowDayPercent.map { "Low energy days. On low days you still finished \($0) percent of a normal day." }
                            ?? "Low energy days")
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color).frame(width: 10, height: 10)
            Text(text).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
        }
    }

    private func gratitudeCard(_ phrases: [JournalTrends.Gratitude.Phrase]) -> some View {
        card("Grateful for, most often") {
            FlowRow(spacing: 8) {
                ForEach(Array(phrases.enumerated()), id: \.offset) { index, phrase in
                    Text(phrase.text)
                        .lr(index < 2 ? .chipTop : index < 4 ? .chipMid : .chipLabel)
                        .foregroundStyle(LR.Color.ink)
                        .padding(.vertical, 8).padding(.horizontal, 14)
                        .background(Capsule().fill(LR.Color.tabPill))
                        .accessibilityLabel("\(phrase.text), \(phrase.count) times")
                }
            }
        }
    }

    private func yearCard(_ months: [TrendsPage.MonthCircle]) -> some View {
        let sizes: [CGFloat] = [18, 22, 27, 32]
        let shades = [LR.Color.surface, LR.Color.trendLight, LR.Color.trendMid, LR.Color.trendDeep]
        return card("Year at a glance") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 10) {
                ForEach(Array(months.enumerated()), id: \.offset) { _, month in
                    VStack(spacing: 6) {
                        Circle().fill(shades[month.level])
                            .overlay(Circle().strokeBorder(LR.Color.dotEmpty, lineWidth: 1.5))
                            .frame(width: sizes[month.level], height: sizes[month.level])
                            .frame(height: 32)
                        Text(month.label).lr(.caption).foregroundStyle(LR.Color.inkSecondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(month.label), \(month.entries) entries")
                }
            }
        }
    }
}

/// A bar with only its top corners rounded, standing on the chart's baseline.
private struct TopRoundedBar: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: 0, bottomTrailingRadius: 0,
                               topTrailingRadius: radius, style: .continuous).path(in: rect)
    }
}

/// Weeks / Months / Year: a light capsule with the chosen one lifted on a white (surface) pill.
private struct PeriodPicker: View {
    @Binding var period: JournalTrends.Period

    @Namespace private var slider
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let options: [(label: String, value: JournalTrends.Period)] = [
        ("Weeks", .week), ("Months", .month), ("Year", .year),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let selected = period == option.value
                Button {
                    guard !selected else { return }
                    Haptics.selection()
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.8)) {
                        period = option.value
                    }
                } label: {
                    Text(option.label).lr(selected ? .bodyStrong : .caption)
                        .foregroundStyle(selected ? LR.Color.ink : LR.Color.inkSecondary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background {
                            if selected {
                                Capsule().fill(LR.Color.surface)
                                    .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
                                    .matchedGeometryEffect(id: "selected", in: slider)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(LR.Color.pillFill))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Period")
    }
}
