import XCTest

final class EncouragementEngineTests: XCTestCase {

    // MARK: - Fixtures

    private let buildProfile = ProfileDTO(
        name: "Test", mode: .build, sex: .male,
        heightIn: 70, weightLb: 180, age: 28, activity: .moderate,
        computedTargets: MacroTargets(calories: 3000, proteinG: 180, carbsG: 300, fatG: 80, stepsDaily: 8000)
    )

    private func pullUpExercise() -> ExerciseDTO {
        ExerciseDTO(id: "pull-up", name: "Pull-up", category: .bodyweight,
                    muscleGroups: ["Lats"], equipment: [.bodyweight])
    }

    // MARK: - Step milestones

    func testStepMilestone3k_circuit_hasScience() {
        let msg = EncouragementEngine.stepMilestoneMessage(steps: 3000, mode: .circuit)
        XCTAssertNotNil(msg.scienceLine)
        XCTAssertEqual(msg.tone, .celebrate)
    }

    func testStepMilestone8k_circuit_isImpressed() {
        let msg = EncouragementEngine.stepMilestoneMessage(steps: 8000, mode: .circuit)
        XCTAssertEqual(msg.tone, .impressed)
    }

    func testStepMilestone3k_build_noScienceLine() {
        let msg = EncouragementEngine.stepMilestoneMessage(steps: 3000, mode: .build)
        XCTAssertNil(msg.scienceLine)
    }

    func testStepMilestone10k_circuit_isCelebrate() {
        let msg = EncouragementEngine.stepMilestoneMessage(steps: 10000, mode: .circuit)
        XCTAssertEqual(msg.tone, .celebrate)
        XCTAssertEqual(msg.sfSymbol, "checkmark.circle.fill")
    }

    // MARK: - Step approaching

    func testStepApproaching_build_mentionsStepsRemaining() {
        let msg = EncouragementEngine.stepApproachingMessage(stepsRemaining: 500, mode: .build)
        XCTAssertTrue(msg.detail.contains("500"))
        XCTAssertEqual(msg.tone, .approaching)
    }

    func testStepApproaching_circuit_mentionsBloodPressure() {
        let msg = EncouragementEngine.stepApproachingMessage(stepsRemaining: 500, mode: .circuit)
        XCTAssertTrue(msg.detail.lowercased().contains("blood pressure"))
    }

    // MARK: - Workout milestones

    func testWorkoutMilestone_4sets_scienceTip() {
        let msg = EncouragementEngine.workoutSetMessage(
            exercise: pullUpExercise(), repsJustLogged: 10,
            totalSetsThisWeekForMuscle: 4, mode: .build)
        XCTAssertNotNil(msg)
        XCTAssertEqual(msg?.tone, .scienceTip)
        // Spells out the acronym.
        XCTAssertTrue(msg?.detail.contains("minimum effective volume") ?? false)
    }

    func testWorkoutMilestone_3sets_returnsNil() {
        let msg = EncouragementEngine.workoutSetMessage(
            exercise: pullUpExercise(), repsJustLogged: 10,
            totalSetsThisWeekForMuscle: 3, mode: .build)
        XCTAssertNil(msg)
    }

    func testWorkoutMilestone_10sets_isCelebrate() {
        let msg = EncouragementEngine.workoutSetMessage(
            exercise: pullUpExercise(), repsJustLogged: 10,
            totalSetsThisWeekForMuscle: 10, mode: .build)
        XCTAssertEqual(msg?.tone, .celebrate)
    }

    func testWorkoutMilestone_usesPrimaryMuscleName() {
        let msg = EncouragementEngine.workoutSetMessage(
            exercise: pullUpExercise(), repsJustLogged: 10,
            totalSetsThisWeekForMuscle: 4, mode: .build)
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
            totalSessionsThisWeek: 3, weeklyGoal: 3, mode: .circuit)
        XCTAssertNotNil(msg)
        XCTAssertEqual(msg?.tone, .celebrate)
    }

    func testPilatesFirstSession_returnsNil() {
        let msg = EncouragementEngine.pilatesSessionMessage(
            totalSessionsThisWeek: 1, weeklyGoal: 3, mode: .circuit)
        XCTAssertNil(msg)
    }

    // MARK: - Streaks

    func testStreakMilestone_5weeks_build() {
        let msg = EncouragementEngine.streakMilestoneMessage(weeks: 5, mode: .build)
        XCTAssertNotNil(msg)
        XCTAssertTrue(msg?.headline.contains("5-week") ?? false)
    }

    func testStreakMilestone_3weeks_returnsNil() {
        let msg = EncouragementEngine.streakMilestoneMessage(weeks: 3, mode: .build)
        XCTAssertNil(msg)
    }

    func testStreakMilestone_5weeks_circuit_hasScience() {
        let msg = EncouragementEngine.streakMilestoneMessage(weeks: 5, mode: .circuit)
        XCTAssertNotNil(msg?.scienceLine)
    }

    // MARK: - Macros

    func testProteinGoalHit_build_mentionsMuscleProteinSynthesis() {
        let msg = EncouragementEngine.macroGoalHitMessage(macro: "protein", mode: .build)
        XCTAssertTrue(msg.detail.contains("muscle protein synthesis"))
        XCTAssertEqual(msg.tone, .celebrate)
    }

    func testProteinApproaching_circuit_returnsApproachingTone() {
        let msg = EncouragementEngine.macroApproachingMessage(
            macro: "protein", remaining: 20, unit: "g", mode: .circuit)
        XCTAssertEqual(msg.tone, .approaching)
        XCTAssertTrue(msg.headline.contains("20g"))
    }

    func testCalorieGoalHit_circuit_noKcalInCopy() {
        let msg = EncouragementEngine.macroGoalHitMessage(macro: "calories", mode: .circuit)
        XCTAssertFalse(msg.detail.contains("kcal"))
    }
}
