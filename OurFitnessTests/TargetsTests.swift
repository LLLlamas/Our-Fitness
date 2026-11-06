import XCTest

final class TargetsTests: XCTestCase {

    func test_bmr_male_lorenzo() {
        // 130 lb × 0.4536 ≈ 58.97 kg, 67" × 2.54 = 170.18 cm
        // 10×58.97 + 6.25×170.18 - 5×30 + 5 ≈ 1508
        XCTAssertEqual(Targets.bmr(sex: .male, weightLb: 130, heightIn: 67, age: 30), 1508, accuracy: 2)
    }

    func test_bmr_female_offset_is_166() {
        let m = Targets.bmr(sex: .male, weightLb: 150, heightIn: 65, age: 35)
        let f = Targets.bmr(sex: .female, weightLb: 150, heightIn: 65, age: 35)
        XCTAssertEqual(m - f, 166)
    }

    func test_tdee_moderate() {
        let v = Targets.ProfileVitals(sex: .male, weightLb: 130, heightIn: 67, age: 30, activity: .moderate)
        let t = Targets.tdee(v)
        XCTAssertGreaterThan(t, 2200)
        XCTAssertLessThan(t, 2500)
    }

    func test_maintain_eats_maintenance_with_1_6_g_per_kg_protein() {
        let v = Targets.ProfileVitals(sex: .male, weightLb: 180, heightIn: 70, age: 35, activity: .moderate)
        let t = Targets.compute(plan: .maintain, vitals: v)
        XCTAssertEqual(t.calories, Targets.tdee(v))
        XCTAssertEqual(t.proteinG, Int((180 * Units.kgPerLb * 1.6).rounded()))
        XCTAssertEqual(t.stepsDaily, 8_000)
        XCTAssertEqual(t.plan, .maintain)
    }

    func test_gain_targets_ten_percent_surplus_and_universal_caps() {
        let v = Targets.ProfileVitals(sex: .male, weightLb: 130, heightIn: 67, age: 30, activity: .active)
        let t = Targets.compute(plan: .gain, vitals: v)
        XCTAssertEqual(t.calories, Int((Double(Targets.tdee(v)) * 1.10).rounded()))
        XCTAssertEqual(t.proteinG, Int((130 * Units.kgPerLb * 1.8).rounded()))
        // Heart-health micros apply to every plan, not just weight loss.
        XCTAssertEqual(t.sodiumMgMax, 1_500)
        XCTAssertEqual(t.addedSugarGMax, 25)
        XCTAssertEqual(t.fiberGMin, 35)
        XCTAssertEqual(t.saturatedFatGMax, Int((Double(t.calories) * 0.10 / 9).rounded()))
        XCTAssertEqual(t.stepsDaily, 8_000)
    }

    func test_lose_targets_500_deficit_and_caps() {
        let v = Targets.ProfileVitals(sex: .male, weightLb: 220, heightIn: 70, age: 45, activity: .light)
        let loseT = Targets.compute(plan: .lose, vitals: v)
        XCTAssertEqual(loseT.calories, Targets.tdee(v) - 500)
        XCTAssertEqual(loseT.proteinG, Int((220 * Units.kgPerLb * 2.0).rounded()))
        XCTAssertEqual(loseT.sodiumMgMax, 1_500)
        XCTAssertEqual(loseT.addedSugarGMax, 25)
        XCTAssertEqual(loseT.fiberGMin, 35)
        XCTAssertGreaterThan(loseT.saturatedFatGMax ?? 0, 0)
        XCTAssertEqual(loseT.stepsDaily, 10_000)
    }

    func test_steps_drop_a_band_at_60() {
        let young = Targets.ProfileVitals(sex: .female, weightLb: 150, heightIn: 64, age: 59, activity: .light)
        let older = Targets.ProfileVitals(sex: .female, weightLb: 150, heightIn: 64, age: 60, activity: .light)
        XCTAssertEqual(Targets.compute(plan: .maintain, vitals: young).stepsDaily, 8_000)
        XCTAssertEqual(Targets.compute(plan: .maintain, vitals: older).stepsDaily, 6_000)
        XCTAssertEqual(Targets.compute(plan: .lose, vitals: older).stepsDaily, 8_000)
    }

    func test_fat_is_30_percent_for_every_plan() {
        let v = Targets.ProfileVitals(sex: .male, weightLb: 180, heightIn: 72, age: 28, activity: .moderate)
        for plan in TargetPlan.suggestions {
            let t = Targets.compute(plan: plan, vitals: v)
            XCTAssertEqual(t.fatG, Int((Double(t.calories) * 0.30 / 9).rounded()), "\(plan)")
        }
    }

