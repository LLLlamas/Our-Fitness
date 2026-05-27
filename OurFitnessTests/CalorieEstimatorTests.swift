import XCTest

final class CalorieEstimatorTests: XCTestCase {

    func test_reps_with_load_yields_low_single_digit_kcal() {
        // 5 reps × 3s = 15s ≈ 0.00417 h; 180 lb ≈ 81.65 kg; MET 4.0 → ~1.36 kcal
        let kcal = CalorieEstimator.caloriesForReps(
            reps: 5, loadLb: 30, bodyWeightLb: 180
        )
        XCTAssertEqual(kcal, 1.36, accuracy: 0.3)
    }

    func test_reps_without_load_uses_lower_met() {
        let loaded = CalorieEstimator.caloriesForReps(
            reps: 10, loadLb: 25, bodyWeightLb: 180
        )
        let unloaded = CalorieEstimator.caloriesForReps(
            reps: 10, loadLb: nil, bodyWeightLb: 180
        )
        XCTAssertGreaterThan(loaded, unloaded)
    }

    func test_duration_loaded_walk_5min_180lb() {
        // 5 min = 0.0833 h; 81.65 kg; MET 4.5 → ~30.6 kcal
        let kcal = CalorieEstimator.caloriesForDuration(
            minutes: 5, loadLb: 30, bodyWeightLb: 180
        )
        XCTAssertEqual(kcal, 30.6, accuracy: 5.0)
    }

    func test_duration_unloaded_uses_lower_met() {
        let loaded = CalorieEstimator.caloriesForDuration(
            minutes: 30, loadLb: 30, bodyWeightLb: 180
        )
        let unloaded = CalorieEstimator.caloriesForDuration(
            minutes: 30, loadLb: nil, bodyWeightLb: 180
        )
        XCTAssertGreaterThan(loaded, unloaded)
    }
}
