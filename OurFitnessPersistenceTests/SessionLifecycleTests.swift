import XCTest
import SwiftData

@MainActor
final class SessionLifecycleTests: XCTestCase {
    func testFailedFinishPreservesAnchorAndRepeatedFinishIsStale() throws {
        let schema = Schema([ActivitySessionModel.self, PilatesSessionModel.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        let ctx = container.mainContext
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let state = LiveSessionState(startDate: start, activityId: ActivityCatalog.all[0].id,
                                     activityName: "Basketball", met: 8, expectedMinutes: 30, profileId: UUID())
        LiveSessionStore.save(state)
        defer { LiveSessionStore.clear() }
        let failed = LiveSessionCompletionService.finish(
            ctx, profileId: state.profileId, startDate: start, elapsedSeconds: 600, bodyWeightLb: 150,
            now: start.addingTimeInterval(600), save: { throw RepositoryWriteTests.Failure.diskFull }, endPresentation: {})
        if case .failed = failed {} else { XCTFail("Expected failure") }
        XCTAssertEqual(LiveSessionStore.load(), state)
        let saved = LiveSessionCompletionService.finish(
            ctx, profileId: state.profileId, startDate: start, elapsedSeconds: 600,
            bodyWeightLb: 150, now: start.addingTimeInterval(600), endPresentation: {})
        if case .saved = saved {} else { XCTFail("Expected save") }
        XCTAssertNil(LiveSessionStore.load())
        let repeated = LiveSessionCompletionService.finish(
            ctx, profileId: state.profileId, startDate: start, elapsedSeconds: 700,
            bodyWeightLb: 150, now: start.addingTimeInterval(700), endPresentation: {})
        if case .stale = repeated {} else { XCTFail("Expected stale completion") }
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<ActivitySessionModel>()), 1)
    }

    func testOldRunnerCannotClearReplacement() throws {
        let schema = Schema([ActivitySessionModel.self, PilatesSessionModel.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let replacement = LiveSessionState(startDate: start.addingTimeInterval(60),
                                           activityId: "activity-yoga", activityName: "Yoga",
                                           met: 2.8, expectedMinutes: 30, profileId: UUID())
        LiveSessionStore.save(replacement)
        defer { LiveSessionStore.clear() }
        let outcome = LiveSessionCompletionService.finish(
            container.mainContext, profileId: replacement.profileId, startDate: start,
            elapsedSeconds: 120, bodyWeightLb: 150, now: start.addingTimeInterval(120), endPresentation: {})
        if case .stale = outcome {} else { XCTFail("Expected stale runner") }
        XCTAssertEqual(LiveSessionStore.load(), replacement)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ActivitySessionModel>()), 0)
    }
}
