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
}
