import XCTest

final class MuscleVolumeTests: XCTestCase {

    // Wednesday 2026-05-27 — never a bare Date().
    private let now = ISO8601DateFormatter().date(from: "2026-05-27T12:00:00Z")!
    private let uid = UUID()

    private var pullUp: ExerciseDTO {
        ExerciseDTO(id: "pu", name: "Pull-up", category: .bodyweight, muscleGroups: [], equipment: [.bodyweight])
    }
    private var pushUp: ExerciseDTO {
        ExerciseDTO(id: "pr", name: "Push-up", category: .bodyweight, muscleGroups: [], equipment: [.bodyweight])
    }

    private func set(_ ex: String, at date: Date) -> WorkoutSetDTO {
        WorkoutSetDTO(userId: uid, exerciseId: ex, reps: 8, timestamp: date)
    }
    private func sets(_ ex: String, _ n: Int, at date: Date) -> [WorkoutSetDTO] {
        (0..<n).map { _ in set(ex, at: date) }
    }
    private func count(_ rows: [MuscleVolume.Row], _ g: MuscleVolume.Group) -> Int {
        rows.first { $0.group == g }?.sets ?? -1
    }

    // MARK: Mapping

    func testMuscleLabelsMapToGroups() {
        XCTAssertEqual(MuscleVolume.group(forMuscle: "Pectorals"), .chest)
        XCTAssertEqual(MuscleVolume.group(forMuscle: "Upper pectorals"), .chest)
        XCTAssertEqual(MuscleVolume.group(forMuscle: "Lats"), .back)
        XCTAssertEqual(MuscleVolume.group(forMuscle: "Rhomboids"), .back)
        XCTAssertEqual(MuscleVolume.group(forMuscle: "Lateral delts"), .shoulders, "not a lat")
        XCTAssertEqual(MuscleVolume.group(forMuscle: "Rear delts"), .shoulders)
        XCTAssertEqual(MuscleVolume.group(forMuscle: "Biceps (supinated emphasis)"), .biceps)
        XCTAssertEqual(MuscleVolume.group(forMuscle: "Triceps brachii (all 3 heads)"), .triceps)
        XCTAssertEqual(MuscleVolume.group(forMuscle: "Quads (front emphasis)"), .quads)
        XCTAssertEqual(MuscleVolume.group(forMuscle: "Hamstrings"), .hamstrings)
        XCTAssertEqual(MuscleVolume.group(forMuscle: "Gluteus maximus"), .glutes)
        XCTAssertEqual(MuscleVolume.group(forMuscle: "Gastrocnemius"), .calves)
        // Outside the nine sourced groups.
        XCTAssertNil(MuscleVolume.group(forMuscle: "Forearms/Grip"))
        XCTAssertNil(MuscleVolume.group(forMuscle: "Erector spinae"))
        XCTAssertNil(MuscleVolume.group(forMuscle: "Rectus abdominis"))
    }

    func testExerciseGroupsComeFromTheCuratedLibrary() {
        XCTAssertEqual(MuscleVolume.groups(for: pullUp), [.back, .biceps, .shoulders])
        XCTAssertTrue(MuscleVolume.groups(for: pushUp).isSuperset(of: [.chest, .triceps]))
    }

    func testCustomExerciseFallsBackToItsStoredMuscles() {
        let custom = ExerciseDTO(id: "c", name: "Zzz Mover", category: .isolation,
                                 muscleGroups: ["Quads"], equipment: [.dumbbell])
        XCTAssertEqual(MuscleVolume.groups(for: custom), [.quads])
    }

    func testCardioAndMobilityNeverCount() {
        let run = ExerciseDTO(id: "r", name: "Squat Jog", category: .cardio, muscleGroups: ["Quads"], equipment: [.none])
        let mob = ExerciseDTO(id: "m", name: "Squat Stretch", category: .mobility, muscleGroups: ["Quads"], equipment: [.none])
        XCTAssertTrue(MuscleVolume.groups(for: run).isEmpty)
        XCTAssertTrue(MuscleVolume.groups(for: mob).isEmpty)
    }

    // MARK: Weekly counting around the Monday boundary

    func testWeekRunsMondayToSundayInclusiveOfTheBoundarySecond() {
        let monday = Dates.startOfISOWeek(now)
        let nextMonday = Dates.startOfISOWeek(now, weeksAgo: -1)
        let all = [
            set("pu", at: monday.addingTimeInterval(-1)),      // Sunday night, last week
            set("pu", at: monday),                             // Monday 00:00, this week
            set("pu", at: now),                                // this week
            set("pu", at: nextMonday.addingTimeInterval(-1)),  // Sunday 23:59:59, this week
            set("pu", at: nextMonday),                         // next week
        ]
        let rows = MuscleVolume.weekly(sets: all, exercises: [pullUp], now: now)
        XCTAssertEqual(count(rows, .back), 3)
    }

