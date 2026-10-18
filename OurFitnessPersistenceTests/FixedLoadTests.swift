import XCTest
import SwiftData

/// Fixed-load exercises (Lifted Baby, ...) keep the load each row was done at:
/// `Repos.updateExercise` edits the load without re-reading history, the launch
/// backfill stamps pre-existing rows once, and `Repos.updateSet` prices a row at
/// its own stamped weight. Pinned `now`-free: every timestamp is a fixed instant.
@MainActor
final class FixedLoadTests: XCTestCase {
    enum Failure: Error { case diskFull }

    private let user = UUID()
    private let anchor = Date(timeIntervalSince1970: 1_800_000_000)

    /// A context traps on use once its container deallocates, so the test keeps every container it makes.
    private var containers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let schema = Schema([ExerciseModel.self, WorkoutSetModel.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        containers.append(container)
        return container.mainContext
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "FixedLoadTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    @discardableResult
    private func insertExercise(
        _ ctx: ModelContext, id: String, name: String, loadLb: Double?,
        kind: ExerciseKind = .reps, isIsometric: Bool = false
    ) throws -> ExerciseDTO {
        let dto = ExerciseDTO(id: id, name: name, category: loadLb == nil ? .compound : .bodyweight,
                              muscleGroups: [], equipment: [], loadLb: loadLb,
                              kind: kind, isIsometric: isIsometric)
        ctx.insert(ExerciseModel(snapshot: dto))
        try ctx.save()
        return dto
    }

    @discardableResult
    private func insertSet(
        _ ctx: ModelContext, exercise: String, reps: Int = 5, weightLb: Double? = nil,
        holdSeconds: Int? = nil, offset: TimeInterval = 0
    ) throws -> UUID {
        let dto = WorkoutSetDTO(userId: user, exerciseId: exercise, weightLb: weightLb, reps: reps,
                                timestamp: anchor.addingTimeInterval(offset),
                                caloriesEst: 1, holdSeconds: holdSeconds)
        ctx.insert(WorkoutSetModel(snapshot: dto))
        try ctx.save()
        return dto.id
    }

    private func sets(_ ctx: ModelContext, _ exercise: String) -> [WorkoutSetDTO] {
        Repos.setHistory(ctx, userId: user, exerciseId: exercise, limit: 1000)
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func exercise(_ ctx: ModelContext, _ id: String) throws -> ExerciseDTO {
        // The fixtures carry no profileId, so read the rows directly.
        try XCTUnwrap(ctx.fetch(FetchDescriptor<ExerciseModel>()).first { $0.id == id }?.snapshot)
    }

    // MARK: - updateExercise

    func testUpdateExerciseRenamesAndChangesLoad() throws {
        let ctx = try makeContext()
        try insertExercise(ctx, id: "baby", name: "Lifted Baby", loadLb: 30)
        XCTAssertTrue(Repos.updateExercise(ctx, id: "baby", name: "  Lifted Mia \n", loadLb: 32.5))
        let ex = try exercise(ctx, "baby")
        XCTAssertEqual(ex.name, "Lifted Mia")
        XCTAssertEqual(ex.loadLb, 32.5)   // exact, no rounding
    }

    func testUpdateExerciseWithNothingToChangeSucceedsAndWritesNothing() throws {
        let ctx = try makeContext()
        try insertExercise(ctx, id: "baby", name: "Lifted Baby", loadLb: 30)
        XCTAssertTrue(Repos.updateExercise(ctx, id: "baby"))
        XCTAssertTrue(Repos.updateExercise(ctx, id: "baby", name: "Lifted Baby", loadLb: 30))
        XCTAssertEqual(try exercise(ctx, "baby").loadLb, 30)
    }

    func testUpdateExerciseValidationFailuresLeaveEverythingUnchanged() throws {
        let ctx = try makeContext()
        try insertExercise(ctx, id: "baby", name: "Lifted Baby", loadLb: 30)
        try insertExercise(ctx, id: "squat", name: "Squat", loadLb: nil)
        try insertSet(ctx, exercise: "baby")

        XCTAssertFalse(Repos.updateExercise(ctx, id: "baby", name: "   "))
        XCTAssertFalse(Repos.updateExercise(ctx, id: "baby", loadLb: 0))
        XCTAssertFalse(Repos.updateExercise(ctx, id: "baby", loadLb: -5))
        XCTAssertFalse(Repos.updateExercise(ctx, id: "baby", loadLb: .nan))
        XCTAssertFalse(Repos.updateExercise(ctx, id: "baby", loadLb: .infinity))
        XCTAssertFalse(Repos.updateExercise(ctx, id: "baby", loadLb: Repos.maxFixedLoadLb + 1))
        // A good name must not slip through alongside a bad load.
        XCTAssertFalse(Repos.updateExercise(ctx, id: "baby", name: "Renamed", loadLb: 0))
        // Only an exercise that already has a fixed load can be given a new one.
        XCTAssertFalse(Repos.updateExercise(ctx, id: "squat", loadLb: 40))
        XCTAssertFalse(Repos.updateExercise(ctx, id: "missing", name: "x"))

        let baby = try exercise(ctx, "baby")
        XCTAssertEqual(baby.name, "Lifted Baby")
        XCTAssertEqual(baby.loadLb, 30)
        XCTAssertNil(try exercise(ctx, "squat").loadLb)
        XCTAssertNil(sets(ctx, "baby").first?.weightLb, "a refused edit must not stamp rows")
        XCTAssertFalse(ctx.hasChanges)
    }

    func testUpdateExerciseAcceptsTheUpperBound() throws {
        let ctx = try makeContext()
        try insertExercise(ctx, id: "baby", name: "Lifted Baby", loadLb: 30)
        XCTAssertTrue(Repos.updateExercise(ctx, id: "baby", loadLb: Repos.maxFixedLoadLb))
        XCTAssertEqual(try exercise(ctx, "baby").loadLb, Repos.maxFixedLoadLb)
    }

    func testChangingLoadStampsExistingUnweightedRowsWithTheOldLoadFirst() throws {
        let ctx = try makeContext()
        try insertExercise(ctx, id: "baby", name: "Lifted Baby", loadLb: 30)
        try insertExercise(ctx, id: "stroller", name: "Lifted Stroller", loadLb: 25)
        try insertSet(ctx, exercise: "baby", weightLb: nil, offset: 0)       // legacy row
        try insertSet(ctx, exercise: "baby", weightLb: 28, offset: 60)       // already stamped (older, lighter)
        try insertSet(ctx, exercise: "baby", reps: 1, weightLb: nil, holdSeconds: 40, offset: 120)  // hold
        try insertSet(ctx, exercise: "stroller", weightLb: nil)              // another exercise

        XCTAssertTrue(Repos.updateExercise(ctx, id: "baby", loadLb: 34))

        let baby = sets(ctx, "baby")
        XCTAssertEqual(baby.map(\.weightLb), [30, 28, nil], "legacy row = OLD load; stamped row kept; hold untouched")
        XCTAssertNil(sets(ctx, "stroller").first?.weightLb, "other exercises are not touched")
        XCTAssertEqual(try exercise(ctx, "baby").loadLb, 34)

        // Rows logged afterwards are the caller's to stamp at the new load; the
        // old ones stay at 30 through a second change.
        XCTAssertTrue(Repos.updateExercise(ctx, id: "baby", loadLb: 36))
        XCTAssertEqual(sets(ctx, "baby").map(\.weightLb), [30, 28, nil])
    }

    func testRenameOnlyDoesNotStampRows() throws {
        let ctx = try makeContext()
        try insertExercise(ctx, id: "baby", name: "Lifted Baby", loadLb: 30)
        try insertSet(ctx, exercise: "baby")
        XCTAssertTrue(Repos.updateExercise(ctx, id: "baby", name: "Lifted Mia"))
        XCTAssertNil(sets(ctx, "baby").first?.weightLb)
    }

    func testFailedSaveRollsBackBothTheStampAndTheNewLoad() throws {
        // The transaction guarantee, exercised at the boundary updateExercise uses.
        let ctx = try makeContext()
        try insertExercise(ctx, id: "baby", name: "Lifted Baby", loadLb: 30)
        try insertSet(ctx, exercise: "baby")
        let row = try XCTUnwrap(ctx.fetch(FetchDescriptor<WorkoutSetModel>()).first)
        let model = try XCTUnwrap(ctx.fetch(FetchDescriptor<ExerciseModel>()).first)
        let result = RepositoryWrite.perform(ctx, save: { throw Failure.diskFull }) {
            row.weightLb = 30
            model.loadLb = 34
        }
        XCTAssertFalse(result)
        XCTAssertNil(row.weightLb)
        XCTAssertEqual(model.loadLb, 30)
        // And a real edit afterwards still works.
        XCTAssertTrue(Repos.updateExercise(ctx, id: "baby", loadLb: 34))
        XCTAssertEqual(sets(ctx, "baby").first?.weightLb, 30)
    }

    // MARK: - Backfill

    func testBackfillStampsOnlyNilWeightRowsOfFixedLoadExercisesAndIsIdempotent() throws {
        let ctx = try makeContext()
        try insertExercise(ctx, id: "baby", name: "Lifted Baby", loadLb: 30)
        try insertExercise(ctx, id: "carry", name: "Carried Baby", loadLb: 30, kind: .duration)
        try insertExercise(ctx, id: "squat", name: "Squat", loadLb: nil)
        try insertExercise(ctx, id: "plank", name: "Plank", loadLb: nil, kind: .duration, isIsometric: true)
        try insertSet(ctx, exercise: "baby", weightLb: nil)
        try insertSet(ctx, exercise: "baby", weightLb: 28, offset: 60)
        try insertSet(ctx, exercise: "carry", reps: 12, weightLb: nil)
        try insertSet(ctx, exercise: "squat", weightLb: nil)
        try insertSet(ctx, exercise: "squat", weightLb: 135, offset: 60)
        try insertSet(ctx, exercise: "plank", reps: 1, weightLb: nil, holdSeconds: 45)

        XCTAssertTrue(Repos.backfillFixedLoadWeights(ctx))
        XCTAssertEqual(sets(ctx, "baby").map(\.weightLb), [30, 28])
        XCTAssertEqual(sets(ctx, "carry").map(\.weightLb), [30])
        XCTAssertEqual(sets(ctx, "squat").map(\.weightLb), [nil, 135])
        XCTAssertEqual(sets(ctx, "plank").map(\.weightLb), [nil])

        // Second run changes nothing.
        XCTAssertTrue(Repos.backfillFixedLoadWeights(ctx))
        XCTAssertFalse(ctx.hasChanges)
        XCTAssertEqual(sets(ctx, "baby").map(\.weightLb), [30, 28])
    }

    func testBackfillSkipsHoldRowsOfAFixedLoadExercise() throws {
        let ctx = try makeContext()
        try insertExercise(ctx, id: "hang", name: "Weighted Hang", loadLb: 20, kind: .duration, isIsometric: true)
        try insertSet(ctx, exercise: "hang", reps: 1, weightLb: nil, holdSeconds: 30)
        XCTAssertTrue(Repos.backfillFixedLoadWeights(ctx))
        XCTAssertNil(sets(ctx, "hang").first?.weightLb)
    }

    func testOnceFlagRunsTheBackfillOnlyOnceSoItCannotRestampAtAnEditedLoad() throws {
        let ctx = try makeContext()
        let defaults = isolatedDefaults()
        try insertExercise(ctx, id: "baby", name: "Lifted Baby", loadLb: 30)
        try insertSet(ctx, exercise: "baby", weightLb: nil)

        XCTAssertTrue(Repos.backfillFixedLoadWeightsOnce(ctx, defaults: defaults))
        XCTAssertEqual(sets(ctx, "baby").map(\.weightLb), [30])
        XCTAssertTrue(defaults.bool(forKey: Repos.fixedLoadBackfillKey))

        // The load is edited, then a stray unweighted row appears (e.g. an
        // older build's write). A relaunch must NOT stamp it at the new load.
        XCTAssertTrue(Repos.updateExercise(ctx, id: "baby", loadLb: 34))
        try insertSet(ctx, exercise: "baby", weightLb: nil, offset: 600)
        XCTAssertTrue(Repos.backfillFixedLoadWeightsOnce(ctx, defaults: defaults))
        XCTAssertEqual(sets(ctx, "baby").map(\.weightLb), [30, nil])
    }

    func testOnceFlagIsWrittenOnlyAfterTheBackfillSucceeds() throws {
        // Not covered: the failed-save branch (the backfill's save is not
        // injectable); the rollback it relies on is pinned in RepositoryWriteTests.
        let ctx = try makeContext()
        let defaults = isolatedDefaults()
        XCTAssertFalse(defaults.bool(forKey: Repos.fixedLoadBackfillKey))
        XCTAssertTrue(Repos.backfillFixedLoadWeightsOnce(ctx, defaults: defaults))
        XCTAssertTrue(defaults.bool(forKey: Repos.fixedLoadBackfillKey))
    }

    // MARK: - updateSet prices from the row's stamped weight

    func testUpdateSetKeepsTheStampedWeightWhenTheExerciseLoadHasMovedOn() throws {
        let ctx = try makeContext()
        let baby = try insertExercise(ctx, id: "baby", name: "Lifted Baby", loadLb: 30)
        let rowId = try insertSet(ctx, exercise: "baby", reps: 10, weightLb: 30)
        XCTAssertTrue(Repos.updateExercise(ctx, id: "baby", loadLb: 40))

        // An edit that passes no weight (or clears the field) keeps the stamp.
        XCTAssertTrue(Repos.updateSet(ctx, id: rowId, reps: 12, weightLb: nil, bodyWeightLb: 180))
        var row = try XCTUnwrap(sets(ctx, "baby").first)
        XCTAssertEqual(row.weightLb, 30)
        XCTAssertEqual(row.reps, 12)
        let at30 = Repos.setCaloriesEstimate(exercise: baby, reps: 12, holdSeconds: nil,
                                             bodyWeightLb: 180, loadLb: 30)
        XCTAssertEqual(try XCTUnwrap(row.caloriesEst), at30, accuracy: 0.0000001)

        // An explicit corrected weight wins.
        XCTAssertTrue(Repos.updateSet(ctx, id: rowId, reps: 12, weightLb: 31.5, bodyWeightLb: 180))
        row = try XCTUnwrap(sets(ctx, "baby").first)
        XCTAssertEqual(row.weightLb, 31.5)
    }

    func testUpdateSetStampsALegacyUnweightedFixedLoadRow() throws {
        let ctx = try makeContext()
        try insertExercise(ctx, id: "baby", name: "Lifted Baby", loadLb: 30)
        let rowId = try insertSet(ctx, exercise: "baby", reps: 10, weightLb: nil)
        XCTAssertTrue(Repos.updateSet(ctx, id: rowId, reps: 11, weightLb: nil, bodyWeightLb: 180))
        XCTAssertEqual(sets(ctx, "baby").first?.weightLb, 30)
    }

    func testUpdateSetLeavesPerSetWeightLiftsAndHoldsAlone() throws {
        let ctx = try makeContext()
        try insertExercise(ctx, id: "squat", name: "Squat", loadLb: nil)
        try insertExercise(ctx, id: "hang", name: "Weighted Hang", loadLb: 20, kind: .duration, isIsometric: true)
        let squatId = try insertSet(ctx, exercise: "squat", reps: 8, weightLb: 135)
        let holdId = try insertSet(ctx, exercise: "hang", reps: 1, weightLb: nil, holdSeconds: 30)

        XCTAssertTrue(Repos.updateSet(ctx, id: squatId, reps: 8, weightLb: 140, bodyWeightLb: 180))
        XCTAssertEqual(sets(ctx, "squat").first?.weightLb, 140)
        XCTAssertTrue(Repos.updateSet(ctx, id: squatId, reps: 8, weightLb: nil, bodyWeightLb: 180))
        XCTAssertNil(sets(ctx, "squat").first?.weightLb, "a per-set lift may still clear its weight")

        XCTAssertTrue(Repos.updateSet(ctx, id: holdId, reps: 1, weightLb: nil, holdSeconds: 45, bodyWeightLb: 180))
        let hold = try XCTUnwrap(sets(ctx, "hang").first)
        XCTAssertNil(hold.weightLb, "holds never get a weight")
        XCTAssertEqual(hold.holdSeconds, 45)
    }
}
