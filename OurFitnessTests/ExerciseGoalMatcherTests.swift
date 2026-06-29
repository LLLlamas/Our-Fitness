import XCTest

final class ExerciseGoalMatcherTests: XCTestCase {

    private func names(_ s: [ExerciseGoalMatcher.GoalSuggestion]) -> [String] {
        s.map(\.exerciseName)
    }

    private func muscleText(_ s: ExerciseGoalMatcher.GoalSuggestion) -> String {
        s.muscleGroups.joined(separator: " ").lowercased()
    }

    func test_catalog_is_populated_and_unique() {
        let cat = ExerciseInfo.catalog
        XCTAssertGreaterThanOrEqual(cat.count, 25)
        XCTAssertEqual(Set(cat.map(\.name)).count, cat.count, "catalog names must be unique")
        // Every catalog entry carries real muscle data (not a category placeholder).
        for e in cat {
            XCTAssertFalse(e.muscleGroups.isEmpty)
            XCTAssertFalse(e.muscleGroups.contains { $0.contains("Multiple major") })
        }
    }

    func test_back_and_shoulders_goal_surfaces_back_or_shoulder_work() {
        let out = ExerciseGoalMatcher.suggestions(for: "I'm trying to get a bigger back and shoulders", mode: .build)
        XCTAssertFalse(out.isEmpty)
        // Every top pick should hit a back or shoulder muscle.
        let backShoulder = ["lat", "rhomboid", "trap", "delt", "erector", "teres", "rotator"]
        for s in out {
            XCTAssertTrue(backShoulder.contains { muscleText(s).contains($0) },
                          "\(s.exerciseName) should target back/shoulders")
        }
        // A canonical back row should appear.
        XCTAssertTrue(names(out).contains { $0.contains("Row") || $0.contains("Pull") })
    }

    func test_legs_goal_surfaces_lower_body() {
        let out = ExerciseGoalMatcher.suggestions(for: "stronger legs and glutes", mode: .build)
        XCTAssertFalse(out.isEmpty)
        let lower = ["quad", "glute", "hamstring", "calf"]
        for s in out {
            XCTAssertTrue(lower.contains { muscleText(s).contains($0) })
        }
        XCTAssertTrue(names(out).contains("Squat"))
    }

    func test_directly_named_exercise_ranks_first() {
        let out = ExerciseGoalMatcher.suggestions(for: "I really want to deadlift more weight", mode: .build)
        XCTAssertEqual(out.first?.exerciseName, "Deadlift")
    }

    func test_unrecognised_goal_falls_back_to_compounds() {
        let out = ExerciseGoalMatcher.suggestions(for: "qwerty zxcvb", mode: .build)
        XCTAssertEqual(names(out), ["Squat", "Deadlift", "Bench Press", "Pull-up", "Overhead Press"])
    }

    func test_respects_limit() {
        let out = ExerciseGoalMatcher.suggestions(for: "full body strength", mode: .build, limit: 3)
        XCTAssertEqual(out.count, 3)
    }

    func test_suggestion_carries_research_reason() {
        let out = ExerciseGoalMatcher.suggestions(for: "bigger chest", mode: .build)
        XCTAssertFalse(out.first?.reason.isEmpty ?? true)
    }

    // Expanded vocabulary: an obliques-specific goal surfaces an oblique exercise.
    func test_love_handles_surfaces_oblique_work() {
        let out = names(ExerciseGoalMatcher.suggestions(for: "trim my love handles", mode: .build, limit: 5))
        XCTAssertTrue(out.contains("Russian Twist") || out.contains("Ab Wheel Rollout"))
    }

    // A grip goal surfaces grip work now that carries exist in the catalog.
    func test_grip_goal_surfaces_grip_work() {
        let out = ExerciseGoalMatcher.suggestions(for: "stronger grip", mode: .build, limit: 5)
        let grippy = ["Farmer Carry", "Dead Hang", "Deadlift", "Barbell Row"]
        XCTAssertTrue(out.contains { grippy.contains($0.exerciseName) })
    }

    // Mode is a tilt, not a filter: both modes still return goal-relevant picks, and
    // the muscle match is never overridden.
    func test_mode_tilt_keeps_goal_relevance_in_both_modes() {
        for mode in [Mode.build, .circuit] {
            let out = ExerciseGoalMatcher.suggestions(for: "stronger legs and glutes", mode: mode)
            XCTAssertFalse(out.isEmpty, "\(mode) should still return picks")
            let lower = ["quad", "glute", "hamstring", "calf"]
            for s in out {
                XCTAssertTrue(lower.contains { muscleText(s).contains($0) },
                              "\(s.exerciseName) should target lower body in \(mode)")
            }
        }
        // A directly-named lift still wins regardless of mode tilt.
        XCTAssertEqual(
            ExerciseGoalMatcher.suggestions(for: "I want to deadlift more", mode: .circuit).first?.exerciseName,
            "Deadlift")
    }
}
