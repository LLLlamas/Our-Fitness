import XCTest

/// Progress for the exercises the Epley estimate can't cover: bodyweight / one-tap
/// reps, duration carries and isometric holds. Pinned clock, injected UTC calendar.
final class StrengthProgressMetricsTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    // Wednesday 2026-05-27 — never a bare Date().
    private let now = ISO8601DateFormatter().date(from: "2026-05-27T12:00:00Z")!
    private let uid = UUID()

    private func at(_ dayOffset: Int, hour: Int = 0) -> Date {
        cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: dayOffset, to: now)!)!
    }

    private func pullUp() -> ExerciseDTO {
        ExerciseDTO(id: "pu", name: "Pull-up", category: .bodyweight, muscleGroups: [], equipment: [.bodyweight])
    }
    private func plank() -> ExerciseDTO {
        ExerciseDTO(id: "pl", name: "Plank", category: .bodyweight, muscleGroups: [], equipment: [.bodyweight],
                    kind: .duration, isIsometric: true)
    }
    private func carry() -> ExerciseDTO {
        ExerciseDTO(id: "ca", name: "Carried Baby", category: .compound, muscleGroups: [], equipment: [.none],
                    loadLb: 30, kind: .duration)
    }

    private func reps(_ ex: String, _ n: Int, _ offset: Int, hour: Int = 0) -> WorkoutSetDTO {
        WorkoutSetDTO(userId: uid, exerciseId: ex, reps: n, timestamp: at(offset, hour: hour))
    }
    private func hold(_ ex: String, _ secs: Int?, _ offset: Int) -> WorkoutSetDTO {
        WorkoutSetDTO(userId: uid, exerciseId: ex, reps: 1, timestamp: at(offset), holdSeconds: secs)
    }

    func testBodyweightRepsUseTheBestDayAndCompareWithBeforeTheWindow() {
        let sets = [
            reps("pu", 5, -60),                      // before the window: best 5
            reps("pu", 4, -3), reps("pu", 3, -3, hour: 2),   // one day: 7
            reps("pu", 6, -2),
        ]
        let r = StrengthProgress.lifts(sets: sets, exercises: [pullUp()], now: now, calendar: cal)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].metric, .bestReps)
        XCTAssertEqual(r[0].headline, 7)
        XCTAssertEqual(r[0].previousHeadline, 5)
        XCTAssertEqual(r[0].change, 2)
        XCTAssertEqual(r[0].metric.unitLabel, "reps")
        XCTAssertNil(r[0].gainLb, "gainLb stays a loaded-lift (pounds) figure")
    }

    func testOneTapRepsAddUpWithinADay() {
        // The inline +1 button logs a one-rep set per tap.
        let sets = (0..<4).map { reps("pu", 1, -1, hour: $0) }
        let r = StrengthProgress.lifts(sets: sets, exercises: [pullUp()], now: now, calendar: cal)
        XCTAssertEqual(r[0].headline, 4)
    }

    func testIsometricUsesLongestSingleHold() {
        let sets = [hold("pl", 30, -60), hold("pl", 45, -2), hold("pl", 60, -1), hold("pl", nil, -1)]
        let r = StrengthProgress.lifts(sets: sets, exercises: [plank()], now: now, calendar: cal)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].metric, .bestHold)
        XCTAssertEqual(r[0].headline, 60)
        XCTAssertEqual(r[0].previousHeadline, 30)
        XCTAssertEqual(r[0].change, 30)
        XCTAssertEqual(r[0].metric.unitLabel, "sec")
    }

    func testTwoHoldsInADayAreNotAdded() {
        let sets = [hold("pl", 30, -1), hold("pl", 40, -1)]
        let r = StrengthProgress.lifts(sets: sets, exercises: [plank()], now: now, calendar: cal)
        XCTAssertEqual(r[0].headline, 40)
    }

    func testDurationCarryReadsMinutes() {
        let sets = [reps("ca", 10, -40), reps("ca", 15, -2)]
        let r = StrengthProgress.lifts(sets: sets, exercises: [carry()], now: now, calendar: cal)
        XCTAssertEqual(r[0].metric, .bestMinutes)
        XCTAssertEqual(r[0].headline, 15)
        XCTAssertEqual(r[0].change, 5)
        XCTAssertEqual(r[0].metric.unitLabel, "min")
    }

    func testNoChangeClaimedWhenNotTrainedInTheWindow() {
        let r = StrengthProgress.lifts(sets: [reps("pu", 5, -60), reps("pu", 8, -45)],
                                       exercises: [pullUp()], now: now, calendar: cal)
        XCTAssertEqual(r[0].headline, 8)
        XCTAssertNil(r[0].change)
    }

    func testNewExerciseHasNoChange() {
        let r = StrengthProgress.lifts(sets: [reps("pu", 5, -2)], exercises: [pullUp()], now: now, calendar: cal)
        XCTAssertNil(r[0].change)
    }

    func testCardioMobilityAndUnknownExercisesAreSkipped() {
        let run = ExerciseDTO(id: "run", name: "Run", category: .cardio, muscleGroups: [], equipment: [.none])
        let stretch = ExerciseDTO(id: "st", name: "Stretch", category: .mobility, muscleGroups: [], equipment: [.none])
        let sets = [reps("run", 20, -1), reps("st", 10, -1), reps("gone", 10, -1)]
        XCTAssertTrue(StrengthProgress.lifts(sets: sets, exercises: [run, stretch], now: now, calendar: cal).isEmpty)
    }

    func testLoadedLiftsAndOthersSortTogetherMostRecentFirst() {
        let bench = ExerciseDTO(id: "bp", name: "Bench Press", category: .compound,
                                muscleGroups: [], equipment: [.barbell])
        let sets = [
            WorkoutSetDTO(userId: uid, exerciseId: "bp", weightLb: 100, reps: 5, timestamp: at(-3)),
            reps("pu", 6, -1),
        ]
        let r = StrengthProgress.lifts(sets: sets, exercises: [bench, pullUp()], now: now, calendar: cal)
        XCTAssertEqual(r.map(\.exerciseId), ["pu", "bp"])
        XCTAssertEqual(r[1].metric, .estimatedMax)
        XCTAssertEqual(r[1].headline, r[1].estimatedMaxLb, accuracy: 0.001)
        XCTAssertNil(r[1].metric.unitLabel)
    }
}
