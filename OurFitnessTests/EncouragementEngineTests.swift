import XCTest

final class EncouragementEngineTests: XCTestCase {

    // MARK: - Fixtures

    private let buildProfile = ProfileDTO(
        name: "Test", fitnessGoal: .gain, sex: .male,
        heightIn: 70, weightLb: 180, age: 28, activity: .moderate,
        computedTargets: MacroTargets(calories: 3000, proteinG: 180, carbsG: 300, fatG: 80, stepsDaily: 8000)
    )

    private func pullUpExercise() -> ExerciseDTO {
        ExerciseDTO(id: "pull-up", name: "Pull-up", category: .bodyweight,
                    muscleGroups: ["Lats"], equipment: [.bodyweight])
    }

    // MARK: - Step milestones

    func testStepMilestone3k_circuit_hasScience() {
        let msg = EncouragementEngine.stepMilestoneMessage(steps: 3000, fitnessGoal: .lose)
        XCTAssertNotNil(msg.scienceLine)
        XCTAssertEqual(msg.tone, .celebrate)
    }

    func testStepMilestone8k_circuit_isImpressed() {
        let msg = EncouragementEngine.stepMilestoneMessage(steps: 8000, fitnessGoal: .lose)
        XCTAssertEqual(msg.tone, .impressed)
    }

    func testStepMilestone3k_build_noScienceLine() {
        let msg = EncouragementEngine.stepMilestoneMessage(steps: 3000, fitnessGoal: .gain)
        XCTAssertNil(msg.scienceLine)
    }

    func testStepMilestone10k_circuit_isCelebrate() {
        let msg = EncouragementEngine.stepMilestoneMessage(steps: 10000, fitnessGoal: .lose)
        XCTAssertEqual(msg.tone, .celebrate)
        XCTAssertEqual(msg.sfSymbol, "checkmark.circle.fill")
    }

    // MARK: - Step approaching

    func testStepApproaching_build_mentionsStepsRemaining() {
        let msg = EncouragementEngine.stepApproachingMessage(stepsRemaining: 500, fitnessGoal: .gain)
        XCTAssertTrue(msg.detail.contains("500"))
        XCTAssertEqual(msg.tone, .approaching)
    }

    func testStepApproaching_circuit_mentionsBloodPressure() {
        let msg = EncouragementEngine.stepApproachingMessage(stepsRemaining: 500, fitnessGoal: .lose)
        XCTAssertTrue(msg.detail.lowercased().contains("blood pressure"))
    }

    // MARK: - Workout milestones

    func testWorkoutMilestone_4sets_scienceTip() {
        let msg = EncouragementEngine.workoutSetMessage(
            exercise: pullUpExercise(), repsJustLogged: 10,
            totalSetsThisWeekForMuscle: 4, fitnessGoal: .gain)
        XCTAssertNotNil(msg)
        XCTAssertEqual(msg?.tone, .scienceTip)
        // Spells out the acronym.
        XCTAssertTrue(msg?.detail.contains("minimum effective volume") ?? false)
    }

    func testWorkoutMilestone_3sets_returnsNil() {
        let msg = EncouragementEngine.workoutSetMessage(
            exercise: pullUpExercise(), repsJustLogged: 10,
            totalSetsThisWeekForMuscle: 3, fitnessGoal: .gain)
        XCTAssertNil(msg)
    }

    func testWorkoutMilestone_10sets_isCelebrate() {
        let msg = EncouragementEngine.workoutSetMessage(
            exercise: pullUpExercise(), repsJustLogged: 10,
            totalSetsThisWeekForMuscle: 10, fitnessGoal: .gain)
        XCTAssertEqual(msg?.tone, .celebrate)
    }

    func testWorkoutMilestone_usesPrimaryMuscleName() {
        let msg = EncouragementEngine.workoutSetMessage(
            exercise: pullUpExercise(), repsJustLogged: 10,
            totalSetsThisWeekForMuscle: 4, fitnessGoal: .gain)
        XCTAssertTrue(msg?.detail.contains("Lats") ?? false)
    }

    // MARK: - Projections

    func testRepProjection_nonNil_for180lb() {
        let p = EncouragementEngine.repProjection(
            exercise: pullUpExercise(), repsLogged: 10,
            totalCaloriesToday: 0, bodyWeightLb: 180)
        XCTAssertNotNil(p)
        XCTAssertTrue(p?.contains("cal") ?? false)
        // No kcal in user-facing copy.
        XCTAssertFalse(p?.contains("kcal") ?? true)
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

    // MARK: - Pilates

    func testPilatesWeeklyGoal_hit_returnsMessage() {
        let msg = EncouragementEngine.pilatesSessionMessage(
            totalSessionsThisWeek: 3, weeklyGoal: 3, fitnessGoal: .lose)
        XCTAssertNotNil(msg)
        XCTAssertEqual(msg?.tone, .celebrate)
    }

    func testPilatesFirstSession_returnsNil() {
        let msg = EncouragementEngine.pilatesSessionMessage(
            totalSessionsThisWeek: 1, weeklyGoal: 3, fitnessGoal: .lose)
        XCTAssertNil(msg)
    }

    // MARK: - Streaks

    func testStreakMilestone_5weeks_build() {
        let msg = EncouragementEngine.streakMilestoneMessage(weeks: 5, fitnessGoal: .gain)
        XCTAssertNotNil(msg)
        XCTAssertTrue(msg?.headline.contains("5-week") ?? false)
    }

    func testStreakMilestone_3weeks_returnsNil() {
        let msg = EncouragementEngine.streakMilestoneMessage(weeks: 3, fitnessGoal: .gain)
        XCTAssertNil(msg)
    }

    func testStreakMilestone_5weeks_circuit_hasScience() {
        let msg = EncouragementEngine.streakMilestoneMessage(weeks: 5, fitnessGoal: .lose)
        XCTAssertNotNil(msg?.scienceLine)
    }

    // MARK: - Macros

    func testProteinGoalHit_build_mentionsMuscleProteinSynthesis() {
        let msg = EncouragementEngine.macroGoalHitMessage(macro: "protein", fitnessGoal: .gain)
        XCTAssertTrue(msg.detail.contains("muscle protein synthesis"))
        XCTAssertEqual(msg.tone, .celebrate)
    }

    func testProteinApproaching_circuit_returnsApproachingTone() {
        let msg = EncouragementEngine.macroApproachingMessage(
            macro: "protein", remaining: 20, unit: "g", fitnessGoal: .lose)
        XCTAssertEqual(msg.tone, .approaching)
        XCTAssertTrue(msg.headline.contains("20g"))
    }

    func testCalorieGoalHit_circuit_noKcalInCopy() {
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

    func testMealStreak_modeShapesCopy() {
        let build = EncouragementEngine.mealStreakMessage(days: 3, fitnessGoal: .gain)
        let circuit = EncouragementEngine.mealStreakMessage(days: 3, fitnessGoal: .lose)
        XCTAssertNotEqual(build?.detail, circuit?.detail)
    }
}
