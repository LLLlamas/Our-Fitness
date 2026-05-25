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

    func test_build_targets_surplus_and_no_caps() {
        let v = Targets.ProfileVitals(sex: .male, weightLb: 130, heightIn: 67, age: 30, activity: .active)
        let t = Targets.compute(mode: .build, vitals: v)
        XCTAssertEqual(t.proteinG, 130)
        XCTAssertGreaterThan(t.calories, 2800)
        XCTAssertNil(t.sodiumMgMax)
        XCTAssertNil(t.fiberGMin)
        XCTAssertEqual(t.stepsDaily, 8_000)
    }

    func test_reset_targets_deficit_and_caps() {
        let v = Targets.ProfileVitals(sex: .male, weightLb: 220, heightIn: 70, age: 45, activity: .light)
        let resetT = Targets.compute(mode: .reset, vitals: v)
        let buildT = Targets.compute(mode: .build, vitals: v)
        XCTAssertLessThan(resetT.calories, buildT.calories)
        XCTAssertEqual(resetT.sodiumMgMax, 1_500)
        XCTAssertEqual(resetT.addedSugarGMax, 25)
        XCTAssertEqual(resetT.fiberGMin, 35)
        XCTAssertGreaterThan(resetT.saturatedFatGMax ?? 0, 0)
        XCTAssertEqual(resetT.stepsDaily, 10_000)
    }

    func test_calorie_floor_1200() {
        let v = Targets.ProfileVitals(sex: .female, weightLb: 110, heightIn: 60, age: 65, activity: .sedentary)
        let t = Targets.compute(mode: .reset, vitals: v)
        XCTAssertGreaterThanOrEqual(t.calories, 1200)
    }

    func test_macro_sum_internally_consistent() {
        let v = Targets.ProfileVitals(sex: .male, weightLb: 180, heightIn: 72, age: 28, activity: .moderate)
        let t = Targets.compute(mode: .build, vitals: v)
        let sum = t.proteinG * 4 + t.carbsG * 4 + t.fatG * 9
        XCTAssertLessThan(abs(sum - t.calories), 20)
    }

    // MARK: - Adjustments

    func test_build_stalled_suggests_increase() {
        let a = Targets.suggestAdjustment(mode: .build, weeklyDeltaLb: 0.1)
        XCTAssertEqual(a?.direction, .increase)
        XCTAssertEqual(a?.amountCal, 200)
    }

    func test_build_gaining_too_fast_suggests_decrease() {
        XCTAssertEqual(Targets.suggestAdjustment(mode: .build, weeklyDeltaLb: 1.0)?.direction, .decrease)
    }

    func test_build_on_track_returns_nil() {
        XCTAssertNil(Targets.suggestAdjustment(mode: .build, weeklyDeltaLb: 0.4))
    }

    func test_reset_stalled_suggests_cardio() {
        XCTAssertEqual(Targets.suggestAdjustment(mode: .reset, weeklyDeltaLb: 0)?.direction, .addCardio)
    }

    func test_reset_losing_fast_suggests_increase() {
        XCTAssertEqual(Targets.suggestAdjustment(mode: .reset, weeklyDeltaLb: -2.0)?.direction, .increase)
    }

    func test_reset_on_track_returns_nil() {
        XCTAssertNil(Targets.suggestAdjustment(mode: .reset, weeklyDeltaLb: -0.6))
    }

    func test_reset_markers_stalled_8w_flags_doctor() {
        XCTAssertEqual(
            Targets.suggestAdjustment(mode: .reset, weeklyDeltaLb: -0.6, weeksStalledMarkers: 8)?.direction,
            .flagDoctor
        )
    }
}
