import XCTest

final class CalorieEstimatorTests: XCTestCase {

    // Precise locking tests: hard-coded expected values pin every MET constant
    // and the lb→kg conversion. Drift one and the matching test breaks loudly.

    func test_reps_loaded_exact_kcal() {
        // 10 reps × 3s = 30s; 180 lb × 0.453592 = 81.64656 kg; MET 4.0
        // kcal = 4.0 × 81.64656 × (30/3600) = 2.7215520
        let kcal = CalorieEstimator.caloriesForReps(
            reps: 10, loadLb: 30, bodyWeightLb: 180
        )
        XCTAssertEqual(kcal, 2.7215520, accuracy: 0.01)
    }

    func test_reps_unloaded_exact_kcal() {
        // 10 reps × 3s = 30s; 81.64656 kg; MET 3.5
        // kcal = 3.5 × 81.64656 × (30/3600) = 2.3813580
        let kcal = CalorieEstimator.caloriesForReps(
            reps: 10, loadLb: nil, bodyWeightLb: 180
        )
        XCTAssertEqual(kcal, 2.3813580, accuracy: 0.01)
    }

    func test_duration_loaded_exact_kcal() {
        // 10 min; 81.64656 kg; MET 4.5
        // kcal = 4.5 × 81.64656 × (10/60) = 61.23492
        let kcal = CalorieEstimator.caloriesForDuration(
            minutes: 10, loadLb: 25, bodyWeightLb: 180
        )
        XCTAssertEqual(kcal, 61.23492, accuracy: 0.01)
    }

    func test_duration_unloaded_exact_kcal() {
        // 10 min; 81.64656 kg; MET 3.5
        // kcal = 3.5 × 81.64656 × (10/60) = 47.62716
        let kcal = CalorieEstimator.caloriesForDuration(
            minutes: 10, loadLb: nil, bodyWeightLb: 180
        )
        XCTAssertEqual(kcal, 47.62716, accuracy: 0.01)
    }

    // Directional tests — cheap, document intent.

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
