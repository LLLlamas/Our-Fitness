import XCTest

// Pure Domain. `now` is pinned (mid-week, matching the CI rule) and threaded into
// every call so results never depend on the wall clock.
final class FreshnessTests: XCTestCase {

    // Wednesday 2026-05-27 12:00:00 UTC — the project's standard fixed `now`.
    private let now = Date(timeIntervalSince1970: 1_780_488_000)

    func testRecentSampleHasNoLabel() {
        let oneMinuteAgo = now.addingTimeInterval(-60)
        XCTAssertNil(Freshness.label(for: oneMinuteAgo, now: now))
    }

    func testAtBoundaryStillRecent() {
        let exactly2Min = now.addingTimeInterval(-Freshness.recentWindow)
        // Strictly greater than the window is required, so the boundary is "recent".
        XCTAssertNil(Freshness.label(for: exactly2Min, now: now))
    }

    func testStaleSampleGetsAsOfLabel() {
        let tenMinutesAgo = now.addingTimeInterval(-600)
        let label = Freshness.label(for: tenMinutesAgo, now: now)
        XCTAssertNotNil(label)
        XCTAssertTrue(label?.hasPrefix("as of ") ?? false)
    }

    func testFutureSampleHasNoLabel() {
        let future = now.addingTimeInterval(300)
        XCTAssertNil(Freshness.label(for: future, now: now))
    }

    func testCustomStaleWindow() {
        let thirtySecAgo = now.addingTimeInterval(-30)
        XCTAssertNil(Freshness.label(for: thirtySecAgo, now: now, staleAfter: 60))
        XCTAssertNotNil(Freshness.label(for: thirtySecAgo, now: now, staleAfter: 10))
    }
}
