// Tests for the ExerciseInfo named-exercise matcher.
// Hostless target: compiles Domain sources directly, no @testable import.

import XCTest

final class ExerciseInfoTests: XCTestCase {

    private func meta(_ name: String, category: ExerciseCategory = .isolation) -> ExerciseInfo.Meta {
        let ex = ExerciseDTO(
            id: name, name: name, category: category,
            muscleGroups: [], equipment: []
        )
        return ExerciseInfo.meta(for: ex)
    }

    // MARK: - Regression: "leg extension" must NOT match the triceps "extension" branch

    func test_legExtension_isQuads_notTriceps() {
        let m = meta("Leg Extension")
        XCTAssertTrue(m.muscleGroups.contains("Quads"))
        XCTAssertFalse(m.muscleGroups.contains { $0.lowercased().contains("tricep") })
    }

    func test_legCurl_isHamstrings() {
        XCTAssertEqual(meta("Leg Curl").muscleGroups, ["Hamstrings"])
    }

    func test_legPress_isCompoundLowerBody_met5() {
        let m = meta("Leg Press")
        XCTAssertTrue(m.muscleGroups.contains("Quads"))
        XCTAssertTrue(m.muscleGroups.contains("Glutes"))
        XCTAssertEqual(m.met, 5.0, accuracy: 0.001)
    }

    // MARK: - New named entries

    func test_reversePlank_isPosteriorChain_notAnteriorCore() {
        let m = meta("Reverse Plank")
        XCTAssertTrue(m.muscleGroups.contains("Glutes"))
        XCTAssertTrue(m.muscleGroups.contains("Hamstrings"))
        XCTAssertFalse(m.muscleGroups.contains("Rectus abdominis"))
    }

    func test_wallSit_isQuadsGlutes() {
        let m = meta("Wall Sit")
        XCTAssertEqual(m.muscleGroups, ["Quads", "Glutes"])
        XCTAssertEqual(m.met, 4.0, accuracy: 0.001)
    }

    func test_deadHang_isGripAndLats() {
        let m = meta("Dead Hang")
        XCTAssertTrue(m.muscleGroups.contains { $0.lowercased().contains("grip") })
        XCTAssertTrue(m.muscleGroups.contains("Lats"))
    }

    func test_lateralRaise_isLateralDelts() {
        XCTAssertEqual(meta("Lateral Raise").muscleGroups, ["Lateral delts"])
    }

    func test_frontRaise_isAnteriorDelts() {
        XCTAssertEqual(meta("Front Raise").muscleGroups, ["Anterior delts"])
    }

    func test_chestFly_isPectorals() {
        XCTAssertEqual(meta("Dumbbell Fly").muscleGroups, ["Pectorals"])
    }

    // Reverse fly must still read as rear delts, not chest.
    func test_reverseFly_staysRearDelts() {
        let m = meta("Reverse Fly")
        XCTAssertTrue(m.muscleGroups.contains("Rear delts"))
        XCTAssertFalse(m.muscleGroups.contains("Pectorals"))
    }

    // MARK: - Existing entries still resolve

    func test_pullup_stillMatches_met8() {
        XCTAssertEqual(meta("Pull-up").met, 8.0, accuracy: 0.001)
    }

    func test_unknownExercise_fallsBackToCategoryDefault() {
        let m = meta("Cable Woodchopper Thing", category: .compound)
        XCTAssertEqual(m.met, 5.5, accuracy: 0.001) // compound default
    }
}
