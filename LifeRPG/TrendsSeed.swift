#if targetEnvironment(simulator)
import Foundation
import LifeRPGCore
import SwiftData

/// A fixture for looking at the Trends page: journal entries over the last days before the app's
/// today, plus the quest rows the page's other cards read. Simulator only, run from Debug.
///
/// None of it came from using the app, so a number on the page after this is the fixture's. It is
/// deterministic and writes through the same call the editor saves with (`JournalEntries.save`), so
/// pressing it twice rewrites the same entries. Block ids are derived from the day, so a second
/// press does not change what is stored.
enum TrendsSeed {
    struct Result {
        var entries = 0
        var contexts = 0
        var quests = 0
        var routines = 0
    }

    private static let walkID = UUID(uuidString: "5EED0000-0000-0000-0000-000000000001")!
    private static let groomID = UUID(uuidString: "5EED0000-0000-0000-0000-000000000002")!
    private static let liftID = UUID(uuidString: "5EED0000-0000-0000-0000-000000000003")!
    private static let stretchID = UUID(uuidString: "5EED0000-0000-0000-0000-000000000004")!
    private static let lightWalkID = UUID(uuidString: "5EED0000-0000-0000-0000-0000000000A1")!

    /// What the older and the recent entries talk about, so some words stand out in one period.
    private static let older = [
        "Climbing at the gym again and pasta after.", "Spent the evening in the garden with the neighbours.",
        "Work was busy, a long meeting about hiring.", "Read for an hour before bed.",
        "The garden needs water but the weather turned.", "Cooked pasta with too much garlic.",
    ]
    private static let recent = [
        "Water, water everywhere on the hike and my legs were tired.",
        "Ownership came up again in the 1:1, who owns the applications review.",
        "Did the light version of the walk because I was tired.",
        "Feeling like today went nowhere, but the applications are moving.",
        "Water the plants, then ownership of the roadmap, then sleep.",
        "I feel the light version is working, the applications review went fine.",
        "Tired after the long day, drank a lot of water.",
    ]
    private static let filler = [
        "Today I feel fine.", "Got up late and just kept going.", "Nothing much happened, honestly.",
        "Looked at the river on the way home.", "Called a friend and talked for a while.",
    ]
    private static func blockID(_ back: Int, _ index: Int) -> UUID {
        UUID(uuidString: String(format: "5EED1000-0000-0000-%04d-%012d", index, back))!
    }

    private static let grateful = ["the walk", "the cat", "a good 1:1", "the river", "sleep", "cooking", "quiet morning"]

    /// 15% trivial, 35% easy, 35% medium, 15% hard, so the calendar dots and the day sheet show every
    /// tier colour. A day has one trivial group at most, as in the app.
    private static func seededDifficulty(using rng: inout SeededRNG, allowTrivial: Bool) -> Difficulty {
        switch Int.random(in: 0..<20, using: &rng) {
        case 0..<3: allowTrivial ? .trivial : .easy
        case 3..<10: .easy
        case 10..<17: .medium
        default: .hard
        }
    }

