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
        let out = ExerciseGoalMatcher.suggestions(for: "I'm trying to get a bigger back and shoulders", fitnessGoal: .gain)
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
        let out = ExerciseGoalMatcher.suggestions(for: "stronger legs and glutes", fitnessGoal: .gain)
        XCTAssertFalse(out.isEmpty)
        let lower = ["quad", "glute", "hamstring", "calf"]
        for s in out {
            XCTAssertTrue(lower.contains { muscleText(s).contains($0) })
        }
        XCTAssertTrue(names(out).contains("Squat"))
    }

    func test_directly_named_exercise_ranks_first() {
        let out = ExerciseGoalMatcher.suggestions(for: "I really want to deadlift more weight", fitnessGoal: .gain)
        XCTAssertEqual(out.first?.exerciseName, "Deadlift")
    }

    func test_unrecognised_goal_falls_back_to_compounds() {
        let out = ExerciseGoalMatcher.suggestions(for: "qwerty zxcvb", fitnessGoal: .gain)
        XCTAssertEqual(names(out), ["Squat", "Deadlift", "Bench Press", "Pull-up", "Overhead Press"])
    }

    func test_respects_limit() {
        let out = ExerciseGoalMatcher.suggestions(for: "full body strength", fitnessGoal: .gain, limit: 3)
        XCTAssertEqual(out.count, 3)
    }

    func test_suggestion_carries_research_reason() {
        let out = ExerciseGoalMatcher.suggestions(for: "bigger chest", fitnessGoal: .gain)
        XCTAssertFalse(out.first?.reason.isEmpty ?? true)
    }

    // Expanded vocabulary: an obliques-specific goal surfaces an oblique exercise.
    func test_love_handles_surfaces_oblique_work() {
        let out = names(ExerciseGoalMatcher.suggestions(for: "trim my love handles", fitnessGoal: .gain, limit: 5))
        XCTAssertTrue(out.contains("Russian Twist") || out.contains("Ab Wheel Rollout"))
    }

    // A grip goal surfaces grip work now that carries exist in the catalog.
    func test_grip_goal_surfaces_grip_work() {
        let out = ExerciseGoalMatcher.suggestions(for: "stronger grip", fitnessGoal: .gain, limit: 5)
        let grippy = ["Farmer Carry", "Dead Hang", "Deadlift", "Barbell Row"]
        XCTAssertTrue(out.contains { grippy.contains($0.exerciseName) })
    }

    // The goal is a tilt, not a filter: both goals still return goal-relevant picks, and
    // the muscle match is never overridden.
    func test_goal_tilt_keeps_relevance_for_both_goals() {
        for fitnessGoal in [FitnessGoal.gain, .lose] {
            let out = ExerciseGoalMatcher.suggestions(for: "stronger legs and glutes", fitnessGoal: fitnessGoal)
            XCTAssertFalse(out.isEmpty, "\(fitnessGoal) should still return picks")
            let lower = ["quad", "glute", "hamstring", "calf"]
            for s in out {
                XCTAssertTrue(lower.contains { muscleText(s).contains($0) },
                              "\(s.exerciseName) should target lower body in \(fitnessGoal)")
            }
        }
        // A directly-named lift still wins regardless of goal tilt.
        XCTAssertEqual(
            ExerciseGoalMatcher.suggestions(for: "I want to deadlift more", fitnessGoal: .lose).first?.exerciseName,
            "Deadlift")
    }

    // MARK: - Tendon drills

    private let tendonDrills = ["Decline Squat", "Eccentric Heel Drop", "Eccentric Wrist Extension",
                                "Heavy Slow Calf Raise", "Spanish Squat"]

    // Each drill must resolve to its own curated entry, not a general squat / tricep /
    // calf-raise branch, and carry the muscles it is meant to load.
    func test_tendon_drills_resolve_to_their_own_curated_meta() {
        for name in tendonDrills {
            guard let e = ExerciseInfo.catalogEntry(named: name), e.name == name else {
                return XCTFail("\(name) missing from catalog")
            }
            XCTAssertTrue(e.meta.benefits.count >= 3, name)
            XCTAssertTrue(e.meta.benefits[0].count > 60, "\(name) leads with a real description")
        }
        func primary(_ name: String) -> String {
            (ExerciseInfo.catalogEntry(named: name)?.muscleGroups ?? []).joined(separator: " ").lowercased()
        }
        XCTAssertTrue(primary("Eccentric Heel Drop").contains("gastrocnemius"))
        XCTAssertTrue(primary("Heavy Slow Calf Raise").contains("soleus"))
        XCTAssertTrue(primary("Decline Squat").contains("quad"))
        XCTAssertTrue(primary("Spanish Squat").contains("quad"))
        XCTAssertTrue(primary("Eccentric Wrist Extension").contains("forearm"),
                      "must not fall into the triceps 'extension' branch")
        XCTAssertTrue(ExerciseInfo.catalogEntry(named: "Spanish Squat")?.isIsometric == true)
        // 3 s down + 3 s up in the heavy-slow trials.
        XCTAssertEqual(ExerciseInfo.catalogEntry(named: "Heavy Slow Calf Raise")?.meta.secondsPerRep, 6.0)
    }

    func test_tendon_goals_lead_with_the_matching_drill() {
        let cases: [(goal: String, expect: [String])] = [
            ("my Achilles tendon hurts", ["Eccentric Heel Drop", "Heavy Slow Calf Raise"]),
            ("patellar tendon / jumper's knee", ["Decline Squat", "Spanish Squat"]),
            ("tennis elbow", ["Eccentric Wrist Extension"]),
        ]
        for c in cases {
            for fitnessGoal in [FitnessGoal.gain, .lose] {
                let out = names(ExerciseGoalMatcher.suggestions(for: c.goal, fitnessGoal: fitnessGoal))
                XCTAssertFalse(out.isEmpty, c.goal)
                XCTAssertTrue(c.expect.contains(out[0]), "\(c.goal) led with \(out[0]) (\(fitnessGoal))")
                XCTAssertTrue(c.expect.allSatisfy(out.contains), "\(c.goal) should list \(c.expect): \(out)")
            }
        }
        // A bare "tendon" goal surfaces tendon drills first, not general lifts.
        let generic = names(ExerciseGoalMatcher.suggestions(for: "stronger tendons", fitnessGoal: .gain))
        XCTAssertTrue(tendonDrills.contains(generic[0]), "got \(generic)")
    }

    // "lateral" also trips the back-muscle key "lat", so back work may appear, but the
    // forearm drill must still lead.
    func test_lateral_epicondylitis_still_leads_with_the_wrist_drill() {
        let out = names(ExerciseGoalMatcher.suggestions(for: "lateral epicondylitis", fitnessGoal: .gain))
        XCTAssertEqual(out.first, "Eccentric Wrist Extension", "\(out)")
    }

    // Without tendon wording nothing changes: a plain calves goal still lists Calf Raise.
    func test_plain_calf_goal_unchanged() {
        let out = names(ExerciseGoalMatcher.suggestions(for: "bigger calves", fitnessGoal: .gain))
        XCTAssertTrue(out.contains("Calf Raise"), "\(out)")
    }
}
