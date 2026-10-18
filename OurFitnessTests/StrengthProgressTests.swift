import XCTest

final class StrengthProgressTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    // Fixed mid-week "now" — never a bare Date().
    private let now = ISO8601DateFormatter().date(from: "2026-05-27T12:00:00Z")!
    private let uid = UUID()

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: now)!
    }

    private func press(loadLb: Double? = nil, isometric: Bool = false) -> ExerciseDTO {
        ExerciseDTO(id: "press", name: "Bench Press", category: .compound,
                    muscleGroups: ["chest"], equipment: [.barbell],
                    loadLb: loadLb, isIsometric: isometric)
    }

    private func set(_ w: Double?, _ reps: Int, _ offset: Int, ex: String = "press") -> WorkoutSetDTO {
        WorkoutSetDTO(userId: uid, exerciseId: ex, weightLb: w, reps: reps, timestamp: day(offset))
    }

    func testEpleyEstimate() {
        // 100 × (1 + 5/30) = 116.67
        XCTAssertEqual(StrengthProgress.estimatedOneRepMax(weightLb: 100, reps: 5), 100 * (1 + 5.0 / 30), accuracy: 0.001)
        // A single is its own max.
        XCTAssertEqual(StrengthProgress.estimatedOneRepMax(weightLb: 200, reps: 1), 200, accuracy: 0.001)
    }

    func testBestSetPicksHighestEstimateNotHighestWeight() {
        // 185×3 → 203.5   vs   175×8 → 221.7
        let r = StrengthProgress.lifts(sets: [set(185, 3, -2), set(175, 8, -1)],
                                       exercises: [press()], now: now, calendar: cal)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].bestWeightLb, 175)
        XCTAssertEqual(r[0].bestReps, 8)
    }

    func testGainComparesWithBestFromBeforeTheWindow() {
        // Old: 150×5 = 175. Recent: 165×5 = 192.5 → +17.5
        let r = StrengthProgress.lifts(sets: [set(150, 5, -60), set(165, 5, -3)],
                                       exercises: [press()], now: now, calendar: cal)
        XCTAssertEqual(r[0].gainLb ?? 0, 17.5, accuracy: 0.001)
    }

    func testLiftNotTrainedInTheWindowMakesNoGainClaim() {
        let r = StrengthProgress.lifts(sets: [set(150, 5, -60), set(165, 5, -45)],
                                       exercises: [press()], now: now, calendar: cal)
        XCTAssertNil(r[0].gainLb)
    }

    func testNewLiftHasNoGain() {
        let r = StrengthProgress.lifts(sets: [set(135, 5, -3)], exercises: [press()], now: now, calendar: cal)
        XCTAssertNil(r[0].gainLb)
    }

    func testSetsAreIgnoredWhenNotCountable() {
        let sets = [set(nil, 5, -1), set(0, 5, -1), set(135, 13, -1), set(135, 0, -1)]
        XCTAssertTrue(StrengthProgress.lifts(sets: sets, exercises: [press()], now: now, calendar: cal).isEmpty)
    }

    func testFixedLoadAndIsometricExercisesHaveNoEstimatedMax() {
        let sets = [set(30, 10, -1)]
        // A fixed-load exercise is tracked by reps, never by an Epley estimate.
        let fixed = StrengthProgress.lifts(sets: sets, exercises: [press(loadLb: 30)], now: now, calendar: cal)
        XCTAssertEqual(fixed.map(\.metric), [.bestReps])
        XCTAssertNil(fixed[0].gainLb)
        // An isometric set with no hold seconds (legacy row) has nothing to track.
        XCTAssertTrue(StrengthProgress.lifts(sets: sets, exercises: [press(isometric: true)], now: now, calendar: cal).isEmpty)
    }

    func testSetsForUnknownExerciseAreDropped() {
        XCTAssertTrue(StrengthProgress.lifts(sets: [set(100, 5, -1, ex: "gone")],
                                             exercises: [press()], now: now, calendar: cal).isEmpty)
    }

    func testMostRecentlyTrainedFirst() {
        let row = ExerciseDTO(id: "row", name: "Row", category: .compound, muscleGroups: ["back"], equipment: [.barbell])
        let r = StrengthProgress.lifts(
            sets: [set(135, 5, -5), set(95, 5, -1, ex: "row")],
            exercises: [press(), row], now: now, calendar: cal)
        XCTAssertEqual(r.map(\.exerciseId), ["row", "press"])
    }
}
