import XCTest
import SwiftData

// SchemaV8: the optional "Felt dizzy" columns on ActivitySessionModel and
// PilatesSessionModel (cardio plan §10 Q2).
//
// Limit: every VersionedSchema here lists the SAME live model classes (no frozen
// V7 copies exist in this codebase), so a test cannot rebuild a store with the
// exact V7 column layout. The on-disk test below proves a store written without
// the flag reopens under `AppSchema.current` with nil = not flagged; the real
// V7-hash → V8-hash lightweight migration is only exercised by installing over
// a V7 build.
@MainActor
final class DizzyFlagPersistenceTests: XCTestCase {

    private func container() throws -> ModelContainer {
        let schema = Schema([ActivitySessionModel.self, PilatesSessionModel.self])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
    }

    private let anchor = Date(timeIntervalSince1970: 1_800_000_000)

    func testCurrentSchemaIsV8WithTheSameEntitiesAsV7() {
        XCTAssertEqual(AppSchema.current.versionIdentifier, Schema.Version(8, 0, 0))
        let names: ([any PersistentModel.Type]) -> [String] = { $0.map { String(describing: $0) } }
        XCTAssertEqual(names(SchemaV8.models), names(SchemaV7.models))
    }

    func testStoreWrittenWithoutTheFlagReopensUnderCurrentSchemaAsNotFlagged() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dizzy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("OurFitness.store")
        let profile = UUID()
        do {
            let v7 = try ModelContainer(for: Schema(versionedSchema: SchemaV7.self),
                                        configurations: [ModelConfiguration(url: url)])
            XCTAssertTrue(Repos.logActivitySession(v7.mainContext, ActivitySessionDTO(
                profileId: profile, date: anchor, activityId: "activity-walking", activityName: "Walking",
                met: 3.5, durationMinutes: 30, expectedMinutes: 30)))
        }
        let v8 = try ModelContainer(for: Schema(versionedSchema: AppSchema.current),
                                    configurations: [ModelConfiguration(url: url)])
        let model = try XCTUnwrap(v8.mainContext.fetch(FetchDescriptor<ActivitySessionModel>()).first)
        XCTAssertNil(model.feltDizzy)
        XCTAssertNil(model.dizzySeverityRaw)
        XCTAssertNil(model.dizzyAvgHeartRateBpm)
        XCTAssertNil(model.dizzyPeakHeartRateBpm)
        XCTAssertNil(model.snapshot.dizziness)
        XCTAssertEqual(model.snapshot.profileId, profile)
    }

    func testLoggedAfterTheFactRoundTripsForBothKindsWithoutHeartRate() throws {
        let container = try container()
        let ctx = container.mainContext
        let profile = UUID()
        let flag = DizzinessReport(severity: .mild)
        XCTAssertTrue(Repos.logActivitySession(ctx, ActivitySessionDTO(
            profileId: profile, date: anchor, activityId: "activity-walking", activityName: "Walking",
            met: 3.5, durationMinutes: 30, expectedMinutes: 30, dizziness: flag)))
        XCTAssertTrue(Repos.logPilatesSession(ctx, PilatesSessionDTO(
            profileId: profile, date: anchor, durationMinutes: 40, focusAreas: [], dizziness: DizzinessReport())))
        let activity = try XCTUnwrap(ctx.fetch(FetchDescriptor<ActivitySessionModel>()).first)
        XCTAssertEqual(activity.snapshot.dizziness, flag)
        XCTAssertEqual(activity.feltDizzy, true)
        XCTAssertEqual(activity.dizzySeverityRaw, "mild")
        XCTAssertNil(activity.dizzyAvgHeartRateBpm)
        let pilates = try XCTUnwrap(ctx.fetch(FetchDescriptor<PilatesSessionModel>()).first)
        XCTAssertEqual(pilates.snapshot.dizziness, DizzinessReport())
        XCTAssertNil(pilates.dizzySeverityRaw)
    }

    func testEditsKeepTheFlag() throws {
        let container = try container()
        let ctx = container.mainContext
        let profile = UUID()
        let flag = DizzinessReport(severity: .moderate, averageHeartRateBpm: 120, peakHeartRateBpm: 140)
        let activity = ActivitySessionDTO(profileId: profile, date: anchor, activityId: "activity-walking",
                                          activityName: "Walking", met: 3.5, durationMinutes: 30,
                                          expectedMinutes: 30, dizziness: flag)
        var pilates = PilatesSessionDTO(profileId: profile, date: anchor, durationMinutes: 40,
                                        focusAreas: [], dizziness: flag)
        XCTAssertTrue(Repos.logActivitySession(ctx, activity))
        XCTAssertTrue(Repos.logPilatesSession(ctx, pilates))
        XCTAssertTrue(Repos.updateActivitySession(ctx, id: activity.id, durationMinutes: 45, bodyWeightLb: 150))
        pilates.durationMinutes = 50
        XCTAssertTrue(Repos.updatePilatesSession(ctx, pilates))
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<ActivitySessionModel>()).first?.snapshot.dizziness, flag)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<PilatesSessionModel>()).first?.snapshot.dizziness, flag)
    }

    func testLiveCompletionSavesTheFlagAndHeartRateAttachesForBothKinds() throws {
        let container = try container()
        let ctx = container.mainContext
        let profile = UUID()
        for activity in [ActivityCatalog.all[0], ActivityCatalog.activity(id: ActivityCatalog.pilatesId)!] {
            let state = LiveSessionState(startDate: anchor, activityId: activity.id,
                                         activityName: activity.name, met: activity.met,
                                         expectedMinutes: 30, profileId: profile)
            XCTAssertTrue(Repos.completeLiveSession(ctx, state: state, elapsedSeconds: 600, bodyWeightLb: 150,
                                                    dizziness: DizzinessReport(severity: .severe)))
            XCTAssertTrue(Repos.recordDizzyHeartRate(ctx, state: state, averageBpm: 118.4, peakBpm: 149))
        }
        let expected = DizzinessReport(severity: .severe, averageHeartRateBpm: 118.4, peakHeartRateBpm: 149)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<ActivitySessionModel>()).first?.snapshot.dizziness, expected)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<PilatesSessionModel>()).first?.snapshot.dizziness, expected)
    }

    func testHeartRateNeverAttachesToAnUnflaggedOrMissingSession() throws {
        let container = try container()
        let ctx = container.mainContext
        let activity = ActivityCatalog.all[0]
        let state = LiveSessionState(startDate: anchor, activityId: activity.id, activityName: activity.name,
                                     met: activity.met, expectedMinutes: 30, profileId: UUID())
        XCTAssertFalse(Repos.recordDizzyHeartRate(ctx, state: state, averageBpm: 120, peakBpm: 140))
        XCTAssertTrue(Repos.completeLiveSession(ctx, state: state, elapsedSeconds: 600, bodyWeightLb: 150))
        XCTAssertFalse(Repos.recordDizzyHeartRate(ctx, state: state, averageBpm: 120, peakBpm: 140))
        let model = try XCTUnwrap(ctx.fetch(FetchDescriptor<ActivitySessionModel>()).first)
        XCTAssertNil(model.snapshot.dizziness)
        XCTAssertNil(model.dizzyAvgHeartRateBpm)
    }
}
