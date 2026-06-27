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
        let out = ExerciseGoalMatcher.suggestions(for: "I'm trying to get a bigger back and shoulders")
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
        let out = ExerciseGoalMatcher.suggestions(for: "stronger legs and glutes")
        XCTAssertFalse(out.isEmpty)
        let lower = ["quad", "glute", "hamstring", "calf"]
        for s in out {
            XCTAssertTrue(lower.contains { muscleText(s).contains($0) })
        }
        XCTAssertTrue(names(out).contains("Squat"))
    }

    func test_directly_named_exercise_ranks_first() {
        let out = ExerciseGoalMatcher.suggestions(for: "I really want to deadlift more weight")
        XCTAssertEqual(out.first?.exerciseName, "Deadlift")
    }

    func test_unrecognised_goal_falls_back_to_compounds() {
        let out = ExerciseGoalMatcher.suggestions(for: "qwerty zxcvb")
        XCTAssertEqual(names(out), ["Squat", "Deadlift", "Bench Press", "Pull-up", "Overhead Press"])
    }

    func test_respects_limit() {
        let out = ExerciseGoalMatcher.suggestions(for: "full body strength", limit: 3)
        XCTAssertEqual(out.count, 3)
    }

    func test_suggestion_carries_research_reason() {
        let out = ExerciseGoalMatcher.suggestions(for: "bigger chest")
        XCTAssertFalse(out.first?.reason.isEmpty ?? true)
    }

    // Expanded vocabulary: an obliques-specific goal surfaces an oblique exercise.
    func test_love_handles_surfaces_oblique_work() {
        let out = names(ExerciseGoalMatcher.suggestions(for: "trim my love handles", limit: 5))
        XCTAssertTrue(out.contains("Russian Twist") || out.contains("Ab Wheel Rollout"))
    }

    // A grip goal surfaces grip work now that carries exist in the catalog.
    func test_grip_goal_surfaces_grip_work() {
        let out = ExerciseGoalMatcher.suggestions(for: "stronger grip", limit: 5)
        let grippy = ["Farmer Carry", "Dead Hang", "Deadlift", "Barbell Row"]
        XCTAssertTrue(out.contains { grippy.contains($0.exerciseName) })
    }
}
