import XCTest

final class EncouragementEngineTests: XCTestCase {

    // MARK: - Fixtures

    private func pullUpExercise() -> ExerciseDTO {
        ExerciseDTO(id: "pull-up", name: "Pull-up", category: .bodyweight,
                    muscleGroups: ["Lats"], equipment: [.bodyweight])
    }

    // MARK: - Step milestones

    func testStepMilestone3k_hasScience() {
        let msg = EncouragementEngine.stepMilestoneMessage(steps: 3000)
        XCTAssertNotNil(msg.scienceLine)
        XCTAssertEqual(msg.tone, .celebrate)
    }

    func testStepMilestone8k_isImpressed() {
        let msg = EncouragementEngine.stepMilestoneMessage(steps: 8000)
        XCTAssertEqual(msg.tone, .impressed)
    }

    func testStepMilestone10k_isCelebrate() {
        let msg = EncouragementEngine.stepMilestoneMessage(steps: 10000)
        XCTAssertEqual(msg.tone, .celebrate)
    }

    /// Step goals differ per user, so no fixed-count milestone may claim the goal is done.
    func testStepMilestones_neverClaimGoalComplete() {
        for steps in [3_000, 5_000, 8_000, 10_000, 12_000] {
            let msg = EncouragementEngine.stepMilestoneMessage(steps: steps)
            let copy = (msg.headline + " " + msg.detail).lowercased()
            XCTAssertFalse(copy.contains("goal complete"), "\(steps)")
            XCTAssertFalse(copy.contains("halfway"), "\(steps)")
            XCTAssertFalse(copy.contains("daily goal"), "\(steps)")
        }
    }

    // MARK: - Workout milestones

    func testWorkoutMilestone_4sets_scienceTip() {
        let msg = EncouragementEngine.workoutSetMessage(
            exercise: pullUpExercise(), repsJustLogged: 10,
            totalSetsThisWeekForMuscle: 4)
        XCTAssertNotNil(msg)
        XCTAssertEqual(msg?.tone, .scienceTip)
        // Spells out the acronym.
        XCTAssertTrue(msg?.detail.contains("minimum effective volume") ?? false)
    }

    func testWorkoutMilestone_3sets_returnsNil() {
        let msg = EncouragementEngine.workoutSetMessage(
            exercise: pullUpExercise(), repsJustLogged: 10,
            totalSetsThisWeekForMuscle: 3)
        XCTAssertNil(msg)
    }

    func testWorkoutMilestone_10sets_isCelebrate() {
        let msg = EncouragementEngine.workoutSetMessage(
            exercise: pullUpExercise(), repsJustLogged: 10,
            totalSetsThisWeekForMuscle: 10)
        XCTAssertEqual(msg?.tone, .celebrate)
    }

    func testWorkoutMilestone_usesPrimaryMuscleName() {
        let msg = EncouragementEngine.workoutSetMessage(
            exercise: pullUpExercise(), repsJustLogged: 10,
            totalSetsThisWeekForMuscle: 4)
        XCTAssertTrue(msg?.detail.contains("Lats") ?? false)
    }

    // MARK: - Projections

    func testRepProjection_nonNil_for180lb() {
        let setCalories = CalorieEstimator.caloriesForSet(
            exercise: pullUpExercise(), reps: 10, holdSeconds: nil, bodyWeightLb: 180)
        let p = EncouragementEngine.repProjection(setCalories: setCalories, totalCaloriesToday: 0)
        XCTAssertNotNil(p)
        XCTAssertTrue(p?.contains("cal") ?? false)
        // No kcal in user-facing copy.
        XCTAssertFalse(p?.contains("kcal") ?? true)
    }

    func testRepProjection_reportsTheStoredSetFigure() {
        let p = EncouragementEngine.repProjection(setCalories: 12.4, totalCaloriesToday: 30)
        XCTAssertEqual(p, "~12 cal this set · 42 cal total today")
        XCTAssertNil(EncouragementEngine.repProjection(setCalories: 0.6, totalCaloriesToday: 30))
    }