    func test_legacy_goal_maps_to_matching_plan() {
        let v = Targets.ProfileVitals(sex: .male, weightLb: 180, heightIn: 72, age: 28, activity: .moderate)
        XCTAssertEqual(Targets.compute(fitnessGoal: .gain, vitals: v), Targets.compute(plan: .gain, vitals: v))
        XCTAssertEqual(Targets.compute(fitnessGoal: .lose, vitals: v), Targets.compute(plan: .lose, vitals: v))
    }

    func test_custom_keeps_numbers_fills_carbs_and_respects_floor() {
        let t = Targets.custom(calories: 2_000, proteinG: 150, fatG: 60, stepsDaily: 7_500)
        XCTAssertEqual(t.calories, 2_000)
        XCTAssertEqual(t.proteinG, 150)
        XCTAssertEqual(t.fatG, 60)
        XCTAssertEqual(t.carbsG, (2_000 - 150 * 4 - 60 * 9) / 4)
        XCTAssertEqual(t.stepsDaily, 7_500)
        XCTAssertEqual(t.plan, .custom)
        XCTAssertEqual(t.fiberGMin, 35)
        XCTAssertEqual(Targets.custom(calories: 900, proteinG: 80, fatG: 30, stepsDaily: 0).calories, 1_200)
    }

    func test_recompute_keeps_custom_and_follows_suggestions() {
        let v1 = Targets.ProfileVitals(sex: .female, weightLb: 160, heightIn: 64, age: 38, activity: .moderate)
        let v2 = Targets.ProfileVitals(sex: .female, weightLb: 150, heightIn: 64, age: 38, activity: .moderate)
        let mine = Targets.custom(calories: 1_800, proteinG: 120, fatG: 55, stepsDaily: 9_000)
        XCTAssertEqual(Targets.recompute(mine, fitnessGoal: .lose, vitals: v2), mine)
        let suggested = Targets.compute(plan: .maintain, vitals: v1)
        XCTAssertEqual(Targets.recompute(suggested, fitnessGoal: .lose, vitals: v2),
                       Targets.compute(plan: .maintain, vitals: v2))
        var legacy = suggested; legacy.plan = nil
        XCTAssertEqual(Targets.recompute(legacy, fitnessGoal: .lose, vitals: v2),
                       Targets.compute(plan: .lose, vitals: v2))
    }

    func test_tilt_goal_follows_calories_for_custom() {
        let below = Targets.custom(calories: 1_800, proteinG: 120, fatG: 55, stepsDaily: 0)
        let above = Targets.custom(calories: 2_600, proteinG: 120, fatG: 55, stepsDaily: 0)
        XCTAssertEqual(Targets.fitnessGoal(for: below, tdee: 2_200), .lose)
        XCTAssertEqual(Targets.fitnessGoal(for: above, tdee: 2_200), .gain)
        XCTAssertEqual(Targets.fitnessGoal(for: Targets.custom(calories: 2_200, proteinG: 1, fatG: 1, stepsDaily: 0), tdee: 2_200), .gain)
    }

    func test_heart_health_micros_identical_across_plans_except_satfat_scaling() {
        let v = Targets.ProfileVitals(sex: .female, weightLb: 160, heightIn: 64, age: 38, activity: .moderate)
        let g = Targets.compute(plan: .gain, vitals: v)
        let l = Targets.compute(plan: .lose, vitals: v)
        XCTAssertEqual(g.sodiumMgMax, l.sodiumMgMax)
        XCTAssertEqual(g.addedSugarGMax, l.addedSugarGMax)
        XCTAssertEqual(g.fiberGMin, l.fiberGMin)
        // Sat-fat cap is 10% of each plan's own calories.
        XCTAssertGreaterThan(g.saturatedFatGMax ?? 0, l.saturatedFatGMax ?? 0)
    }

    func test_calorie_floor_1200() {
        let v = Targets.ProfileVitals(sex: .female, weightLb: 110, heightIn: 60, age: 65, activity: .sedentary)
        let t = Targets.compute(fitnessGoal: .lose, vitals: v)
        XCTAssertGreaterThanOrEqual(t.calories, 1200)
    }

    func test_macro_sum_internally_consistent() {
        let v = Targets.ProfileVitals(sex: .male, weightLb: 180, heightIn: 72, age: 28, activity: .moderate)
        let t = Targets.compute(fitnessGoal: .gain, vitals: v)
        let sum = t.proteinG * 4 + t.carbsG * 4 + t.fatG * 9
        XCTAssertLessThan(abs(sum - t.calories), 20)
    }
}
