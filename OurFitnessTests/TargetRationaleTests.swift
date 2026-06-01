import XCTest

final class TargetRationaleTests: XCTestCase {

    // Build a realistic profile so the rationale math has real inputs.
    private func profile(mode: Mode, weightLb: Double = 180, heightIn: Double = 70,
                         age: Int = 30, sex: Sex = .male, activity: ActivityLevel = .moderate) -> ProfileDTO {
        let v = Targets.ProfileVitals(sex: sex, weightLb: weightLb, heightIn: heightIn, age: age, activity: activity)
        let targets = Targets.compute(mode: mode, vitals: v)
        return ProfileDTO(
            name: "Test", mode: mode, sex: sex, heightIn: heightIn,
            weightLb: weightLb, age: age, activity: activity, computedTargets: targets
        )
    }

    // MARK: - Calorie breakdown

    func test_calorie_breakdown_matches_targets_math() {
        let p = profile(mode: .build)
        let c = TargetRationale.calories(for: p)
        XCTAssertEqual(c.bmr, Targets.bmr(sex: .male, weightLb: 180, heightIn: 70, age: 30))
        XCTAssertEqual(c.tdee, Targets.tdee(p.vitals))
        XCTAssertEqual(c.target, p.computedTargets.calories)
        XCTAssertEqual(c.delta, c.target - c.tdee)
    }

    func test_build_is_surplus_circuit_is_deficit() {
        XCTAssertTrue(TargetRationale.calories(for: profile(mode: .build)).isSurplus)
        XCTAssertFalse(TargetRationale.calories(for: profile(mode: .circuit)).isSurplus)
        XCTAssertLessThan(TargetRationale.calories(for: profile(mode: .circuit)).delta, 0)
    }

    func test_calorie_why_mentions_maintenance_number() {
        let p = profile(mode: .build)
        let tdee = TargetRationale.calories(for: p).tdee
        XCTAssertTrue(TargetRationale.calorieWhy(for: p).contains("\(tdee)"),
                      "calorie rationale should anchor on the user's maintenance number")
    }

    // MARK: - Protein

    func test_protein_per_lb_is_target_over_weight() {
        let p = profile(mode: .circuit, weightLb: 200)
        let expected = Double(p.computedTargets.proteinG) / 200.0
        XCTAssertEqual(TargetRationale.proteinPerLb(for: p), expected, accuracy: 0.001)
    }

    func test_protein_why_includes_gram_target() {
        let p = profile(mode: .build)
        XCTAssertTrue(TargetRationale.proteinWhy(for: p).contains("\(p.computedTargets.proteinG)g"))
    }

    // MARK: - Fat

    func test_fat_pct_is_reasonable_for_mode() {
        // Build ~27%, Circuit ~28% of calories per Targets.rules.
        XCTAssertEqual(Double(TargetRationale.fatPctOfCalories(for: profile(mode: .build))), 27, accuracy: 3)
        XCTAssertEqual(Double(TargetRationale.fatPctOfCalories(for: profile(mode: .circuit))), 28, accuracy: 3)
    }

    // MARK: - Goal framing

    func test_goal_line_is_mode_specific_and_plain() {
        XCTAssertTrue(TargetRationale.goalLine(for: .build).contains("muscle"))
        XCTAssertTrue(TargetRationale.goalLine(for: .circuit).contains("lose weight"))
        // No bare acronyms in the goal line.
        XCTAssertFalse(TargetRationale.goalLine(for: .circuit).contains("BP"))
    }

    // MARK: - Steps

    func test_steps_why_includes_goal_and_is_mode_specific() {
        let circuit = TargetRationale.stepsWhy(mode: .circuit, goal: 10_000)
        XCTAssertTrue(circuit.contains("10,000"))
        let build = TargetRationale.stepsWhy(mode: .build, goal: 8_000)
        XCTAssertTrue(build.contains("8,000"))
        XCTAssertNotEqual(circuit, build)
    }

    // MARK: - Marker meaning

    func test_marker_meaning_reflects_status_words() {
        // Optimal LDL.
        XCTAssertTrue(TargetRationale.markerMeaning(kind: .ldl, value: 90, mode: .circuit).contains("healthy range"))
        // High LDL.
        XCTAssertTrue(TargetRationale.markerMeaning(kind: .ldl, value: 160, mode: .circuit).contains("high"))
    }

    func test_marker_meaning_spells_out_acronyms() {
        let ldl = TargetRationale.markerMeaning(kind: .ldl, value: 90, mode: .circuit)
        XCTAssertTrue(ldl.localizedCaseInsensitiveContains("cholesterol"))
        let glucose = TargetRationale.markerMeaning(kind: .fastingGlucose, value: 95, mode: .circuit)
        XCTAssertTrue(glucose.localizedCaseInsensitiveContains("blood sugar"))
    }
}
