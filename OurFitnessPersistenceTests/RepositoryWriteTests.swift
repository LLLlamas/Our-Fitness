import XCTest
import SwiftData

@MainActor
final class RepositoryWriteTests: XCTestCase {
    enum Failure: Error { case diskFull }

    private func profileContainer() throws -> ModelContainer {
        let schema = Schema([ProfileModel.self, ExerciseModel.self, ReminderGroupModel.self])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
    }

    func testEveryGoalSeedsStarterMovementsAndGoalSwitchPreservesThem() throws {
        for goal in FitnessGoal.allCases {
            let container = try profileContainer()
            let ctx = container.mainContext
            let profile = try XCTUnwrap(Repos.createProfile(ctx, name: "Fixture", fitnessGoal: goal,
                sex: .female, heightIn: 65, weightLb: 150, age: 30, activity: .moderate))
            XCTAssertEqual(Set(Repos.exercises(ctx, forProfile: profile.id).map(\.name)),
                           ["Lifted Baby", "Lifted Stroller", "Carried Baby"], "\(goal)")
            XCTAssertEqual(Set(Repos.listReminderGroups(ctx, userId: profile.id).map(\.kind)), [.plants, .medication])
            let other: FitnessGoal = goal == .gain ? .lose : .gain
            XCTAssertNotNil(Repos.updateGoal(ctx, profileId: profile.id, to: other))
            XCTAssertNotNil(Repos.updateGoal(ctx, profileId: profile.id, to: goal))
            XCTAssertEqual(Repos.exercises(ctx, forProfile: profile.id).count, 3)
            XCTAssertEqual(Repos.listReminderGroups(ctx, userId: profile.id).count, 2)
        }
    }

    func testGoalSwitchNeverSeeds() throws {
        let container = try profileContainer()
        let ctx = container.mainContext
        let profile = try XCTUnwrap(Repos.createProfile(ctx, name: "Fixture", fitnessGoal: .gain,
            sex: .male, heightIn: 70, weightLb: 180, age: 35, activity: .light))
        for ex in Repos.exercises(ctx, forProfile: profile.id) {
            XCTAssertTrue(Repos.deleteExercise(ctx, id: ex.id))
        }
        let switched = try XCTUnwrap(Repos.updateGoal(ctx, profileId: profile.id, to: .lose))
        XCTAssertEqual(switched.fitnessGoal, .lose)
        XCTAssertEqual(switched.computedTargets,
                       Targets.compute(fitnessGoal: .lose, vitals: profile.vitals))
        XCTAssertTrue(Repos.exercises(ctx, forProfile: profile.id).isEmpty)
    }

    func testHeartHealthBackfillRecomputesOnlyStaleTargetsAndIsIdempotent() throws {
        let container = try profileContainer()
        let ctx = container.mainContext
        let vitals = Targets.ProfileVitals(sex: .male, weightLb: 180, heightIn: 70, age: 35, activity: .moderate)
        // A profile stored under the old rules: gain-goal targets with no micros.
        var legacy = Targets.compute(fitnessGoal: .gain, vitals: vitals)
        legacy.sodiumMgMax = nil; legacy.addedSugarGMax = nil
        legacy.saturatedFatGMax = nil; legacy.fiberGMin = nil
        let stale = ProfileDTO(name: "Old", fitnessGoal: .gain, sex: .male, heightIn: 70,
                               weightLb: 180, age: 35, activity: .moderate, computedTargets: legacy)
        let current = try XCTUnwrap(Repos.createProfile(ctx, name: "New", fitnessGoal: .lose,
            sex: .female, heightIn: 65, weightLb: 150, age: 30, activity: .moderate))
        ctx.insert(ProfileModel(snapshot: stale))
        try ctx.save()
        let currentStamp = try XCTUnwrap(Repos.listProfiles(ctx).first { $0.id == current.id }).updatedAt

        XCTAssertTrue(Repos.backfillHeartHealthTargets(ctx))
        let fixed = try XCTUnwrap(Repos.listProfiles(ctx).first { $0.id == stale.id })
        XCTAssertEqual(fixed.computedTargets, Targets.compute(fitnessGoal: .gain, vitals: vitals))
        XCTAssertEqual(fixed.computedTargets.fiberGMin, 35)
        XCTAssertEqual(fixed.computedTargets.sodiumMgMax, 1_500)
        // Up-to-date profile untouched.
        XCTAssertEqual(try XCTUnwrap(Repos.listProfiles(ctx).first { $0.id == current.id }).updatedAt, currentStamp)

        // Second run is a no-op.
        let fixedStamp = fixed.updatedAt
        XCTAssertTrue(Repos.backfillHeartHealthTargets(ctx))
        XCTAssertFalse(ctx.hasChanges)
        XCTAssertEqual(try XCTUnwrap(Repos.listProfiles(ctx).first { $0.id == stale.id }).updatedAt, fixedStamp)
    }

