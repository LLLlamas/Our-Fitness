import XCTest

/// Pins `CalorieEstimator.caloriesForSet` — the ONE per-set estimate that every
/// logging surface and `Repos.updateSet` / `Repos.setCaloriesEstimate` use.
///
/// It dispatches on the exercise's SHAPE (hold → duration → fixed load →
/// researched), never on the user's fitness goal, so a set logged and later
/// corrected lands on the same figure whoever logged it. These tests pin each
/// branch, the branch precedence, and that each scales with the number the user
/// edits.
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

    private func set(_ ex: ExerciseDTO, reps: Int, hold: Int? = nil) -> Double {
        CalorieEstimator.caloriesForSet(exercise: ex, reps: reps, holdSeconds: hold, bodyWeightLb: 180)
    }

    // MARK: - Researched path (no fixed load, counted in reps)

    func test_researched_rep_estimate_scales_with_corrected_rep_count() {
        // Barbell squat: MET 5.0 → net 4.0, 3 s/rep.
        // 10 reps = 30 s → 4.0 × 81.6466266 × (30/3600) = 2.72155422
        let ex = exercise("Barbell Squat")
        XCTAssertEqual(set(ex, reps: 10), 2.72155422, accuracy: 0.0001)
        XCTAssertEqual(set(ex, reps: 10),
                       CalorieEstimator.caloriesForReps(reps: 10, exercise: ex, bodyWeightLb: 180),
                       accuracy: 0.0000001)
        // Fixing a double-tapped 10 back to 5 must halve the stored estimate.
        XCTAssertEqual(set(ex, reps: 5), set(ex, reps: 10) / 2, accuracy: 0.0001)
    }

    // MARK: - Fixed-load path (e.g. Lifted Baby)

    func test_fixed_load_uses_flat_load_aware_estimate_not_researched() {
        // A fixed `loadLb` routes to the flat 4.0 MET (net 3.0), 3 s/rep:
        // 10 reps → 3.0 × 81.6466266 × (30/3600) = 2.041165665.
        let baby = exercise("Lifted Baby", category: .bodyweight, loadLb: 30)
        XCTAssertEqual(set(baby, reps: 10), 2.041165665, accuracy: 0.0001)
        // Same name, no load → researched path; the two must stay distinguishable.
        XCTAssertNotEqual(set(exercise("Barbell Squat"), reps: 10), set(baby, reps: 10), accuracy: 0.01)
    }

    // MARK: - Duration path (reps carries minutes)

    func test_duration_movement_reads_its_count_as_minutes_not_reps() {
        // A `.duration` movement stores MINUTES in `reps`: net 3.5 × 81.6466266 ×
        // 20/60 = 95.2543977 — not the rep estimate (4.08233133 for 20 reps).
        let carry = exercise("Carried Baby", category: .bodyweight, kind: .duration, loadLb: 30)
        XCTAssertEqual(set(carry, reps: 20), 95.2543977, accuracy: 0.0001)
        XCTAssertNotEqual(set(carry, reps: 20),
                          CalorieEstimator.caloriesForReps(reps: 20, loadLb: 30, bodyWeightLb: 180),
                          accuracy: 1)
    }

    // MARK: - Hold path (holdSeconds set)

    func test_hold_estimate_uses_the_exercise_met_not_the_default() {
        // Wall sit: MET 4.0 → net 3.0. 60 s → 3.0 × 81.6466266 × (60/3600) = 4.08233133
        // The bare default (3.8 → net 2.8) would give 3.810175908.
        let wallSit = exercise("Wall Sit", kind: .duration, isIsometric: true)
        XCTAssertEqual(ExerciseInfo.meta(for: wallSit).met, 4.0, accuracy: 0.0001)
        XCTAssertEqual(set(wallSit, reps: 1, hold: 60), 4.08233133, accuracy: 0.0001)
    }

    func test_hold_estimate_scales_with_corrected_seconds() {
        let plank = exercise("Plank", kind: .duration, isIsometric: true)
        XCTAssertEqual(set(plank, reps: 1, hold: 90), set(plank, reps: 1, hold: 60) * 1.5, accuracy: 0.0001)
    }

    func test_hold_takes_precedence_over_duration_and_load() {
        // A hold row is {reps:1, holdSeconds:N}; it must never be read as 1 minute
        // or 1 rep just because the exercise is `.duration` or carries a load.
        let wallSit = exercise("Wall Sit", kind: .duration, loadLb: 25, isIsometric: true)
        let met = ExerciseInfo.meta(for: wallSit).met
        XCTAssertEqual(set(wallSit, reps: 1, hold: 60),
                       CalorieEstimator.caloriesForIsometric(seconds: 60, met: met, bodyWeightLb: 180),
                       accuracy: 0.0000001)
    }

    func test_duration_takes_precedence_over_fixed_load() {
        let carry = exercise("Carried Baby", category: .bodyweight, kind: .duration, loadLb: 30)
        XCTAssertEqual(set(carry, reps: 10),
                       CalorieEstimator.caloriesForDuration(minutes: 10, loadLb: 30, bodyWeightLb: 180),
                       accuracy: 0.0000001)
    }

    // MARK: - What an edit cannot change

    func test_weight_lifted_is_not_an_input_to_the_set_estimate() {
        // Correcting a fat-fingered 1350 lb back to 135 lb changes the stored set
        // weight only: `caloriesForSet` takes no set-weight argument — this is
        // MET × BODY weight × time. Pinned so nobody "fixes" the recompute by
        // folding the lifted load in; that would need a new researched estimator.
        let lift = exercise("Barbell Squat")
        XCTAssertTrue(lift.tracksPerSetWeight)
        XCTAssertEqual(set(lift, reps: 8),
                       CalorieEstimator.caloriesForReps(reps: 8, exercise: lift, bodyWeightLb: 180),
                       accuracy: 0.0000001)
    }

    // MARK: - Exercise shape flags (C1 / C2)

    func test_tracks_per_set_weight_and_one_tap_loggable() {
        let lift = exercise("Barbell Squat")                                  // compound, no load
        let curl = exercise("Dumbbell Curl", category: .isolation)
        let baby = exercise("Lifted Baby", category: .bodyweight, loadLb: 30)
        let carry = exercise("Carried Baby", category: .bodyweight, kind: .duration, loadLb: 30)
        let pushup = exercise("Push-up", category: .bodyweight)
        let loadedCompound = exercise("Sandbag Squat", loadLb: 40)
        let plank = exercise("Plank", category: .bodyweight, kind: .duration, isIsometric: true)
        let isoCompound = exercise("Iso Hold", isIsometric: true)

        XCTAssertTrue(lift.tracksPerSetWeight)
        XCTAssertTrue(curl.tracksPerSetWeight)
        XCTAssertFalse(baby.tracksPerSetWeight)
        XCTAssertFalse(carry.tracksPerSetWeight)
        XCTAssertFalse(pushup.tracksPerSetWeight)
        XCTAssertFalse(loadedCompound.tracksPerSetWeight)
        XCTAssertFalse(plank.tracksPerSetWeight)
        XCTAssertFalse(isoCompound.tracksPerSetWeight)

        XCTAssertFalse(lift.isOneTapLoggable)
        XCTAssertFalse(curl.isOneTapLoggable)
        XCTAssertTrue(baby.isOneTapLoggable)
        XCTAssertTrue(carry.isOneTapLoggable)
        XCTAssertTrue(pushup.isOneTapLoggable)
        XCTAssertTrue(loadedCompound.isOneTapLoggable)
        XCTAssertFalse(plank.isOneTapLoggable)
        XCTAssertFalse(isoCompound.isOneTapLoggable)
    }
}
