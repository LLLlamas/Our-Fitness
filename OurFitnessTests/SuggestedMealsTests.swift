import XCTest

final class SuggestedMealsTests: XCTestCase {

    private func profile(mode: Mode) -> ProfileDTO {
        let v = Targets.ProfileVitals(sex: .male, weightLb: 180, heightIn: 70, age: 30, activity: .moderate)
        return ProfileDTO(
            name: "Test", mode: mode, sex: .male, heightIn: 70,
            weightLb: 180, age: 30, activity: .moderate,
            computedTargets: Targets.compute(mode: mode, vitals: v)
        )
    }

    /// Totals == targets so both macro gaps are zero → neutral bias, where
    /// score == perServing protein. Lets us reason about ranking deterministically.
    private func neutralTotals(_ p: ProfileDTO) -> DailyTotals {
        var t = DailyTotals()
        t.calories = p.computedTargets.calories
        t.proteinG = p.computedTargets.proteinG
        return t
    }

    func test_backward_compatible_when_no_personalisation() {
        let p = profile(mode: .build)
        let t = neutralTotals(p)
        let plain = SuggestedMeals.ranked(for: p, totals: t, limit: 10).map(\.id)
        let explicitEmpty = SuggestedMeals.ranked(
            for: p, totals: t, recentLogs: [], favoriteFoodIds: [], limit: 10
        ).map(\.id)
        XCTAssertEqual(plain, explicitEmpty)
    }

    func test_neutral_bias_top_is_highest_protein() {
        let p = profile(mode: .build)
        // pasta-chicken (48g) is the highest-protein meal in the build+shared pool.
        let ranked = SuggestedMeals.ranked(for: p, totals: neutralTotals(p), limit: 10)
        XCTAssertEqual(ranked.first?.id, "pasta-chicken")
    }

    func test_favorite_ingredient_boosts_meal_above_higher_protein_one() {
        let p = profile(mode: .build)
        let t = neutralTotals(p)
        // burrito-bowl (45g protein) contains avocado. Favoriting avocado applies a
        // +15% boost → 45 * 1.15 = 51.75 > pasta-chicken's 48, so it overtakes.
        let ranked = SuggestedMeals.ranked(
            for: p, totals: t, favoriteFoodIds: ["avocado"], limit: 10
        )
        XCTAssertEqual(ranked.first?.id, "burrito-bowl")
    }

    func test_isPersonalised_true_when_favorite_ingredient_present() {
        let p = profile(mode: .build)
        // burrito-bowl contains avocado, chicken-breast, rice-white, etc.
        XCTAssertTrue(SuggestedMeals.isPersonalised(
            burritoBowl(p), recentLogs: [], favoriteFoodIds: ["avocado"]
        ))
    }

    func test_recentLogs_personalise_via_most_logged() {
        let p = profile(mode: .build)
        // A meal becomes personalised when one of its ingredients is among the
        // user's most-logged foods (chicken-breast is in burrito-bowl).
        let logs = (0..<6).map { _ in
            FoodLogEntryDTO(
                userId: UUID(), date: Dates.dayKey(), slot: .other, foodId: "chicken-breast",
                perServing: PerServing(calories: 187, proteinG: 35, carbsG: 0, fatG: 4)
            )
        }
        XCTAssertTrue(SuggestedMeals.isPersonalised(
            burritoBowl(p), recentLogs: logs, favoriteFoodIds: []
        ))
    }

    func test_isPersonalised_false_when_no_loved_ingredient() {
        let p = profile(mode: .build)
        XCTAssertFalse(SuggestedMeals.isPersonalised(
            eggsToast(p), recentLogs: [], favoriteFoodIds: ["avocado"]
        ))
    }

    // Helpers to fetch a known meal from the ranked pool.
    private func meal(_ id: String, _ p: ProfileDTO) -> SuggestedMeal {
        SuggestedMeals.ranked(for: p, totals: neutralTotals(p), limit: 50).first { $0.id == id }!
    }
    private func burritoBowl(_ p: ProfileDTO) -> SuggestedMeal { meal("burrito-bowl", p) }
    private func eggsToast(_ p: ProfileDTO) -> SuggestedMeal { meal("eggs-toast", p) }
}
