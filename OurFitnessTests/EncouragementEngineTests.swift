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

    // MARK: - Strength progress copy

    private func w(_ lb: Double) -> String { "\(Int(lb)) lb" }
    private func d(_ key: String) -> String { key }

    func testNewBestAtWeight_namesWeightAndPreviousBest() {
        let msg = EncouragementEngine.newBestMessage(
            .atWeight(measure: .reps, weight: .init(50), amount: 34, previousBest: 30, previousDayKey: "2026-10-02"),
            formatWeight: w, formatDay: d)
        XCTAssertEqual(msg.headline, "New best: 34 reps @ 50 lb")
        XCTAssertTrue(msg.detail.contains("4 more reps"))
        XCTAssertTrue(msg.detail.contains("30 reps on 2026-10-02"))
        XCTAssertEqual(msg.tone, .celebrate)
    }

    func testNewBestBodyweight_hasNoWeightSuffix() {
        let msg = EncouragementEngine.newBestMessage(
            .atWeight(measure: .reps, weight: .bodyweight, amount: 1, previousBest: 0, previousDayKey: "x"),
            formatWeight: w, formatDay: d)
        XCTAssertEqual(msg.headline, "New best: 1 rep")
    }

    func testNewBestMinutes() {
        let msg = EncouragementEngine.newBestMessage(
            .atWeight(measure: .minutes, weight: .init(30), amount: 25, previousBest: 20, previousDayKey: "k"),
            formatWeight: w, formatDay: d)
        XCTAssertEqual(msg.headline, "New best: 25 min @ 30 lb")
        XCTAssertTrue(msg.detail.contains("5 more min"))
    }

    func testHeaviestYetAndLongestHold() {
        let heavy = EncouragementEngine.newBestMessage(
            .heaviest(weightLb: 55, previousLb: 50, previousDayKey: "k"), formatWeight: w, formatDay: d)
        XCTAssertEqual(heavy.headline, "Heaviest yet: 55 lb")
        XCTAssertTrue(heavy.detail.contains("50 lb"))
        let hold = EncouragementEngine.newBestMessage(
            .longestHold(seconds: 75, previousSeconds: 60, previousDayKey: "k"), formatWeight: w, formatDay: d)
        XCTAssertEqual(hold.headline, "Longest hold yet: 1 min 15 s")
        XCTAssertTrue(hold.detail.contains("15 s longer"))
    }

    func testBestHeadlinesStayWithinFiftyCharacters() {
        let bests: [RepHistory.NewBest] = [
            .atWeight(measure: .reps, weight: .init(137.5), amount: 123, previousBest: 100, previousDayKey: "k"),
            .heaviest(weightLb: 137.5, previousLb: 100, previousDayKey: "k"),
            .longestHold(seconds: 3_725, previousSeconds: 60, previousDayKey: "k"),
        ]
        for b in bests {
            let msg = EncouragementEngine.newBestMessage(b, formatWeight: { "\($0) pounds of iron plate" }, formatDay: d)
            XCTAssertLessThanOrEqual(msg.headline.count, 50, msg.headline)
        }
    }

    func testWeeklyRepsMessage_perNote() {
        func msg(_ note: RepHistory.WeeklyNote, this: Int = 100, last: Int = 120) -> EncouragementMessage? {
            EncouragementEngine.weeklyRepsMessage(
                RepHistory.WeeklyReps(thisWeek: this, lastWeek: last, note: note, byExercise: []))
        }
        XCTAssertEqual(msg(.approaching(remaining: 20))?.headline, "20 reps to match last week")
        XCTAssertEqual(msg(.approaching(remaining: 20))?.tone, .approaching)
        XCTAssertEqual(msg(.passed(by: 35), this: 155)?.headline, "+35 reps vs last week")
        XCTAssertEqual(msg(.bestWeek)?.headline, "Most reps in a week yet")
        XCTAssertEqual(msg(.firstWeekBack, last: 0)?.headline, "First week back")
        XCTAssertNil(msg(.none))
    }

    func testWeeklyRepsMessage_neverShamesOrNamesADecrease() {
        let notes: [RepHistory.WeeklyNote] = [.approaching(remaining: 1), .passed(by: 1), .bestWeek, .firstWeekBack]
        for n in notes {
            let m = EncouragementEngine.weeklyRepsMessage(
                RepHistory.WeeklyReps(thisWeek: 10, lastWeek: 11, note: n, byExercise: []))
            let copy = ((m?.headline ?? "") + " " + (m?.detail ?? "")).lowercased()
            for banned in ["missed", "behind", "failed", "worse", "fewer", "lost", "streak"] {
                XCTAssertFalse(copy.contains(banned), "\(n): \(copy)")
            }
            XCTAssertLessThanOrEqual(m?.headline.count ?? 0, 50)
        }
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