    func testRowsListEveryGroupIncludingZeros() {
        let rows = MuscleVolume.weekly(sets: sets("pu", 2, at: now), exercises: [pullUp], now: now)
        XCTAssertEqual(rows.map(\.group), MuscleVolume.Group.allCases)
        XCTAssertEqual(count(rows, .back), 2)
        XCTAssertEqual(count(rows, .calves), 0)
    }

    func testOneSetCountsOncePerGroupAndIgnoresUnknownExercises() {
        let all = sets("pu", 1, at: now) + sets("pr", 1, at: now) + sets("gone", 5, at: now)
        let rows = MuscleVolume.weekly(sets: all, exercises: [pullUp, pushUp], now: now)
        XCTAssertEqual(count(rows, .back), 1)
        XCTAssertEqual(count(rows, .chest), 1)
    }

    // MARK: Status

    func testStatusThresholdIsTheWeeklyTarget() {
        XCTAssertEqual(MuscleVolume.weeklySetTarget, 10)
        XCTAssertEqual(MuscleVolume.Row(group: .back, sets: 0).status, .below)
        XCTAssertEqual(MuscleVolume.Row(group: .back, sets: 9).status, .below)
        XCTAssertEqual(MuscleVolume.Row(group: .back, sets: 10).status, .reached)
        XCTAssertEqual(MuscleVolume.Row(group: .back, sets: 30).status, .reached, "no upper limit is claimed")
    }

    // MARK: Recommendations

    func testRecommendationNamesAnExerciseTheKitCanDo() {
        let rows = MuscleVolume.weekly(sets: sets("pu", 4, at: now), exercises: [pullUp], now: now)
        let recs = MuscleVolume.recommendations(rows: rows, equipment: .default, limit: 9)
        XCTAssertEqual(recs.first { $0.group == .back }?.text, "Back: 4 of 10 sets this week. Add Pull-up.")

        let noBar = HomeEquipment(maxDumbbellLb: 20, hasPullUpBar: false)
        let r2 = MuscleVolume.recommendations(rows: rows, equipment: noBar, limit: 9)
        XCTAssertEqual(r2.first { $0.group == .back }?.exerciseName, "Dumbbell Row")

        let nothing = HomeEquipment(maxDumbbellLb: 0, hasPullUpBar: false)
        let r3 = MuscleVolume.recommendations(rows: rows, equipment: nothing, limit: 9)
        XCTAssertNil(r3.first { $0.group == .back }?.exerciseName)
        XCTAssertEqual(r3.first { $0.group == .back }?.text, "Back: 4 of 10 sets this week.")
    }

    func testOnlyUnderTrainedGroupsSortedByShortfallAndLimited() {
        let all = sets("pu", 12, at: now)   // back, biceps, shoulders all reach 10
        let rows = MuscleVolume.weekly(sets: all + sets("pr", 3, at: now), exercises: [pullUp, pushUp], now: now)
        let recs = MuscleVolume.recommendations(rows: rows, equipment: .default, limit: 3)
        XCTAssertEqual(recs.count, 3)
        XCTAssertFalse(recs.contains { [.back, .biceps, .shoulders].contains($0.group) })
        XCTAssertEqual(recs.map(\.sets), recs.map(\.sets).sorted(), "fewest sets first")
    }

    func testEveryGroupHasADefaultKitExerciseThatIsInTheCatalog() {
        let names = Set(ExerciseInfo.catalog.map(\.name))
        for g in MuscleVolume.Group.allCases {
            let name = MuscleVolume.exercise(for: g, equipment: .default)
            XCTAssertNotNil(name, "\(g)")
            XCTAssertTrue(names.contains(name ?? ""), "\(name ?? "nil") must be a catalog entry")
        }
    }

    func testNewCatalogEntriesResolveToTheirIntendedMuscles() {
        func groups(_ name: String) -> Set<MuscleVolume.Group> {
            guard let e = ExerciseInfo.catalog.first(where: { $0.name == name }) else { return [] }
            return Set(e.muscleGroups.compactMap(MuscleVolume.group(forMuscle:)))
        }
        XCTAssertTrue(groups("Pike Push-up").contains(.shoulders))
        XCTAssertTrue(groups("Dumbbell Row").contains(.back))
        XCTAssertTrue(groups("Bulgarian Split Squat").contains(.quads))
        XCTAssertTrue(groups("Tricep Extension").contains(.triceps))
    }
}
