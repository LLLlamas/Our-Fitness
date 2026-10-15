import XCTest

final class SuggestedMealsTests: XCTestCase {

    private func profile(fitnessGoal: FitnessGoal) -> ProfileDTO {
        let v = Targets.ProfileVitals(sex: .male, weightLb: 180, heightIn: 70, age: 30, activity: .moderate)
        return ProfileDTO(
            name: "Test", fitnessGoal: fitnessGoal, sex: .male, heightIn: 70,
            weightLb: 180, age: 30, activity: .moderate,
            computedTargets: Targets.compute(fitnessGoal: fitnessGoal, vitals: v)
        )
    }

    /// Totals == targets so both macro gaps are zero → neutral bias, where
    /// score == perServing protein × goal tilt. Lets us reason about ranking deterministically.
    private func neutralTotals(_ p: ProfileDTO) -> DailyTotals {
        var t = DailyTotals()
        t.calories = p.computedTargets.calories
        t.proteinG = p.computedTargets.proteinG
        return t
    }

    func test_backward_compatible_when_no_personalisation() {
        let p = profile(fitnessGoal: .gain)
        let t = neutralTotals(p)
        let plain = SuggestedMeals.ranked(for: p, totals: t, limit: 10).map(\.id)
        let explicitEmpty = SuggestedMeals.ranked(
            for: p, totals: t, recentLogs: [], favoriteFoodIds: [], limit: 10
        ).map(\.id)
        XCTAssertEqual(plain, explicitEmpty)
    }

    func test_neutral_bias_top_is_highest_tilted_protein() {
        // Under neutral bias the score is perServing protein × goal tilt, so the top
        // result must be the best such meal in the full pool (robust to corpus growth).
        for goal in [FitnessGoal.gain, .lose] {
            let p = profile(fitnessGoal: goal)
            let best = SuggestedMeals.all
                .map { Double($0.perServing.proteinG) * SuggestedMeals.goalTilt($0, fitnessGoal: goal) }
                .max()!
            let top = SuggestedMeals.ranked(for: p, totals: neutralTotals(p), limit: 5).first!
            let topScore = Double(top.perServing.proteinG) * SuggestedMeals.goalTilt(top, fitnessGoal: goal)
            XCTAssertEqual(topScore, best, accuracy: 1e-9, "\(goal)")
        }
    }

    /// The goal re-orders, it never hides a meal: both goals rank the same full pool.
    func test_every_goal_ranks_the_full_pool() {
        let all = Set(SuggestedMeals.all.map(\.id))
        for goal in [FitnessGoal.gain, .lose] {
            let p = profile(fitnessGoal: goal)
            let ids = Set(SuggestedMeals.ranked(for: p, totals: neutralTotals(p), limit: 10_000).map(\.id))
            XCTAssertEqual(ids, all, "\(goal)")
        }
    }

    func test_meal_ids_are_unique() {
        let ids = SuggestedMeals.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func test_goal_tilt_is_bounded_and_goal_shaped() {
        for meal in SuggestedMeals.all {
            for goal in [FitnessGoal.gain, .lose] {
                let t = SuggestedMeals.goalTilt(meal, fitnessGoal: goal)
                XCTAssertGreaterThanOrEqual(t, 1.0)
                XCTAssertLessThanOrEqual(t, 1.2 + 1e-9)
            }
        }
        // A protein-heavy calorie-dense meal leans gain; a light fibre-rich one leans lose.
        let burrito = SuggestedMeals.all.first { $0.id == "burrito-bowl" }!
        XCTAssertGreaterThan(SuggestedMeals.goalTilt(burrito, fitnessGoal: .gain), 1.15)
    }

    func test_favorite_ingredient_raises_meal_rank() {
        let p = profile(fitnessGoal: .gain)
        let t = neutralTotals(p)
        // burrito-bowl contains avocado; favouriting avocado applies a +15% boost,
        // so its rank must improve (relative order — robust to other meals being added).
        let before = SuggestedMeals.ranked(for: p, totals: t, limit: 1_000)
            .firstIndex { $0.id == "burrito-bowl" }
        let after = SuggestedMeals.ranked(
            for: p, totals: t, favoriteFoodIds: ["avocado"], limit: 1_000
        ).firstIndex { $0.id == "burrito-bowl" }
        XCTAssertNotNil(before)
        XCTAssertNotNil(after)
        if before! > 0 { XCTAssertLessThan(after!, before!) } else { XCTAssertEqual(after, 0) }
    }

    func test_isPersonalised_true_when_favorite_ingredient_present() {
        let p = profile(fitnessGoal: .gain)
        // burrito-bowl contains avocado, chicken-breast, rice-white, etc.
        XCTAssertTrue(SuggestedMeals.isPersonalised(
            burritoBowl(p), recentLogs: [], favoriteFoodIds: ["avocado"]
        ))
    }

    func test_recentLogs_personalise_via_most_logged() {
        let p = profile(fitnessGoal: .gain)
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
        let p = profile(fitnessGoal: .gain)
        XCTAssertFalse(SuggestedMeals.isPersonalised(
            eggsToast(p), recentLogs: [], favoriteFoodIds: ["avocado"]
        ))
    }

    // Helpers to fetch a known meal from the ranked pool.
    private func meal(_ id: String, _ p: ProfileDTO) -> SuggestedMeal {
        SuggestedMeals.ranked(for: p, totals: neutralTotals(p), limit: 200).first { $0.id == id }!
    }
    private func burritoBowl(_ p: ProfileDTO) -> SuggestedMeal { meal("burrito-bowl", p) }
    private func eggsToast(_ p: ProfileDTO) -> SuggestedMeal { meal("eggs-toast", p) }
}
