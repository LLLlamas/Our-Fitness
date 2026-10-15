import XCTest

final class TargetRationaleTests: XCTestCase {

    // Build a realistic profile so the rationale math has real inputs.
    private func profile(fitnessGoal: FitnessGoal, weightLb: Double = 180, heightIn: Double = 70,
                         age: Int = 30, sex: Sex = .male, activity: ActivityLevel = .moderate) -> ProfileDTO {
        let v = Targets.ProfileVitals(sex: sex, weightLb: weightLb, heightIn: heightIn, age: age, activity: activity)
        let targets = Targets.compute(fitnessGoal: fitnessGoal, vitals: v)
        return ProfileDTO(
            name: "Test", fitnessGoal: fitnessGoal, sex: sex, heightIn: heightIn,
            weightLb: weightLb, age: age, activity: activity, computedTargets: targets
        )
    }

    // MARK: - Calorie breakdown

    func test_calorie_breakdown_matches_targets_math() {
        let p = profile(fitnessGoal: .gain)
        let c = TargetRationale.calories(for: p)
        XCTAssertEqual(c.bmr, Targets.bmr(sex: .male, weightLb: 180, heightIn: 70, age: 30))
        XCTAssertEqual(c.tdee, Targets.tdee(p.vitals))
        XCTAssertEqual(c.target, p.computedTargets.calories)
        XCTAssertEqual(c.delta, c.target - c.tdee)
    }

    func test_gain_is_surplus_lose_is_deficit() {
        XCTAssertTrue(TargetRationale.calories(for: profile(fitnessGoal: .gain)).isSurplus)
        XCTAssertFalse(TargetRationale.calories(for: profile(fitnessGoal: .lose)).isSurplus)
        XCTAssertLessThan(TargetRationale.calories(for: profile(fitnessGoal: .lose)).delta, 0)
    }

    func test_calorie_why_mentions_maintenance_number() {
        let p = profile(fitnessGoal: .gain)
        let tdee = TargetRationale.calories(for: p).tdee
        XCTAssertTrue(TargetRationale.calorieWhy(for: p).contains("\(tdee)"),
                      "calorie rationale should anchor on the user's maintenance number")
    }

    // MARK: - Protein

    func test_protein_per_lb_is_target_over_weight() {
        let p = profile(fitnessGoal: .lose, weightLb: 200)
        let expected = Double(p.computedTargets.proteinG) / 200.0
        XCTAssertEqual(TargetRationale.proteinPerLb(for: p), expected, accuracy: 0.001)
    }

    func test_protein_why_includes_gram_target() {
        let p = profile(fitnessGoal: .gain)
        XCTAssertTrue(TargetRationale.proteinWhy(for: p).contains("\(p.computedTargets.proteinG)g"))
    }

    // MARK: - Fat

    func test_fat_pct_is_reasonable_for_goal() {
        // Gain ~27%, lose ~28% of calories per Targets.rules.
        XCTAssertEqual(Double(TargetRationale.fatPctOfCalories(for: profile(fitnessGoal: .gain))), 27, accuracy: 3)
        XCTAssertEqual(Double(TargetRationale.fatPctOfCalories(for: profile(fitnessGoal: .lose))), 28, accuracy: 3)
    }

    // MARK: - Goal framing

    func test_goal_line_is_goal_specific_and_plain() {
        XCTAssertTrue(TargetRationale.goalLine(for: .gain).contains("muscle"))
        XCTAssertTrue(TargetRationale.goalLine(for: .lose).contains("lose weight"))
        // No bare acronyms in the goal line.
        XCTAssertFalse(TargetRationale.goalLine(for: .lose).contains("BP"))
    }

    func test_copy_never_names_a_mode() {
        let banned = ["Build", "Circuit", "mode"]
        for goal in FitnessGoal.allCases {
            let p = profile(fitnessGoal: goal)
            let copy = [
                TargetRationale.goalLine(for: goal),
                TargetRationale.calorieWhy(for: p),
                TargetRationale.proteinWhy(for: p),
                TargetRationale.fiberWhy(for: p),
                TargetRationale.sodiumWhy(for: p),
                TargetRationale.addedSugarWhy(for: p),
                TargetRationale.saturatedFatWhy(for: p),
                TargetRationale.stepsWhy(fitnessGoal: goal, goal: 9_000),
            ]
            for line in copy {
                for word in banned {
                    // Whole-word match so "modest" / "moderate" don't trip "mode".
                    XCTAssertNil(line.range(of: "\\b\(word)\\b", options: .regularExpression),
                                 "\(goal): '\(word)' in \(line)")
                }
            }
        }
    }

    // MARK: - Steps

    func test_steps_why_includes_goal_and_is_goal_specific() {
        let lose = TargetRationale.stepsWhy(fitnessGoal: .lose, goal: 10_000)
        XCTAssertTrue(lose.contains("10,000"))
        let gain = TargetRationale.stepsWhy(fitnessGoal: .gain, goal: 8_000)
        XCTAssertTrue(gain.contains("8,000"))
        XCTAssertNotEqual(lose, gain)
    }

    // MARK: - Marker meaning

    func test_marker_meaning_reflects_status_words() {
        // Optimal LDL.
        XCTAssertTrue(TargetRationale.markerMeaning(kind: .ldl, value: 90, fitnessGoal: .lose).contains("healthy range"))
        // High LDL.
        XCTAssertTrue(TargetRationale.markerMeaning(kind: .ldl, value: 160, fitnessGoal: .lose).contains("high"))
    }

    func test_marker_meaning_spells_out_acronyms() {
        let ldl = TargetRationale.markerMeaning(kind: .ldl, value: 90, fitnessGoal: .lose)
        XCTAssertTrue(ldl.localizedCaseInsensitiveContains("cholesterol"))
        let glucose = TargetRationale.markerMeaning(kind: .fastingGlucose, value: 95, fitnessGoal: .lose)
        XCTAssertTrue(glucose.localizedCaseInsensitiveContains("blood sugar"))
    }
}