    private func container() throws -> ModelContainer {
        let schema = Schema([WaterEntryModel.self, ActivitySessionModel.self, PilatesSessionModel.self])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
    }

    func testFailedCommitRollsBackInsertAndAllowsRetry() throws {
        let container = try container()
        let ctx = container.mainContext
        let entry = WaterEntryDTO(userId: UUID(), date: "2026-09-13", flOz: 8,
                                  timestamp: Date(timeIntervalSince1970: 1_800_000_000))
        let result = RepositoryWrite.perform(ctx, save: { throw Failure.diskFull }) {
            ctx.insert(WaterEntryModel(snapshot: entry))
        }
        XCTAssertFalse(result)
        XCTAssertFalse(ctx.hasChanges)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<WaterEntryModel>()), 0)
        XCTAssertTrue(Repos.addWater(ctx, entry))
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<WaterEntryModel>()), 1)
    }

    func testFailedCommitRestoresExistingValue() throws {
        let container = try container()
        let ctx = container.mainContext
        let model = WaterEntryModel(snapshot: WaterEntryDTO(userId: UUID(), date: "2026-09-13", flOz: 8))
        ctx.insert(model)
        try ctx.save()
        XCTAssertFalse(RepositoryWrite.perform(ctx, save: { throw Failure.diskFull }) { model.flOz = 32 })
        XCTAssertEqual(model.flOz, 8)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<WaterEntryModel>()).first?.flOz, 8)
    }

    func testSessionCompletionIsDurablyIdempotentForBothKinds() throws {
        let container = try container()
        let ctx = container.mainContext
        let profile = UUID()
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)
        for activity in [ActivityCatalog.all[0], ActivityCatalog.activity(id: ActivityCatalog.pilatesId)!] {
            let state = LiveSessionState(startDate: anchor, activityId: activity.id,
                                         activityName: activity.name, met: activity.met,
                                         expectedMinutes: 30, profileId: profile)
            XCTAssertTrue(Repos.completeLiveSession(ctx, state: state, elapsedSeconds: 600, bodyWeightLb: 150))
            // Represents either a second device or relaunch after save-before-clear.
            XCTAssertTrue(Repos.completeLiveSession(ctx, state: state, elapsedSeconds: 900, bodyWeightLb: 150))
        }
        let activity = try XCTUnwrap(ctx.fetch(FetchDescriptor<ActivitySessionModel>()).first)
        XCTAssertEqual(activity.durationMinutes, 10)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<ActivitySessionModel>()), 1)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<PilatesSessionModel>()), 1)
    }

    func testSessionSaveFailureCanRetryWithoutDuplicate() throws {
        let container = try container()
        let ctx = container.mainContext
        let activity = ActivityCatalog.all[0]
        let state = LiveSessionState(startDate: Date(timeIntervalSince1970: 1_800_000_000),
                                     activityId: activity.id, activityName: activity.name,
                                     met: activity.met, expectedMinutes: 30, profileId: UUID())
        XCTAssertFalse(Repos.completeLiveSession(ctx, state: state, elapsedSeconds: 600,
                                                 bodyWeightLb: 150, save: { throw Failure.diskFull }))
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<ActivitySessionModel>()), 0)
        XCTAssertTrue(Repos.completeLiveSession(ctx, state: state, elapsedSeconds: 600, bodyWeightLb: 150))
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<ActivitySessionModel>()), 1)
    }
}
