import XCTest

/// The calorie invariants `Repos.updateSet` depends on when it recomputes a
/// corrected set's `caloriesEst` (see `Repos.setCaloriesEstimate`).
///
/// Those branches live in Data/ and need a ModelContext, so they can't be
/// exercised from this hostless target. What IS pure — and what would silently
/// rot if someone collapsed the branching — is that the three logging surfaces
/// use three genuinely different estimators, and that each scales with the
/// number the user edits. That is what these pin.
///
/// 180 lb × 0.45359237 = 81.6466266 kg. Every figure is ACTIVE energy: (MET − 1)
/// × kg × hours, matching CalorieEstimatorTests.
final class SetEditCaloriesTests: XCTestCase {

    private func exercise(
        _ name: String,
        category: ExerciseCategory = .compound,
        kind: ExerciseKind = .reps,
        loadLb: Double? = nil,
        isIsometric: Bool = false
    ) -> ExerciseDTO {
        ExerciseDTO(
            id: name, name: name, category: category,
            muscleGroups: [], equipment: [],
            loadLb: loadLb, kind: kind, isIsometric: isIsometric
        )
    }

    // MARK: - Build rep path (RepCounterView.saveSet)

    func test_build_rep_estimate_scales_with_corrected_rep_count() {
        // Barbell squat: MET 5.0 → net 4.0, 3 s/rep.
        // 10 reps = 30 s → 4.0 × 81.6466266 × (30/3600) = 2.72155422
        let ex = exercise("Barbell Squat")
        let ten = CalorieEstimator.caloriesForReps(reps: 10, exercise: ex, bodyWeightLb: 180)
        let five = CalorieEstimator.caloriesForReps(reps: 5, exercise: ex, bodyWeightLb: 180)
        XCTAssertEqual(ten, 2.72155422, accuracy: 0.0001)
        // Fixing a double-tapped 10 back to 5 must halve the stored estimate,
        // never leave the 10-rep figure behind.
        XCTAssertEqual(five, ten / 2, accuracy: 0.0001)
    }

    func test_build_and_circuit_rep_estimates_are_not_interchangeable() {
        // Build uses the exercise's researched MET + tempo; Circuit uses the flat
        // load-aware estimate. An edit must re-derive with the SAME one the log
        // used, so these two must stay distinguishable.
        let ex = exercise("Barbell Squat")
        let build = CalorieEstimator.caloriesForReps(reps: 10, exercise: ex, bodyWeightLb: 180)
        let circuit = CalorieEstimator.caloriesForReps(reps: 10, loadLb: 30, bodyWeightLb: 180)
        XCTAssertEqual(build, 2.72155422, accuracy: 0.0001)
        XCTAssertEqual(circuit, 2.041165665, accuracy: 0.0001)
        XCTAssertNotEqual(build, circuit, accuracy: 0.01)
    }

    // MARK: - Isometric hold path (IsometricTimerView.completeHold)

    func test_hold_estimate_uses_the_exercise_met_not_the_default() {
        // Wall sit: MET 4.0 → net 3.0. 60 s → 3.0 × 81.6466266 × (60/3600) = 4.08233133
        // The bare default (3.8 → net 2.8) would give 3.810175908, so this test
        // fails if the edit path stops passing ExerciseInfo's MET through.
        let met = ExerciseInfo.meta(for: exercise("Wall Sit", kind: .duration, isIsometric: true)).met
        XCTAssertEqual(met, 4.0, accuracy: 0.0001)

        let withMet = CalorieEstimator.caloriesForIsometric(seconds: 60, met: met, bodyWeightLb: 180)
        let withDefault = CalorieEstimator.caloriesForIsometric(seconds: 60, bodyWeightLb: 180)
        XCTAssertEqual(withMet, 4.08233133, accuracy: 0.0001)
        XCTAssertEqual(withDefault, 3.810175908, accuracy: 0.0001)
    }

    func test_hold_estimate_scales_with_corrected_seconds() {
        let met = ExerciseInfo.meta(for: exercise("Plank", kind: .duration, isIsometric: true)).met
        let sixty = CalorieEstimator.caloriesForIsometric(seconds: 60, met: met, bodyWeightLb: 180)
        let ninety = CalorieEstimator.caloriesForIsometric(seconds: 90, met: met, bodyWeightLb: 180)
        XCTAssertEqual(ninety, sixty * 1.5, accuracy: 0.0001)
    }

    // MARK: - Circuit duration path (BabyExercisesCard.logActivity)

    func test_duration_movement_reads_its_count_as_minutes_not_reps() {
        // A Circuit `.duration` movement stores MINUTES in `reps`. Editing 20 has
        // to run through caloriesForDuration (net 3.5 × 81.6466266 × 20/60), not
        // the rep estimator — the two differ by more than an order of magnitude.
        let asMinutes = CalorieEstimator.caloriesForDuration(minutes: 20, loadLb: 30, bodyWeightLb: 180)
        let asReps = CalorieEstimator.caloriesForReps(reps: 20, loadLb: 30, bodyWeightLb: 180)
        XCTAssertEqual(asMinutes, 95.2543977, accuracy: 0.0001)
        XCTAssertEqual(asReps, 4.08233133, accuracy: 0.0001)
    }

    // MARK: - What an edit cannot change

    func test_weight_lifted_is_not_an_input_to_the_build_rep_estimate() {
        // Correcting a fat-fingered 1350 lb back to 135 lb changes the stored
        // weight only: this estimate is MET × BODY weight × time, with no term
        // for the load on the bar, so the recompute lands on the same number.
        // Pinned so nobody "fixes" the recompute by folding the lifted load in —
        // that would need a new researched estimator, not an edit to this path.
        let light = exercise("Barbell Squat", loadLb: 135)
        let absurd = exercise("Barbell Squat", loadLb: 1350)
        XCTAssertEqual(
            CalorieEstimator.caloriesForReps(reps: 8, exercise: light, bodyWeightLb: 180),
            CalorieEstimator.caloriesForReps(reps: 8, exercise: absurd, bodyWeightLb: 180),
            accuracy: 0.0000001
        )
    }
}
