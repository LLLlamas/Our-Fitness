import XCTest

final class ProgressionTests: XCTestCase {

    private let spec = ProgramSetSpec(exerciseId: "ex", sets: 3, repsBottom: 6, repsTop: 10, rpeCap: 8)

    private func set(reps: Int, weight: Double? = 100, rpe: Double? = nil, id: UUID = UUID()) -> WorkoutSetDTO {
        WorkoutSetDTO(id: id, userId: UUID(), exerciseId: "ex",
                      weightLb: weight, reps: reps, rpe: rpe)
    }

    // MARK: linear

    func test_linear_first_session_prescribes_top() {
        XCTAssertEqual(Progression.nextTarget(scheme: .linear, spec: spec, history: []).targetReps, 10)
    }

    func test_linear_hit_top_adds_5() {
        let t = Progression.nextTarget(scheme: .linear, spec: spec, history: [set(reps: 10, weight: 100)])
        XCTAssertEqual(t.targetWeightLb, 105)
    }

    func test_linear_miss_top_repeats_weight() {
        let t = Progression.nextTarget(scheme: .linear, spec: spec, history: [set(reps: 8, weight: 100)])
        XCTAssertEqual(t.targetWeightLb, 100)
    }

    // MARK: double-progression

    func test_double_progression_first_session_bottom() {
        XCTAssertEqual(
            Progression.nextTarget(scheme: .doubleProgression, spec: spec, history: []).targetReps, 6
        )
    }

    func test_double_progression_hit_top_resets() {
        let t = Progression.nextTarget(scheme: .doubleProgression, spec: spec, history: [set(reps: 10, weight: 100)])
        XCTAssertEqual(t.targetWeightLb, 105)
        XCTAssertEqual(t.targetReps, 6)
    }

    func test_double_progression_mid_range_adds_rep() {
        let t = Progression.nextTarget(scheme: .doubleProgression, spec: spec, history: [set(reps: 7, weight: 100)])
        XCTAssertEqual(t.targetReps, 8)
        XCTAssertEqual(t.targetWeightLb, 100)
    }

    // MARK: rpe-based

    func test_rpe_at_cap_holds_weight() {
        let t = Progression.nextTarget(scheme: .rpeBased, spec: spec, history: [set(reps: 10, weight: 100, rpe: 8)])
        XCTAssertEqual(t.targetWeightLb, 100)
    }

    func test_rpe_below_cap_adds_weight() {
        let t = Progression.nextTarget(scheme: .rpeBased, spec: spec, history: [set(reps: 10, weight: 100, rpe: 6)])
        XCTAssertEqual(t.targetWeightLb, 105)
    }

    // MARK: PR

    func test_pr_returns_nil_on_empty() {
        XCTAssertNil(Progression.personalRecord([]))
    }

    func test_pr_picks_heaviest_then_most_reps() {
        let a = UUID(), b = UUID(), c = UUID()
        let pr = Progression.personalRecord([
            set(reps: 5, weight: 200, id: a),
            set(reps: 8, weight: 200, id: b),
            set(reps: 10, weight: 180, id: c),
        ])
        XCTAssertEqual(pr?.id, b)
    }
}
