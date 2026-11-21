import XCTest
import SwiftData

/// The Train row's inline −1: `Repos.removeOneFromToday` takes one rep (or minute)
/// off TODAY's newest set — re-priced through `updateSet`, or deleted when it is a
/// single rep — and never touches an earlier day.
@MainActor
final class RemoveOneTodayTests: XCTestCase {
    private let user = UUID()
    // 14:00 UTC, so "an hour ago" and "a day ago" fall on the right local days in any zone.
    private let now = Date(timeIntervalSince1970: 1_800_000_000 + 6 * 3600)

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

    private func insertExercise(_ ctx: ModelContext, id: String, category: ExerciseCategory = .bodyweight,
                                loadLb: Double? = nil, kind: ExerciseKind = .reps) throws {
        ctx.insert(ExerciseModel(snapshot: ExerciseDTO(
            id: id, name: id, category: category, muscleGroups: [], equipment: [],
            loadLb: loadLb, kind: kind)))
        try ctx.save()
    }

    @discardableResult
    private func insertSet(_ ctx: ModelContext, _ exercise: String, reps: Int, weightLb: Double? = nil,
                           secondsAgo: TimeInterval, calories: Double = 99) throws -> UUID {
        let dto = WorkoutSetDTO(userId: user, exerciseId: exercise, weightLb: weightLb, reps: reps,
                                timestamp: now.addingTimeInterval(-secondsAgo), caloriesEst: calories)
        ctx.insert(WorkoutSetModel(snapshot: dto))
        try ctx.save()
        return dto.id
    }

    private func sets(_ ctx: ModelContext, _ exercise: String) -> [WorkoutSetDTO] {
        Repos.setHistory(ctx, userId: user, exerciseId: exercise, limit: 1000)
            .sorted { $0.timestamp < $1.timestamp }
    }

    func test_multiRepSet_losesOneRepAndIsRepriced() throws {
        let ctx = try makeContext()
        try insertExercise(ctx, id: "pushups")
        let id = try insertSet(ctx, "pushups", reps: 10, secondsAgo: 3600)

        XCTAssertTrue(Repos.removeOneFromToday(ctx, userId: user, exerciseId: "pushups",
                                               bodyWeightLb: 170, now: now))
        let row = try XCTUnwrap(sets(ctx, "pushups").first { $0.id == id })
        XCTAssertEqual(row.reps, 9)
        let expected = Repos.setCaloriesEstimate(
            exercise: ExerciseDTO(id: "pushups", name: "pushups", category: .bodyweight,
                                  muscleGroups: [], equipment: []),
            reps: 9, holdSeconds: nil, bodyWeightLb: 170)
        XCTAssertEqual(try XCTUnwrap(row.caloriesEst), expected, accuracy: 1e-9)
    }

    func test_singleRepSet_isDeleted() throws {
        let ctx = try makeContext()
        try insertExercise(ctx, id: "pushups")
        try insertSet(ctx, "pushups", reps: 1, secondsAgo: 3600)

        XCTAssertTrue(Repos.removeOneFromToday(ctx, userId: user, exerciseId: "pushups",
                                               bodyWeightLb: 170, now: now))
        XCTAssertTrue(sets(ctx, "pushups").isEmpty)
    }

    func test_takesFromTheNewestTodaySetOnly() throws {
        let ctx = try makeContext()
        try insertExercise(ctx, id: "pushups")
        let older = try insertSet(ctx, "pushups", reps: 10, secondsAgo: 7200)
        let newer = try insertSet(ctx, "pushups", reps: 5, secondsAgo: 600)

        XCTAssertTrue(Repos.removeOneFromToday(ctx, userId: user, exerciseId: "pushups",
                                               bodyWeightLb: 170, now: now))
        let rows = sets(ctx, "pushups")
        XCTAssertEqual(rows.first { $0.id == older }?.reps, 10)
        XCTAssertEqual(rows.first { $0.id == newer }?.reps, 4)
    }

    func test_nothingToday_isNoOpAndLeavesYesterdayAlone() throws {
        let ctx = try makeContext()
        try insertExercise(ctx, id: "pushups")
        let yesterday = try insertSet(ctx, "pushups", reps: 30, secondsAgo: 86_400, calories: 42)

        XCTAssertFalse(Repos.removeOneFromToday(ctx, userId: user, exerciseId: "pushups",
                                                bodyWeightLb: 170, now: now))
        let row = try XCTUnwrap(sets(ctx, "pushups").first { $0.id == yesterday })
        XCTAssertEqual(row.reps, 30)
        XCTAssertEqual(row.caloriesEst, 42)
    }

