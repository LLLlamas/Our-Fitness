import XCTest

final class TrainingHistoryTests: XCTestCase {

    private let uid = UUID()
    private let iso = ISO8601DateFormatter()

    private func ts(_ s: String) -> Date { iso.date(from: s)! }

    private func ex(_ id: String, _ name: String, isometric: Bool = false) -> ExerciseDTO {
        ExerciseDTO(id: id, name: name, category: isometric ? .bodyweight : .compound,
                    muscleGroups: [], equipment: [], isIsometric: isometric)
    }

    private func set(_ exId: String, reps: Int, at: String, cal: Double, hold: Int? = nil) -> WorkoutSetDTO {
        WorkoutSetDTO(userId: uid, exerciseId: exId, reps: reps,
                      timestamp: ts(at), caloriesEst: cal, holdSeconds: hold)
    }

    func test_empty_input_yields_no_sessions() {
        XCTAssertTrue(TrainingHistory.sessions(sets: [], exercises: []).isEmpty)
    }

    func test_groups_by_day_newest_first_and_aggregates() {
        let exercises = [ex("bench", "Bench Press"), ex("plank", "Plank", isometric: true)]
        // 12:00Z and 14:00Z on the same date land on the same local day in any timezone.
        let sets = [
            set("bench", reps: 10, at: "2026-05-22T12:00:00Z", cal: 30),
            set("bench", reps: 8,  at: "2026-05-22T14:00:00Z", cal: 25),
            set("plank", reps: 1,  at: "2026-05-22T13:00:00Z", cal: 10, hold: 60),
            set("bench", reps: 12, at: "2026-05-20T12:00:00Z", cal: 35),
        ]
        let sessions = TrainingHistory.sessions(sets: sets, exercises: exercises)

        XCTAssertEqual(sessions.count, 2)
        XCTAssertGreaterThan(sessions[0].dayKey, sessions[1].dayKey, "newest day first")

        let recent = sessions[0]
        XCTAssertEqual(recent.totalSets, 3)
        XCTAssertEqual(recent.totalCalories, 65)

        let bench = recent.exercises.first { $0.exerciseId == "bench" }
        XCTAssertEqual(bench?.setCount, 2)
        XCTAssertEqual(bench?.totalReps, 18)
        XCTAssertEqual(bench?.calories, 55)
        XCTAssertEqual(bench?.setIds.count, 2)

        let plank = recent.exercises.first { $0.exerciseId == "plank" }
        XCTAssertEqual(plank?.isIsometric, true)
        XCTAssertEqual(plank?.totalHoldSeconds, 60)

        let older = sessions[1]
        XCTAssertEqual(older.totalSets, 1)
        XCTAssertEqual(older.exercises.first?.totalReps, 12)
    }

    func test_exercises_within_a_day_are_alphabetical() {
        let exercises = [ex("z", "Zercher Squat"), ex("a", "Arm Curl")]
        let sets = [
            set("z", reps: 5, at: "2026-05-22T12:00:00Z", cal: 10),
            set("a", reps: 5, at: "2026-05-22T12:30:00Z", cal: 10),
        ]
        let names = TrainingHistory.sessions(sets: sets, exercises: exercises)[0].exercises.map(\.name)
        XCTAssertEqual(names, ["Arm Curl", "Zercher Squat"])
    }

    func test_unknown_exercise_is_labelled_not_dropped() {
        let sets = [set("ghost", reps: 5, at: "2026-05-22T12:00:00Z", cal: 10)]
        let sessions = TrainingHistory.sessions(sets: sets, exercises: [])
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].exercises.first?.name, "Exercise")
    }

    // MARK: - Weekly volume (ISO / Monday weeks)

    // Pinned clock: Wednesday 2026-05-27. The ISO week it belongs to starts
    // Monday 2026-05-25 — a Sunday-anchored calendar would start it 05-24 and
    // pull the previous Sunday into "this week", which is the bug these lock.
    private let now = ISO8601DateFormatter().date(from: "2026-05-27T12:00:00Z")!

    func test_setsInWeek_counts_only_the_current_iso_week() {
        let sets = [
            set("bench", reps: 5, at: "2026-05-27T12:00:00Z", cal: 10),  // Wed, this week
            set("bench", reps: 5, at: "2026-05-26T12:00:00Z", cal: 10),  // Tue, this week
            set("bench", reps: 5, at: "2026-05-23T12:00:00Z", cal: 10),  // Sat, last week
        ]
        XCTAssertEqual(TrainingHistory.setsInWeek(sets, now: now), 2)
    }

    func test_setsInWeek_weeksAgo_walks_back_one_week_at_a_time() {
        let sets = [
            set("bench", reps: 5, at: "2026-05-27T12:00:00Z", cal: 10),  // this week
            set("bench", reps: 5, at: "2026-05-23T12:00:00Z", cal: 10),  // 1 week ago
            set("bench", reps: 5, at: "2026-05-16T12:00:00Z", cal: 10),  // 2 weeks ago
        ]
        XCTAssertEqual(TrainingHistory.setsInWeek(sets, weeksAgo: 1, now: now), 1)
        XCTAssertEqual(TrainingHistory.setsInWeek(sets, weeksAgo: 2, now: now), 1)
        XCTAssertEqual(TrainingHistory.setsInWeek(sets, weeksAgo: 3, now: now), 0)
    }

    func test_weeklySetCounts_groups_by_monday_and_sorts_ascending() {
        let sets = [
            set("bench", reps: 5, at: "2026-05-27T12:00:00Z", cal: 10),
            set("bench", reps: 5, at: "2026-05-26T12:00:00Z", cal: 10),
            set("bench", reps: 5, at: "2026-05-23T12:00:00Z", cal: 10),
        ]
        let points = TrainingHistory.weeklySetCounts(sets, now: now)
        XCTAssertEqual(points.map(\.date), ["2026-05-18", "2026-05-25"])
        XCTAssertEqual(points.map(\.value), [1, 2])
    }

    func test_weeklySetCounts_drops_weeks_outside_the_window() {
        let sets = [
            set("bench", reps: 5, at: "2026-05-27T12:00:00Z", cal: 10),
            set("bench", reps: 5, at: "2026-01-07T12:00:00Z", cal: 10),  // ~20 weeks back
        ]
        let points = TrainingHistory.weeklySetCounts(sets, weeks: 12, now: now)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.date, "2026-05-25")
    }

    func test_weeklySetCounts_empty_for_non_positive_window() {
        XCTAssertTrue(TrainingHistory.weeklySetCounts([], weeks: 0, now: now).isEmpty)
    }
}
