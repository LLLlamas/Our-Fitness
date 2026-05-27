import XCTest

final class HealthAccessTests: XCTestCase {

    func test_shouldPromptConnect_whenNotGranted() {
        XCTAssertTrue(HealthAccess.shouldPromptConnect(healthGranted: false))
    }

    func test_shouldPromptConnect_whenGranted() {
        XCTAssertFalse(HealthAccess.shouldPromptConnect(healthGranted: true))
    }

    func test_statusLabel_reflectsGrant() {
        XCTAssertEqual(HealthAccess.statusLabel(healthGranted: true), "Connected to Apple Health")
        XCTAssertTrue(HealthAccess.statusLabel(healthGranted: false).contains("Connect"))
    }

    func test_shouldBackfill_onlyWhenGrantedAndNotYetDone() {
        XCTAssertTrue(HealthAccess.shouldBackfill(healthGranted: true, hasBackfilled: false))
        XCTAssertFalse(HealthAccess.shouldBackfill(healthGranted: true, hasBackfilled: true))
        XCTAssertFalse(HealthAccess.shouldBackfill(healthGranted: false, hasBackfilled: false))
        XCTAssertFalse(HealthAccess.shouldBackfill(healthGranted: false, hasBackfilled: true))
    }
}
