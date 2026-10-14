import XCTest
import SwiftData

@MainActor
final class RepositoryWriteTests: XCTestCase {
    enum Failure: Error { case diskFull }

    func testCircuitCreationAndModeSwitchPreserveSeeds() throws {
        let schema = Schema([ProfileModel.self, ExerciseModel.self, ReminderGroupModel.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        let ctx = container.mainContext
        let profile = try XCTUnwrap(Repos.createProfile(ctx, name: "Fixture", mode: .circuit,
            sex: .female, heightIn: 65, weightLb: 150, age: 30, activity: .moderate))
        XCTAssertEqual(Repos.exercises(ctx, forProfile: profile.id).count, 3)
        XCTAssertEqual(Set(Repos.listReminderGroups(ctx, userId: profile.id).map(\.kind)), [.plants, .medication])
        XCTAssertNotNil(Repos.updateMode(ctx, profileId: profile.id, to: .build))
        XCTAssertNotNil(Repos.updateMode(ctx, profileId: profile.id, to: .circuit))
        XCTAssertEqual(Repos.exercises(ctx, forProfile: profile.id).count, 3)
        XCTAssertEqual(Repos.listReminderGroups(ctx, userId: profile.id).count, 2)
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