    func test_weightedSetKeepsItsWeight() throws {
        let ctx = try makeContext()
        try insertExercise(ctx, id: "bench", category: .compound)
        let id = try insertSet(ctx, "bench", reps: 8, weightLb: 135, secondsAgo: 600)

        XCTAssertTrue(Repos.removeOneFromToday(ctx, userId: user, exerciseId: "bench",
                                               bodyWeightLb: 170, now: now))
        let row = try XCTUnwrap(sets(ctx, "bench").first { $0.id == id })
        XCTAssertEqual(row.reps, 7)
        XCTAssertEqual(row.weightLb, 135)
    }

    func test_otherExercisesAreUntouched() throws {
        let ctx = try makeContext()
        try insertExercise(ctx, id: "pushups")
        try insertExercise(ctx, id: "squats")
        let squat = try insertSet(ctx, "squats", reps: 12, secondsAgo: 60)
        try insertSet(ctx, "pushups", reps: 10, secondsAgo: 3600)

        XCTAssertTrue(Repos.removeOneFromToday(ctx, userId: user, exerciseId: "pushups",
                                               bodyWeightLb: 170, now: now))
        XCTAssertEqual(sets(ctx, "squats").first { $0.id == squat }?.reps, 12)
    }

    func test_fixedLoadSet_keepsItsStampedLoadAfterTheExerciseLoadChanges() throws {
        let ctx = try makeContext()
        try insertExercise(ctx, id: "baby", loadLb: 20)
        let id = try insertSet(ctx, "baby", reps: 5, weightLb: 20, secondsAgo: 600)
        XCTAssertTrue(Repos.updateExercise(ctx, id: "baby", loadLb: 30))

        XCTAssertTrue(Repos.removeOneFromToday(ctx, userId: user, exerciseId: "baby",
                                               bodyWeightLb: 170, now: now))
        let row = try XCTUnwrap(sets(ctx, "baby").first { $0.id == id })
        XCTAssertEqual(row.reps, 4)
        // The row stays at the load it was done at, never the exercise's new 30 lb.
        XCTAssertEqual(row.weightLb, 20)
        func baby(load: Double) -> ExerciseDTO {
            ExerciseDTO(id: "baby", name: "baby", category: .bodyweight, muscleGroups: [],
                        equipment: [], loadLb: load)
        }
        let at20 = Repos.setCaloriesEstimate(exercise: baby(load: 30), reps: 4, holdSeconds: nil,
                                             bodyWeightLb: 170, loadLb: 20)
        XCTAssertEqual(try XCTUnwrap(row.caloriesEst), at20, accuracy: 1e-9)
        // Honest caveat: the flat estimators read only that a load exists, so a
        // 30 lb pricing is numerically identical today; the stamped weight above
        // is what proves the row was not re-read at 30 lb.
        let at30 = Repos.setCaloriesEstimate(exercise: baby(load: 30), reps: 4, holdSeconds: nil,
                                             bodyWeightLb: 170, loadLb: 30)
        XCTAssertEqual(at20, at30, accuracy: 1e-9)
    }

    func test_durationSet_losesOneMinute() throws {
        let ctx = try makeContext()
        try insertExercise(ctx, id: "carry", kind: .duration)
        let id = try insertSet(ctx, "carry", reps: 5, secondsAgo: 600)

        XCTAssertTrue(Repos.removeOneFromToday(ctx, userId: user, exerciseId: "carry",
                                               bodyWeightLb: 170, now: now))
        let row = try XCTUnwrap(sets(ctx, "carry").first { $0.id == id })
        XCTAssertEqual(row.reps, 4)
        let expected = Repos.setCaloriesEstimate(
            exercise: ExerciseDTO(id: "carry", name: "carry", category: .bodyweight,
                                  muscleGroups: [], equipment: [], kind: .duration),
            reps: 4, holdSeconds: nil, bodyWeightLb: 170)
        XCTAssertEqual(try XCTUnwrap(row.caloriesEst), expected, accuracy: 1e-9)
    }

    func test_twoSetsWithTheSameTimestamp_totalDropsByExactlyOne() throws {
        let ctx = try makeContext()
        try insertExercise(ctx, id: "pushups")
        try insertSet(ctx, "pushups", reps: 3, secondsAgo: 600)
        try insertSet(ctx, "pushups", reps: 4, secondsAgo: 600)
        let before = sets(ctx, "pushups").map(\.reps).reduce(0, +)

        XCTAssertTrue(Repos.removeOneFromToday(ctx, userId: user, exerciseId: "pushups",
                                               bodyWeightLb: 170, now: now))
        XCTAssertEqual(sets(ctx, "pushups").map(\.reps).reduce(0, +), before - 1)
    }
}

