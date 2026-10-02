import Testing
@testable import LifeRPGCore

/// Which doodle a quest wears is decided by its text. Only a custom ad-hoc routine can carry a chosen
/// one (`RoutineOccurrence.iconKey`, `SchemaV4`); `resolve` is the one rule that reads it.
struct DoodleKeyTests {
    @Test(arguments: [
        ("Walk 8,000 steps", DoodleKey.sneaker),
        ("Walk by the river", .sneaker),
        ("Incline walk, 30 minutes", .sneaker),
        ("Workout: running", .sneaker),
        ("Half-day hike or long bike ride", .sneaker),
        ("Complete a long-distance cardio session", .sneaker),
        ("Workout: dumbbell training", .dumbbell),
        ("Workout: weight training", .dumbbell),
        ("Complete four workouts in one week", .dumbbell),
        ("Do wrist mobility exercises", .dumbbell),
        ("Stretch or use a massage gun for 10 minutes", .dumbbell),
        ("Write a journal entry", .notebook),
        ("Write down a dream", .notebook),
        ("Read for 20 minutes", .notebook),
        ("Finish reading a book", .notebook),
        ("Read a paper and write a summary", .notebook),
        ("Turn a technical topic into a complete write-up", .notebook),
        ("Study (examples, LeetCode, interview experience)", .braces),
        ("Just one easy problem", .braces),
        ("Review last week's practice problems", .braces),
        ("Complete a full mock interview", .braces),
        ("Work on project", .potion),
        ("Get a side project to demo-able state", .potion),
        ("Drink 2L of water", .potion),
        ("Make a cup of tea", .potion),
        ("Mix a new cocktail recipe", .potion),
        ("Send job applications", .paperPlane),
        ("Message a friend you haven't talked to in a long time", .paperPlane),
        ("Video call with parents", .paperPlane),
        ("Thank someone who recently helped you", .paperPlane),
        ("Review bills/statements", .trendLine),
        ("Check the credit card statement only, skip the full reconciliation", .trendLine),
        ("Clean and tidy the apartment (vacuum, dishes, dust, litter box, water fountain)", .sparkle),
        ("Take out the trash", .sparkle),
        ("Grocery shopping and cleaning out the fridge", .sparkle),
        ("Cook a dish you've never made", .potion),
        ("Name three of your strengths", .sparkle),
        ("Strength training at home", .dumbbell),
        ("Declutter the wardrobe and donate or sell what you don't wear", .sparkle),
        ("Compliment a stranger", .sparkle),
    ])
    func realLibraryTextsMapAsExpected(text: String, expected: DoodleKey) {
        #expect(DoodleKey.forText(text) == expected)
    }

    @Test func matchingIsCaseInsensitiveAndByWordNotBySubstring() {
        #expect(DoodleKey.forText("WALK THE DOG") == .sneaker)
        #expect(DoodleKey.forText("walk the dog") == .sneaker)
        // "tea" is a word of its own; it must not fire inside "team" or "teaching".
        #expect(DoodleKey.forText("Plan the team offsite") == .sparkle)
        // "Apply" alone is not a send: only "apply to" and "applications" are.
        #expect(DoodleKey.forText("Apply hand cream") == .sparkle)
        #expect(DoodleKey.forText("Apply to three jobs") == .paperPlane)
    }

    @Test func unknownAndEmptyTextFallBackToSparkle() {
        #expect(DoodleKey.forText("") == .sparkle)
        #expect(DoodleKey.forText("Say no to something") == .sparkle)
    }

    @Test func cleaningBeatsTheWaterInAWaterFountain() {
        #expect(DoodleKey.forText("Clean the water fountain") == .sparkle)
        #expect(DoodleKey.forText("Drink water") == .potion)
    }

    @Test func earlierTableEntriesWinWhenTwoMatch() {
        // "run" (sneaker) and "workout" (dumbbell) both appear; the table lists sneaker first.
        #expect(DoodleKey.forText("Workout: running") == .sneaker)
    }

    @Test func everyTableKeyIsReachableThroughItsOwnKeywords() {
        for entry in DoodleKey.table {
            // A keyword shared with an earlier entry resolves to that entry, so one hit is enough.
            let reachable = entry.keywords.contains { keyword in
                let word = keyword.hasSuffix("*") ? String(keyword.dropLast()) : keyword
                return DoodleKey.forText(word) == entry.key
            }
            #expect(reachable, "\(entry.key) cannot be produced by any of its keywords")
        }
    }

    @Test func onlyAvatarAndFlagAreOutsideTheTable() {
        // The avatar and the epic flag are placed by the layout, not chosen from a quest's text.
        let inTable = Set(DoodleKey.table.map(\.key))
        #expect(Set(DoodleKey.allCases).subtracting(inTable) == [.avatar, .flag])
    }

    // MARK: a chosen doodle

    @Test func aStoredKeyBeatsTheKeywords() {
        #expect(DoodleKey.resolve(iconKey: "dumbbell", text: "Walk the dog") == .dumbbell)
        #expect(DoodleKey.resolve(iconKey: "flag", text: "") == .flag)
    }

    @Test func noKeyFallsBackToTheText() {
        #expect(DoodleKey.resolve(iconKey: nil, text: "Walk the dog") == .sneaker)
        #expect(DoodleKey.resolve(iconKey: nil, text: "Say no to something") == .sparkle)
    }

    /// A key written by a newer build, or damaged on the way through a backup, must not crash or
    /// leave a blank disc: the text decides, as it did before the column existed.
    @Test func anUnknownKeyFallsBackToTheText() {
        #expect(DoodleKey.resolve(iconKey: "telescope", text: "Walk the dog") == .sneaker)
        #expect(DoodleKey.resolve(iconKey: "", text: "Drink water") == .potion)
        #expect(DoodleKey.resolve(iconKey: "Dumbbell", text: "Drink water") == .potion)   // keys are exact
    }

    @Test func everyKeyHasAShortSpokenName() {
        #expect(DoodleKey.allCases.map(\.title) == [
            "Person", "Sneaker", "Potion", "Braces", "Notebook", "Dumbbell", "Paper plane", "Trend line",
            "Flag", "Sparkle",
        ])
    }
}
