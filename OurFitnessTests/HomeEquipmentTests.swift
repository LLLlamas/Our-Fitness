import XCTest

final class HomeEquipmentTests: XCTestCase {

    func testDefaultKitIsTwentyPoundDumbbellsAndABar() {
        XCTAssertEqual(HomeEquipment.default.maxDumbbellLb, 20)
        XCTAssertTrue(HomeEquipment.default.hasPullUpBar)
    }

    func testStorageRoundTripAndLenientDecode() {
        let kit = HomeEquipment(maxDumbbellLb: 35, hasPullUpBar: false)
        XCTAssertEqual(kit.encoded, "35,0")
        XCTAssertEqual(HomeEquipment(encoded: kit.encoded), kit)
        for bad in [nil, "", "abc", "20", "20,2", "-5,1", "20,1,3"] {
            XCTAssertEqual(HomeEquipment(encoded: bad), .default, "\(bad ?? "nil")")
        }
        XCTAssertEqual(HomeEquipment.storageKey(UUID(uuidString: "11111111-2222-3333-4444-555555555555")!),
                       "equipment.11111111-2222-3333-4444-555555555555")
    }

    func testRequirementsGateOnTheKit() {
        let none = HomeEquipment(maxDumbbellLb: 0, hasPullUpBar: false)
        XCTAssertTrue(none.canDo(exerciseNamed: "Push-up"))
        XCTAssertFalse(none.canDo(exerciseNamed: "Pull-up"))
        XCTAssertFalse(none.canDo(exerciseNamed: "Bicep Curl"))
        let d = HomeEquipment.default
        XCTAssertTrue(d.canDo(exerciseNamed: "Pull-up"))
        XCTAssertTrue(d.canDo(exerciseNamed: "Bicep Curl"))
        XCTAssertFalse(d.canDo(exerciseNamed: "Bench Press"))
        XCTAssertFalse(d.canDo(exerciseNamed: "Leg Press"))
        XCTAssertFalse(d.canDo(exerciseNamed: "Not In The Catalog"), "unknown names are never recommended")
    }

    func testEveryCatalogExerciseIsClassified() {
        for e in ExerciseInfo.catalog {
            XCTAssertTrue(HomeEquipment.isListed(e.name), "\(e.name) is missing from HomeEquipment's table")
        }
    }

    func testMatcherOnlyReturnsExercisesTheKitCanDo() {
        let kit = HomeEquipment.default
        for goal in ["bigger back and shoulders", "stronger legs and glutes", "bigger chest", "bigger arms", "qwerty zxcvb"] {
            let out = ExerciseGoalMatcher.suggestions(for: goal, fitnessGoal: .gain, equipment: kit)
            XCTAssertFalse(out.isEmpty, goal)
            for s in out {
                XCTAssertTrue(kit.canDo(exerciseNamed: s.exerciseName), "\(s.exerciseName) for \(goal)")
            }
        }
    }

    func testMatcherWithoutABarDropsPullUps() {
        let noBar = HomeEquipment(maxDumbbellLb: 20, hasPullUpBar: false)
        let out = ExerciseGoalMatcher.suggestions(for: "bigger back", fitnessGoal: .gain, equipment: noBar)
        XCTAssertFalse(out.contains { ["Pull-up", "Chin-up", "Dead Hang"].contains($0.exerciseName) })
        XCTAssertTrue(out.contains { $0.exerciseName == "Dumbbell Row" })
    }

    func testMatcherWithoutEquipmentIsUnchanged() {
        let out = ExerciseGoalMatcher.suggestions(for: "qwerty zxcvb", fitnessGoal: .gain)
        XCTAssertEqual(out.map(\.exerciseName), ["Squat", "Deadlift", "Bench Press", "Pull-up", "Overhead Press"])
    }
}