    func testStepProjection_zeroRemaining_returnsNil() {
        let p = EncouragementEngine.stepProjection(
            stepsToday: 10000, goalSteps: 8000, bodyWeightLb: 180)
        XCTAssertNil(p)
    }

    func testStepProjection_halfwayToGoal_nonNil() {
        let p = EncouragementEngine.stepProjection(
            stepsToday: 4000, goalSteps: 8000, bodyWeightLb: 180)
        XCTAssertNotNil(p)
        XCTAssertTrue(p?.contains("4000 more steps") ?? false)
    }

    // MARK: - Macros

    func testProteinGoalHit_gain_mentionsMuscleProteinSynthesis() {
        let msg = EncouragementEngine.macroGoalHitMessage(macro: "protein", fitnessGoal: .gain)
        XCTAssertTrue(msg.detail.contains("muscle protein synthesis"))
        XCTAssertEqual(msg.tone, .celebrate)
    }

    func testProteinApproaching_lose_returnsApproachingTone() {
        let msg = EncouragementEngine.macroApproachingMessage(
            macro: "protein", remaining: 20, unit: "g", fitnessGoal: .lose)
        XCTAssertEqual(msg.tone, .approaching)
        XCTAssertTrue(msg.headline.contains("20g"))
    }

    func testCalorieGoalHit_lose_noKcalInCopy() {
        let msg = EncouragementEngine.macroGoalHitMessage(macro: "calories", fitnessGoal: .lose)
        XCTAssertFalse(msg.detail.contains("kcal"))
    }

    // MARK: - Meal-logging streak

    func testMealStreak_nonMilestone_returnsNil() {
        XCTAssertNil(EncouragementEngine.mealStreakMessage(days: 2, fitnessGoal: .gain))
        XCTAssertNil(EncouragementEngine.mealStreakMessage(days: 5, fitnessGoal: .lose))
        XCTAssertNil(EncouragementEngine.mealStreakMessage(days: 0, fitnessGoal: .gain))
    }

    func testMealStreak_milestones_returnMessage() {
        for d in [3, 7, 14, 30, 60, 100] {
            XCTAssertNotNil(EncouragementEngine.mealStreakMessage(days: d, fitnessGoal: .gain),
                            "expected a message at \(d) days")
        }
    }

    func testMealStreak_7day_hasScienceLine() {
        let msg = EncouragementEngine.mealStreakMessage(days: 7, fitnessGoal: .lose)
        XCTAssertNotNil(msg?.scienceLine)
        XCTAssertEqual(msg?.tone, .impressed)
    }

    func testMealStreak_goalShapesCopy() {
        let gain = EncouragementEngine.mealStreakMessage(days: 3, fitnessGoal: .gain)
        let lose = EncouragementEngine.mealStreakMessage(days: 3, fitnessGoal: .lose)
        XCTAssertNotEqual(gain?.detail, lose?.detail)
    }

    /// No nudge copy may name an app mode.
    func testNudgeCopy_neverNamesAMode() {
        for goal in [FitnessGoal.gain, .lose] {
            for hour in [11, 12, 18] {
                for meals in [0, 1] {
                    guard let m = EncouragementEngine.mealLoggingNudge(
                        mealsLoggedToday: meals, hourOfDay: hour, fitnessGoal: goal) else { continue }
                    XCTAssertFalse(m.detail.contains("Circuit") || m.detail.contains("Build"), m.detail)
                }
            }
            for macro in ["protein", "calories"] {
                let m = EncouragementEngine.macroApproachingMessage(
                    macro: macro, remaining: 10, unit: "g", fitnessGoal: goal)
                XCTAssertFalse(m.detail.lowercased().contains("build target"), m.detail)
            }
        }
    }
}