    @MainActor
    static func seed(days count: Int, endingBefore today: String, in context: ModelContext) throws -> Result {
        var result = Result()
        let calendar = LifeCalendar.gregorian()
        let existing = Set(try context.fetch(FetchDescriptor<DailyContext>()).map(\.dayKey))
        let questDays = Set(try context.fetch(FetchDescriptor<DailyQuest>()).map(\.dayKey))

        for back in 1...count {
            guard let dayKey = DayKey.adding(-back, to: today) else { continue }
            // One generator per day, so a second press rewrites the same text whatever it skips.
            var rng = SeededRNG(seed: UInt64(back) &* 7919)
            let isRecent = back <= 30
            let lowDay = back % 5 == 0 || back % 11 == 0

            // About one night in seven has nothing written, and a few days are a single line.
            if back % 7 != 3 {
                var lines: [String] = []
                // Every third night is a page (about 400 words), the rest a few lines.
                let length = back % 9 == 0 ? 1 : back % 3 == 0 ? Int.random(in: 25...40, using: &rng)
                                                             : Int.random(in: 3...(isRecent ? 14 : 9), using: &rng)
                for _ in 0..<length {
                    let pool = Int.random(in: 0..<10, using: &rng)
                    lines.append(pool < 6 ? (isRecent ? recent : older).randomElement(using: &rng)!
                                          : filler.randomElement(using: &rng)!)
                }
                var blocks: [JournalBlock] = [.text(id: blockID(back, 0), text: lines.joined(separator: " "))]
                if Int.random(in: 0..<10, using: &rng) < 5 {
                    let items = grateful.shuffled(using: &rng).prefix(Int.random(in: 1...3, using: &rng))
                    blocks.append(.prompt(id: blockID(back, 1),
                                          question: JournalFixedKey.gratefulFor.question(language: .en),
                                          answer: items.joined(separator: ", "), source: .fixed,
                                          fixedKey: .gratefulFor))
                }
                var written = calendar.date(bySettingHour: 20 + back % 4, minute: 10, second: 0,
                                            of: DayKey.date(dayKey) ?? Date()) ?? Date()
                written = written.addingTimeInterval(Double(back % 50) * 60)
                if try JournalEntries.save(blocks, on: dayKey, in: context, now: written) != nil {
                    result.entries += 1
                }
            }

            guard !existing.contains(dayKey) else { continue }
            let tier: Tier = lowDay ? (back % 2 == 0 ? .veryLow : .low) : .normal
            let dayContext = DailyContext()
            dayContext.dayKey = dayKey
            dayContext.tier = tier
            context.insert(dayContext)
            result.contexts += 1

            let noon = DayKey.date(dayKey) ?? Date()
            if !questDays.contains(dayKey) {
                let randoms = lowDay ? Int.random(in: 1...2, using: &rng) : Int.random(in: 2...4, using: &rng)
                for index in 0..<randoms {
                    // "Read 20 pages" has no template, like a quest typed in by hand.
                    let picks: [(UUID?, String)] = [(liftID, "Workout: weight training"), (groomID, "Cat grooming"),
                                                    (nil, "Read 20 pages")]
                    let (id, text) = picks[index % 3]
                    let difficulty = seededDifficulty(using: &rng, allowTrivial: index == 0)
                    let quest = DailyQuest()
                    quest.dayKey = dayKey
                    quest.weekKey = DayKey.weekKey(of: dayKey) ?? ""
                    quest.slotRaw = difficulty.rawValue
                    quest.templateID = id
                    quest.textSnapshot = text
                    if difficulty == .trivial {
                        // The app's trivial slot is always the three-item group, which has no template.
                        quest.templateID = nil
                        quest.trivialGroup = picks.map(\.1)
                        quest.textSnapshot = quest.trivialGroup.joined(separator: " · ")
                        quest.trivialDone = [true, true, true]
                        quest.points = Scoring.trivialGroupBase
                    } else {
                        quest.points = Int.random(in: difficulty.range, using: &rng)
                    }
                    quest.completedAt = noon
                    context.insert(quest)
                    result.quests += 1
                }
                for (id, text) in [(walkID, "Walk, 30 minutes"), (stretchID, "Stretch for ten minutes")]
                where back % 4 != 1 || id == walkID {
                    let routine = RoutineOccurrence()
                    routine.routineID = id
                    routine.dueDayKey = dayKey
                    routine.weekKey = DayKey.weekKey(of: dayKey) ?? ""
                    routine.completedDayKey = dayKey
                    routine.completedAt = noon
                    routine.textSnapshot = text
                    routine.basePoints = 8
                    routine.awardedPoints = 8
                    if lowDay, id == walkID {
                        routine.usedDegraded = true
                        routine.degradedRoutineID = lightWalkID
                        routine.degradedTextSnapshot = "Walk, 10 minutes"
                    }
                    context.insert(routine)
                    result.routines += 1
                }
            }

            // A rating now and then, so Favorite quests shows stars.
            if back % 3 == 0 {
                for (id, text, value) in [(walkID, "Walk, 30 minutes", 2), (groomID, "Cat grooming", 2),
                                          (liftID, "Workout: weight training", 1)] {
                    let rating = QuestRating()
                    rating.targetID = id
                    rating.textSnapshot = text
                    rating.rating = value
                    rating.dayKey = dayKey
                    rating.timestamp = noon
                    context.insert(rating)
                }
            }
        }
        try context.save()
        return result
    }
}
#endif
