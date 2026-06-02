import XCTest

final class ActivityCatalogTests: XCTestCase {

    // MARK: - Calorie math (deterministic MET × kg × hours)

    func test_activity_exact_kcal() {
        // 60 min basketball game (MET 8.0); 180 lb × 0.453592 = 81.64656 kg
        // kcal = 8.0 × 81.64656 × (60/60) = 653.17248
        let kcal = CalorieEstimator.caloriesForActivity(
            met: 8.0, minutes: 60, bodyWeightLb: 180
        )
        XCTAssertEqual(kcal, 653.17248, accuracy: 0.01)
    }

    func test_activity_half_hour_pilates_matches_pilates_helper() {
        // The activity helper with the catalog's pilates MET (3.0) must agree with
        // the dedicated pilates helper for the same inputs.
        let viaActivity = CalorieEstimator.caloriesForActivity(met: 3.0, minutes: 30, bodyWeightLb: 150)
        let viaPilates = CalorieEstimator.caloriesForPilates(minutes: 30, bodyWeightLb: 150)
        XCTAssertEqual(viaActivity, viaPilates, accuracy: 0.0001)
    }

    func test_activity_scales_with_duration_and_weight() {
        let short = CalorieEstimator.caloriesForActivity(met: 7.0, minutes: 20, bodyWeightLb: 150)
        let long = CalorieEstimator.caloriesForActivity(met: 7.0, minutes: 40, bodyWeightLb: 150)
        let heavy = CalorieEstimator.caloriesForActivity(met: 7.0, minutes: 20, bodyWeightLb: 200)
        XCTAssertEqual(long, short * 2, accuracy: 0.01)        // double the time → double the burn
        XCTAssertGreaterThan(heavy, short)                     // heavier body → more burn
    }

    // MARK: - Catalog invariants

    func test_catalog_has_unique_ids() {
        let ids = ActivityCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Activity ids must be unique")
    }

    func test_catalog_mets_are_positive() {
        for a in ActivityCatalog.all {
            XCTAssertGreaterThan(a.met, 0, "\(a.name) must have a positive MET")
        }
    }

    func test_catalog_includes_other_with_lookup() {
        let other = ActivityCatalog.activity(id: ActivityCatalog.otherId)
        XCTAssertNotNil(other)
        XCTAssertEqual(other?.met, ActivityCatalog.otherDefaultMET)
    }

    func test_walking_id_matches_dailyburn_exclusion() {
        // DailyBurn / MoveCard exclude the walking activity from training burn by
        // its literal id to avoid double-counting with steps. If this id ever
        // changes, those exclusions must change too — this pins the contract.
        XCTAssertNotNil(ActivityCatalog.activity(id: "activity-walking"))
    }

    func test_known_named_mets() {
        // Spot-check a few against the spec so MET drift breaks loudly.
        XCTAssertEqual(ActivityCatalog.activity(id: "activity-soccer")?.met, 7.0)
        XCTAssertEqual(ActivityCatalog.activity(id: "activity-tennis")?.met, 7.3)
        XCTAssertEqual(ActivityCatalog.activity(id: "activity-jump-rope")?.met, 11.8)
        XCTAssertEqual(ActivityCatalog.activity(id: "activity-yoga")?.met, 2.8)
    }

    // MARK: - LiveSessionState elapsed (timestamp-anchored, injectable now)

    func test_live_session_elapsed_is_derived_from_start() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let state = LiveSessionState(
            startDate: start, activityId: "activity-soccer", activityName: "Soccer",
            met: 7.0, expectedMinutes: 30, profileId: UUID()
        )
        let now = start.addingTimeInterval(125) // 2m 5s later
        XCTAssertEqual(state.elapsedSeconds(now: now), 125)
    }

    func test_live_session_elapsed_never_negative() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let state = LiveSessionState(
            startDate: start, activityId: "activity-soccer", activityName: "Soccer",
            met: 7.0, expectedMinutes: 30, profileId: UUID()
        )
        let before = start.addingTimeInterval(-60) // clock skew / earlier "now"
        XCTAssertEqual(state.elapsedSeconds(now: before), 0)
    }
}
