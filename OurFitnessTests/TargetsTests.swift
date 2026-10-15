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

    func test_gain_targets_surplus_and_universal_caps() {
        let v = Targets.ProfileVitals(sex: .male, weightLb: 130, heightIn: 67, age: 30, activity: .active)
        let t = Targets.compute(fitnessGoal: .gain, vitals: v)
        XCTAssertEqual(t.proteinG, 130)
        XCTAssertGreaterThan(t.calories, 2800)
        // Heart-health micros apply to every goal, not just weight loss.
        XCTAssertEqual(t.sodiumMgMax, 1_500)
        XCTAssertEqual(t.addedSugarGMax, 25)
        XCTAssertEqual(t.fiberGMin, 35)
        XCTAssertEqual(t.saturatedFatGMax, Int((Double(t.calories) * 0.10 / 9).rounded()))
        XCTAssertEqual(t.stepsDaily, 8_000)
    }

    func test_lose_targets_deficit_and_caps() {
        let v = Targets.ProfileVitals(sex: .male, weightLb: 220, heightIn: 70, age: 45, activity: .light)
        let loseT = Targets.compute(fitnessGoal: .lose, vitals: v)
        let gainT = Targets.compute(fitnessGoal: .gain, vitals: v)
        XCTAssertLessThan(loseT.calories, gainT.calories)
        XCTAssertEqual(loseT.sodiumMgMax, 1_500)
        XCTAssertEqual(loseT.addedSugarGMax, 25)
        XCTAssertEqual(loseT.fiberGMin, 35)
        XCTAssertGreaterThan(loseT.saturatedFatGMax ?? 0, 0)
        XCTAssertEqual(loseT.stepsDaily, 10_000)
    }

    func test_heart_health_micros_identical_across_goals_except_satfat_scaling() {
        let v = Targets.ProfileVitals(sex: .female, weightLb: 160, heightIn: 64, age: 38, activity: .moderate)
        let g = Targets.compute(fitnessGoal: .gain, vitals: v)
        let l = Targets.compute(fitnessGoal: .lose, vitals: v)
        XCTAssertEqual(g.sodiumMgMax, l.sodiumMgMax)
        XCTAssertEqual(g.addedSugarGMax, l.addedSugarGMax)
        XCTAssertEqual(g.fiberGMin, l.fiberGMin)
        // Sat-fat cap is 10% of each goal's own calories.
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
