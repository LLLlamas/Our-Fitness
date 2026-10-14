import XCTest

final class CalorieEstimatorTests: XCTestCase {

    // Precise locking tests: hard-coded expected values pin every MET constant,
    // the lb→kg conversion, and the gross→net (MET − 1) adjustment. Drift one and
    // the matching test breaks loudly.
    //
    // 180 lb × 0.45359237 = 81.6466266 kg; 150 lb × 0.45359237 = 68.0388555 kg.
    // Every figure below is ACTIVE energy: (MET − 1) × kg × hours.

    func test_reps_loaded_exact_kcal() {
        // 10 reps × 3s = 30s; MET 4.0 → net 3.0
        // kcal = 3.0 × 81.6466266 × (30/3600) = 2.041165665
        let kcal = CalorieEstimator.caloriesForReps(
            reps: 10, loadLb: 30, bodyWeightLb: 180
        )
        XCTAssertEqual(kcal, 2.041165665, accuracy: 0.0001)
    }

    func test_reps_unloaded_exact_kcal() {
        // 10 reps × 3s = 30s; MET 3.5 → net 2.5
        // kcal = 2.5 × 81.6466266 × (30/3600) = 1.7009713875
        let kcal = CalorieEstimator.caloriesForReps(
            reps: 10, loadLb: nil, bodyWeightLb: 180
        )
        XCTAssertEqual(kcal, 1.7009713875, accuracy: 0.0001)
    }

    func test_duration_loaded_exact_kcal() {
        // 10 min; MET 4.5 → net 3.5
        // kcal = 3.5 × 81.6466266 × (10/60) = 47.62719885
        let kcal = CalorieEstimator.caloriesForDuration(
            minutes: 10, loadLb: 25, bodyWeightLb: 180
        )
        XCTAssertEqual(kcal, 47.62719885, accuracy: 0.0001)
    }

    func test_duration_unloaded_exact_kcal() {
        // 10 min; MET 3.5 → net 2.5
        // kcal = 2.5 × 81.6466266 × (10/60) = 34.01942775
        let kcal = CalorieEstimator.caloriesForDuration(
            minutes: 10, loadLb: nil, bodyWeightLb: 180
        )
        XCTAssertEqual(kcal, 34.01942775, accuracy: 0.0001)
    }

    func test_pilates_exact_kcal() {
        // 45 min pilates; MET 3.0 → net 2.0
        // kcal = 2.0 × 81.6466266 × (45/60) = 122.4699399
        let kcal = CalorieEstimator.caloriesForPilates(minutes: 45, bodyWeightLb: 180)
        XCTAssertEqual(kcal, 122.4699399, accuracy: 0.0001)
    }

    func test_isometric_exact_kcal() {
        // 60 s plank at 150 lb; MET 3.8 → net 2.8
        // kcal = 2.8 × 68.0388555 × (60/3600) = 3.17514659
        let kcal = CalorieEstimator.caloriesForIsometric(seconds: 60, bodyWeightLb: 150)
        XCTAssertEqual(kcal, 3.17514659, accuracy: 0.0001)
    }

    func test_steps_exact_kcal() {
        // 10,000 steps at 180 lb; 7,392 steps/h → 1.352813853 h; MET 4.3 → net 3.3
        // kcal = 3.3 × 81.6466266 × 1.352813853 = 364.49386875
        let kcal = CalorieEstimator.caloriesForSteps(steps: 10_000, bodyWeightLb: 180)
        XCTAssertEqual(kcal, 364.49386875, accuracy: 0.0001)
    }

    func test_activity_exact_kcal() {
        // 30 min running (catalog MET 9.0 → net 8.0) at 180 lb
        // kcal = 8.0 × 81.6466266 × 0.5 = 326.5865064
        let kcal = CalorieEstimator.caloriesForActivity(met: 9.0, minutes: 30, bodyWeightLb: 180)
        XCTAssertEqual(kcal, 326.5865064, accuracy: 0.0001)
    }

    // MARK: - The gross→net adjustment itself

    /// Every estimate is activity-only, so it must come out strictly below the
    /// raw compendium product (MET × kg × hours) by exactly one resting MET.
    func test_estimates_are_net_of_one_resting_met() {
        let hours = 1.0
        let kg = 180 * Units.kgPerLb
        let grossPilates = 3.0 * kg * hours
        let netPilates = CalorieEstimator.caloriesForPilates(minutes: 60, bodyWeightLb: 180)
        XCTAssertEqual(grossPilates - netPilates, 1.0 * kg * hours, accuracy: 0.0001)
        XCTAssertLessThan(netPilates, grossPilates)
    }

    /// A sub-resting MET must clamp to zero rather than going negative.
    func test_submetabolic_met_clamps_to_zero() {
        XCTAssertEqual(
            CalorieEstimator.caloriesForActivity(met: 0.8, minutes: 60, bodyWeightLb: 180),
            0, accuracy: 0.0001
        )
        XCTAssertEqual(
            CalorieEstimator.caloriesForActivity(met: 1.0, minutes: 60, bodyWeightLb: 180),
            0, accuracy: 0.0001
        )
        XCTAssertEqual(
            CalorieEstimator.caloriesForIsometric(seconds: 300, met: 0.5, bodyWeightLb: 180),
            0, accuracy: 0.0001
        )
    }

    // Directional tests — cheap, document intent.

    func test_reps_with_load_yields_low_single_digit_kcal() {
        // 5 reps × 3s = 15s ≈ 0.004167 h; net MET 3.0 → ~1.02 kcal
        let kcal = CalorieEstimator.caloriesForReps(
            reps: 5, loadLb: 30, bodyWeightLb: 180
        )
        XCTAssertEqual(kcal, 1.02, accuracy: 0.3)
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
        // 5 min = 0.08333 h; net MET 3.5 → ~23.8 kcal
        let kcal = CalorieEstimator.caloriesForDuration(
            minutes: 5, loadLb: 30, bodyWeightLb: 180
        )
        XCTAssertEqual(kcal, 23.8, accuracy: 5.0)
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
