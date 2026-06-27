import XCTest

final class MealCravingMatcherTests: XCTestCase {

    // Pinned "now" so the affinity history window is deterministic.
    private let now = ISO8601DateFormatter().date(from: "2026-05-24T12:00:00Z")!

    private func profile(mode: Mode = .build, restrictions: [String] = []) -> ProfileDTO {
        ProfileDTO(
            name: "Test", mode: mode, sex: .male, heightIn: 70, weightLb: 180,
            age: 30, activity: .moderate, restrictions: restrictions,
            computedTargets: MacroTargets(calories: 2800, proteinG: 180, carbsG: 300, fatG: 90, stepsDaily: 8000)
        )
    }

    func test_returns_matches_for_a_flavor_craving() {
        let out = MealCravingMatcher.matches(
            for: profile(), craving: "something sweet for dessert",
            totals: .zero, now: now
        )
        XCTAssertFalse(out.isEmpty)
        // The flavour descriptor should be reflected in the reason.
        XCTAssertTrue(out.contains { $0.reason.lowercased().contains("sweet") })
    }

    func test_calorie_floor_biases_toward_higher_calorie_meals() {
        let out = MealCravingMatcher.matches(
            for: profile(), craving: "I need at least 600 calories",
            totals: .zero, now: now
        )
        XCTAssertFalse(out.isEmpty)
        // With only a calorie floor in play, every positively-scored pick clears it.
        XCTAssertTrue(out.allSatisfy { $0.meal.perServing.calories >= 600 })
    }

    func test_allergen_restrictions_are_filtered_out() {
        let out = MealCravingMatcher.matches(
            for: profile(restrictions: ["dairy"]),
            craving: "something creamy and sweet",
            totals: .zero, now: now
        )
        XCTAssertTrue(out.allSatisfy { !$0.meal.allergens.contains("dairy") })
    }

    func test_keyword_match_surfaces_named_food() {
        let out = MealCravingMatcher.matches(
            for: profile(), craving: "high protein chicken meal",
            totals: .zero, now: now
        )
        XCTAssertTrue(out.contains { $0.meal.name.lowercased().contains("chicken") })
    }

    func test_unparseable_craving_falls_back_to_ranked() {
        // No recognised flavour/keyword/calorie/protein — should still suggest meals.
        let out = MealCravingMatcher.matches(
            for: profile(), craving: "hmmmm",
            totals: .zero, limit: 5, now: now
        )
        XCTAssertFalse(out.isEmpty)
    }

    func test_respects_mode_corpus() {
        let buildIds = Set(SuggestedMeals.suggestions(for: .build).map(\.id))
        let out = MealCravingMatcher.matches(
            for: profile(mode: .build), craving: "salty savory bowl",
            totals: .zero, now: now
        )
        XCTAssertTrue(out.allSatisfy { buildIds.contains($0.meal.id) })
    }

    func test_respects_limit() {
        let out = MealCravingMatcher.matches(
            for: profile(), craving: "something savory and filling",
            totals: .zero, limit: 3, now: now
        )
        XCTAssertLessThanOrEqual(out.count, 3)
    }

    // Expanded flavour vocabulary: a cheesy craving fires and is reflected in the reason.
    func test_cheesy_flavour_matches() {
        let out = MealCravingMatcher.matches(
            for: profile(), craving: "something cheesy", totals: .zero, now: now
        )
        XCTAssertFalse(out.isEmpty)
        XCTAssertTrue(out.contains { $0.reason.lowercased().contains("cheesy") })
    }

    // Dietary craving works as a flavour class.
    func test_vegan_craving_returns_results() {
        let out = MealCravingMatcher.matches(
            for: profile(), craving: "vegan and filling", totals: .zero, now: now
        )
        XCTAssertFalse(out.isEmpty)
    }
}
