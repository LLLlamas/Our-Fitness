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
        XCTAssertEqual(bench?.tally.rowCount, 2)
        XCTAssertEqual(bench?.tally.totalAmount, 18)
        XCTAssertEqual(bench?.tally.lines.map(\.amount), [18], "unweighted rows fold into one bodyweight line")
        XCTAssertEqual(bench?.totalReps, 18)
        XCTAssertEqual(bench?.calories, 55)
        XCTAssertEqual(bench?.setIds.count, 2)

        let plank = recent.exercises.first { $0.exerciseId == "plank" }
        XCTAssertEqual(plank?.isIsometric, true)
        XCTAssertEqual(plank?.totalHoldSeconds, 60)
        XCTAssertEqual(plank?.tally.measure, .holdSeconds)
        XCTAssertEqual(plank?.tally.longestHoldSeconds, 60)

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

    private func repEx(_ id: String) -> ExerciseDTO { ex(id, id) }
    private var catalog: [ExerciseDTO] {
        [repEx("bench"),
         ex("plank", "Plank", isometric: true),
         ExerciseDTO(id: "carry", name: "Carried Baby", category: .bodyweight,
                     muscleGroups: [], equipment: [], loadLb: 30, kind: .duration)]
    }

    func test_exercise_line_carries_the_reps_at_weight_tally() {
        let sets = [
            WorkoutSetDTO(userId: uid, exerciseId: "bench", weightLb: 50, reps: 10, timestamp: ts("2026-05-22T12:00:00Z")),
            WorkoutSetDTO(userId: uid, exerciseId: "bench", weightLb: 50, reps: 20, timestamp: ts("2026-05-22T13:00:00Z")),
            WorkoutSetDTO(userId: uid, exerciseId: "bench", weightLb: 55, reps: 8, timestamp: ts("2026-05-22T14:00:00Z")),
        ]
        let line = TrainingHistory.sessions(sets: sets, exercises: catalog)[0].exercises[0]
        XCTAssertEqual(RepHistory.summary(line.tally, formatWeight: { "\(Int($0)) lb" }), "50 lb × 30 · 55 lb × 8")
    }

    func test_repsInWeek_sums_reps_not_rows_in_the_current_iso_week() {
        let sets = [
            set("bench", reps: 5, at: "2026-05-27T12:00:00Z", cal: 10),  // Wed, this week
            set("bench", reps: 7, at: "2026-05-26T12:00:00Z", cal: 10),  // Tue, this week
            set("bench", reps: 9, at: "2026-05-23T12:00:00Z", cal: 10),  // Sat, last week
        ]
        XCTAssertEqual(TrainingHistory.repsInWeek(sets, exercises: catalog, now: now), 12)
    }

    func test_repsInWeek_excludes_holds_duration_and_unknown_exercises() {
        let sets = [
            set("bench", reps: 5, at: "2026-05-27T12:00:00Z", cal: 10),
            set("plank", reps: 1, at: "2026-05-27T12:00:00Z", cal: 10, hold: 60),
            set("carry", reps: 12, at: "2026-05-27T12:00:00Z", cal: 10),  // minutes
            set("ghost", reps: 40, at: "2026-05-27T12:00:00Z", cal: 10),
        ]
        XCTAssertEqual(TrainingHistory.repsInWeek(sets, exercises: catalog, now: now), 5)
    }

    func test_repsInWeek_weeksAgo_walks_back_one_week_at_a_time() {
        let sets = [
            set("bench", reps: 5, at: "2026-05-27T12:00:00Z", cal: 10),  // this week
            set("bench", reps: 6, at: "2026-05-23T12:00:00Z", cal: 10),  // 1 week ago
            set("bench", reps: 7, at: "2026-05-16T12:00:00Z", cal: 10),  // 2 weeks ago
        ]
        XCTAssertEqual(TrainingHistory.repsInWeek(sets, exercises: catalog, weeksAgo: 1, now: now), 6)
        XCTAssertEqual(TrainingHistory.repsInWeek(sets, exercises: catalog, weeksAgo: 2, now: now), 7)
        XCTAssertEqual(TrainingHistory.repsInWeek(sets, exercises: catalog, weeksAgo: 3, now: now), 0)
    }

    func test_weeklyRepCounts_groups_by_monday_and_sorts_ascending() {
        let sets = [
            set("bench", reps: 5, at: "2026-05-27T12:00:00Z", cal: 10),
            set("bench", reps: 4, at: "2026-05-26T12:00:00Z", cal: 10),
            set("bench", reps: 3, at: "2026-05-23T12:00:00Z", cal: 10),
        ]
        let points = TrainingHistory.weeklyRepCounts(sets, exercises: catalog, now: now)
        XCTAssertEqual(points.map(\.date), ["2026-05-18", "2026-05-25"])
        XCTAssertEqual(points.map(\.value), [3, 9])
    }

    func test_weeklyRepCounts_drops_weeks_outside_the_window() {
        let sets = [
            set("bench", reps: 5, at: "2026-05-27T12:00:00Z", cal: 10),
            set("bench", reps: 5, at: "2026-01-07T12:00:00Z", cal: 10),  // ~20 weeks back
        ]
        let points = TrainingHistory.weeklyRepCounts(sets, exercises: catalog, weeks: 12, now: now)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.date, "2026-05-25")
    }

    func test_weeklyRepCounts_omits_weeks_with_only_holds() {
        let sets = [set("plank", reps: 1, at: "2026-05-27T12:00:00Z", cal: 10, hold: 60)]
        XCTAssertTrue(TrainingHistory.weeklyRepCounts(sets, exercises: catalog, now: now).isEmpty)
    }

    func test_weeklyRepCounts_empty_for_non_positive_window() {
        XCTAssertTrue(TrainingHistory.weeklyRepCounts([], exercises: [], weeks: 0, now: now).isEmpty)
    }
}
