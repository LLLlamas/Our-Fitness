import XCTest

final class RepTargetTests: XCTestCase {

    private let uid = UUID()

    /// Local noon on a 2026-11 day, so day keys match in any timezone.
    private func noon(_ day: Int, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    /// Pinned clock: Wednesday 2026-11-25. Last ISO week = Mon 16 … Sun 22.
    private var now: Date { noon(25) }

    private let exercises = [
        ExerciseDTO(id: "squat", name: "Squat", category: .compound, muscleGroups: [], equipment: []),
        ExerciseDTO(id: "plank", name: "Plank", category: .bodyweight, muscleGroups: [], equipment: [],
                    isIsometric: true),
        ExerciseDTO(id: "walk", name: "Walk", category: .bodyweight, muscleGroups: [], equipment: [],
                    kind: .duration),
    ]

    private func set(_ ex: String, _ reps: Int, day: Int, hold: Int? = nil) -> WorkoutSetDTO {
        WorkoutSetDTO(userId: uid, exerciseId: ex, reps: reps, timestamp: noon(day),
                      caloriesEst: 0, holdSeconds: hold)
    }

    // MARK: - Counting

    func test_day_counts_only_todays_rep_exercise_reps() {
        let sets = [
            set("squat", 1, day: 25), set("squat", 1, day: 25), set("squat", 10, day: 25),
            set("plank", 1, day: 25, hold: 60),   // hold — doesn't count
            set("walk", 20, day: 25),             // minutes — doesn't count
            set("squat", 30, day: 24),            // yesterday
        ]
        XCTAssertEqual(RepTarget.reps(sets, exercises: exercises, period: .day, now: now), 12,
                       "+1 taps and a set of ten are the same reps")
    }

    func test_week_counts_monday_to_now() {
        let sets = [
            set("squat", 10, day: 23), set("squat", 5, day: 25),
            set("squat", 40, day: 22),            // last Sunday — previous week
        ]
        XCTAssertEqual(RepTarget.reps(sets, exercises: exercises, period: .week, now: now), 15)
    }

    // MARK: - Default from last week

    func test_no_history_has_no_default() {
        XCTAssertNil(RepTarget.suggestedGoal([], exercises: exercises, period: .day, now: now))
        XCTAssertNil(RepTarget.suggestedGoal([], exercises: exercises, period: .week, now: now))
    }

    func test_holds_and_minutes_alone_give_no_default() {
        let sets = [set("plank", 1, day: 17, hold: 90), set("walk", 30, day: 18)]
        XCTAssertNil(RepTarget.suggestedGoal(sets, exercises: exercises, period: .week, now: now))
    }

    func test_this_weeks_reps_alone_give_no_default() {
        let sets = [set("squat", 50, day: 24)]
        XCTAssertNil(RepTarget.suggestedGoal(sets, exercises: exercises, period: .week, now: now))
    }

    func test_week_default_is_last_weeks_reps_rounded_to_step() {
        // 60 + 52 = 112 → nearest 25 = 100.
        let sets = [set("squat", 60, day: 16), set("squat", 52, day: 20), set("squat", 99, day: 9)]
        XCTAssertEqual(RepTarget.suggestedGoal(sets, exercises: exercises, period: .week, now: now), 100)
    }

    func test_day_default_is_per_trained_day() {
        // 112 reps over 2 trained days = 56 → nearest 5 = 55; rest days don't dilute it.
        let sets = [set("squat", 60, day: 16), set("squat", 52, day: 20)]
        XCTAssertEqual(RepTarget.suggestedGoal(sets, exercises: exercises, period: .day, now: now), 55)
    }

    func test_tiny_week_rounds_up_to_one_step() {
        let sets = [set("squat", 3, day: 17)]
        XCTAssertEqual(RepTarget.suggestedGoal(sets, exercises: exercises, period: .week, now: now), 25)
        XCTAssertEqual(RepTarget.suggestedGoal(sets, exercises: exercises, period: .day, now: now), 5)
    }

    // MARK: - Goal resolution and −/+

    func test_stored_goal_wins_zero_means_unset() {
        XCTAssertEqual(RepTarget.resolve(stored: 80, suggested: 55), 80)
        XCTAssertEqual(RepTarget.resolve(stored: 0, suggested: 55), 55)
        XCTAssertNil(RepTarget.resolve(stored: 0, suggested: nil))
    }

    func test_adjust_steps_and_clamps() {
        XCTAssertEqual(RepTarget.adjusted(50, by: 1, period: .day), 55)
        XCTAssertEqual(RepTarget.adjusted(50, by: -1, period: .day), 45)
        XCTAssertEqual(RepTarget.adjusted(5, by: -1, period: .day), 5, "never below one step")
        XCTAssertEqual(RepTarget.adjusted(10_000, by: 1, period: .week), 10_000)
        XCTAssertEqual(RepTarget.adjusted(100, by: 1, period: .week), 125)
    }

    func test_adjust_from_no_goal() {
        XCTAssertEqual(RepTarget.adjusted(nil, by: 1, period: .day), 5)
        XCTAssertEqual(RepTarget.adjusted(nil, by: 1, period: .week), 25)
        XCTAssertNil(RepTarget.adjusted(nil, by: -1, period: .day))
    }

    func test_fraction() {
        XCTAssertEqual(RepTarget.fraction(reps: 30, goal: 60), 0.5)
        XCTAssertEqual(RepTarget.fraction(reps: 90, goal: 60), 1)
        XCTAssertEqual(RepTarget.fraction(reps: 30, goal: nil), 0)
    }
}
