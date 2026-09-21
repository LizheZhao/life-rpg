import Foundation
import Testing
@testable import LifeRPGCore

/// Cooldown windows, the weekend gate, and affinity weighting.
struct SamplingTests {
    private let tz = Fixtures.tokyo

    // MARK: cooldown

    /// "Cooldown N days": last key on D → ineligible D+1 … D+N, eligible again on D+N+1.
    /// E is 3 days, so completing on the 10th blocks the 11th–13th and frees the 14th.
    @Test func completionCooldownCountsFromTheCompletionDay() throws {
        let ctx = try Fixtures.context()
        let t = Fixtures.quest(ctx, "drink water", .easy, completed: "2026-09-10")
        #expect(Sampling.inCooldown(t, today: "2026-09-10", in: tz))
        #expect(Sampling.inCooldown(t, today: "2026-09-13", in: tz))
        #expect(!Sampling.inCooldown(t, today: "2026-09-14", in: tz))
    }

    @Test func difficultyDefaultsAndOverride() throws {
        let ctx = try Fixtures.context()
        let hard = Fixtures.quest(ctx, "call a friend", .hard, completed: "2026-09-01")
        #expect(Sampling.inCooldown(hard, today: "2026-09-15", in: tz))     // 14 days
        #expect(!Sampling.inCooldown(hard, today: "2026-09-16", in: tz))
        hard.cooldownDaysOverride = 20
        #expect(Sampling.inCooldown(hard, today: "2026-09-16", in: tz))
    }

    /// Drawn but not completed: one day only, so it can't come back tomorrow.
    @Test func servedCooldownIsOneDay() throws {
        let ctx = try Fixtures.context()
        let t = Fixtures.quest(ctx, "stretch", .easy, served: "2026-09-10")
        #expect(Sampling.inCooldown(t, today: "2026-09-11", in: tz))
        #expect(!Sampling.inCooldown(t, today: "2026-09-12", in: tz))
    }

    // MARK: pool filters

    @Test func weekendOnlyIsOutOfThePoolOnWeekdays() throws {
        let ctx = try Fixtures.context()
        Fixtures.quest(ctx, "hike", .hard, weekendOnly: true)
        Fixtures.quest(ctx, "inbox zero", .hard)
        let all = try Sampling.activeTemplates(ctx)
        let friday = Sampling.eligible(all, difficulty: .hard, dayKey: "2026-09-18",
                                       allowedIntensities: Set(Intensity.allCases), in: tz)
        let saturday = Sampling.eligible(all, difficulty: .hard, dayKey: "2026-09-19",
                                         allowedIntensities: Set(Intensity.allCases), in: tz)
        #expect(friday.map(\.text) == ["inbox zero"])
        #expect(Set(saturday.map(\.text)) == ["hike", "inbox zero"])
    }

    @Test func inactiveIntensityAndExclusionsAreFiltered() throws {
        let ctx = try Fixtures.context()
        Fixtures.quest(ctx, "retired", .medium, active: false)
        Fixtures.quest(ctx, "sprints", .medium, intensity: .high)
        let keep = Fixtures.quest(ctx, "walk", .medium)
        let skip = Fixtures.quest(ctx, "already drawn", .medium)
        let all = try Sampling.activeTemplates(ctx)
        let pool = Sampling.eligible(all, difficulty: .medium, dayKey: "2026-09-18",
                                     allowedIntensities: [.low, .medium], excluding: [skip.id], in: tz)
        #expect(pool.map(\.id) == [keep.id])
    }

    // MARK: weighting

    /// Affinity -2 → weight 1, +2 → weight 5: disliked entries are rarer but never impossible.
    @Test func affinityWeightsTheDraw() throws {
        let ctx = try Fixtures.context()
        let liked = Fixtures.quest(ctx, "liked", .easy, affinity: 2)
        let disliked = Fixtures.quest(ctx, "disliked", .easy, affinity: -2)
        #expect(Sampling.weight(liked) == 5)
        #expect(Sampling.weight(disliked) == 1)

        var rng = SeededRNG(seed: 7)
        var likedHits = 0
        for _ in 0..<1200 where Sampling.pick(from: [liked, disliked], rng: &rng)?.id == liked.id {
            likedHits += 1
        }
        #expect((900...1100).contains(likedHits))      // 5:1 → about 1000
    }

    @Test func emptyPoolDrawsNothing() {
        var rng = SeededRNG(seed: 1)
        #expect(Sampling.pick(from: [], rng: &rng) == nil)
    }

    @Test func distinctDrawNeverRepeatsAndStopsWhenExhausted() throws {
        let ctx = try Fixtures.context()
        let pool = (0..<2).map { Fixtures.quest(ctx, "t\($0)", .trivial) }
        var rng = SeededRNG(seed: 3)
        let picked = Sampling.pickDistinct(3, from: pool, rng: &rng)
        #expect(picked.count == 2)
        #expect(Set(picked.map(\.id)).count == 2)
    }
}
