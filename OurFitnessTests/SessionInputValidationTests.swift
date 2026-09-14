import XCTest

final class SessionInputValidationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCatalogOverridesReceivedMETAndPreservesOfflineStart() throws {
        let activity = ActivityCatalog.all[0]
        let start = now.addingTimeInterval(-86400)
        let state = try XCTUnwrap(SessionInputValidation.start(
            activityId: activity.id, suppliedMET: 999, expectedMinutes: 30,
            startDate: start, profileId: UUID(), now: now))
        XCTAssertEqual(state.met, activity.met)
        XCTAssertEqual(state.activityName, activity.name)
        XCTAssertEqual(state.startDate, start)
    }

    func testRejectsUnknownActivityInvalidPlanAndFutureDate() {
        for (id, minutes, date) in [("unknown", 30, now),
                                    (ActivityCatalog.otherId, Int.max, now),
                                    (ActivityCatalog.otherId, 30, now.addingTimeInterval(301))] {
            XCTAssertNil(SessionInputValidation.start(activityId: id, suppliedMET: 5,
                expectedMinutes: minutes, startDate: date, profileId: UUID(), now: now))
        }
    }

    func testOtherSupportsBoundedCustomIntensity() {
        for met in [Double.nan, .infinity, -1, 13] {
            XCTAssertNil(SessionInputValidation.start(activityId: ActivityCatalog.otherId,
                suppliedMET: met, expectedMinutes: 30, startDate: now, profileId: UUID(), now: now))
        }
        XCTAssertEqual(SessionInputValidation.start(activityId: ActivityCatalog.otherId,
            suppliedMET: 6.5, expectedMinutes: 30, startDate: now, profileId: UUID(), now: now)?.met, 6.5)
    }
}
