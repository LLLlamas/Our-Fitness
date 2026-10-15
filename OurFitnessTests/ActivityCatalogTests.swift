import XCTest

final class ActivityCatalogTests: XCTestCase {

    // MARK: - Calorie math (deterministic MET × kg × hours)

    func test_activity_exact_kcal() {
        // 60 min basketball game (MET 8.0 → net 7.0); 180 lb × 0.45359237 = 81.6466266 kg
        // kcal = (8.0 − 1) × 81.6466266 × (60/60) = 571.5263862
        let kcal = CalorieEstimator.caloriesForActivity(
            met: 8.0, minutes: 60, bodyWeightLb: 180
        )
        XCTAssertEqual(kcal, 571.5263862, accuracy: 0.0001)
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
        // DailyBurn / MoveCard exclude the walking activity from training burn to
        // avoid double-counting with steps, and reach for it via
        // `ActivityCatalog.walkingId`. Pin both the constant's spelling and the
        // fact that it still resolves to a real catalog entry.
        XCTAssertEqual(ActivityCatalog.walkingId, "activity-walking")
        XCTAssertNotNil(ActivityCatalog.activity(id: ActivityCatalog.walkingId))
    }

    /// `tracksDistance` is a UI/semantics flag, NOT the step-overlap signal:
    /// cycling tracks distance but registers no steps, so DailyBurn must keep
    /// counting it. Pinned so nobody "simplifies" the exclusion to this flag.
    func test_tracksDistance_is_not_the_step_overlap_signal() {
        let cycling = ActivityCatalog.activity(id: "activity-cycling")
        XCTAssertEqual(cycling?.tracksDistance, true)
        XCTAssertFalse(DailyBurn.stepOverlappingActivityIds.contains("activity-cycling"))
    }

    func test_known_named_mets() {
        // Spot-check a few against the spec so MET drift breaks loudly.
        XCTAssertEqual(ActivityCatalog.activity(id: "activity-soccer")?.met, 7.0)
        XCTAssertEqual(ActivityCatalog.activity(id: "activity-tennis")?.met, 7.3)
        XCTAssertEqual(ActivityCatalog.activity(id: "activity-jump-rope")?.met, 11.8)
        XCTAssertEqual(ActivityCatalog.activity(id: ActivityCatalog.yogaId)?.met, 2.8)
        // Ainsworth 2011, 02101 "stretching, mild".
        XCTAssertEqual(ActivityCatalog.activity(id: ActivityCatalog.stretchingId)?.met, 2.3)
    }

    /// Yoga and Stretching back the optional Train sections, which query sessions
    /// by these ids — and existing yoga rows on disk carry "activity-yoga".
    func test_section_ids_are_stable_and_resolve() {
        XCTAssertEqual(ActivityCatalog.yogaId, "activity-yoga")
        XCTAssertEqual(ActivityCatalog.stretchingId, "activity-stretching")
        XCTAssertNotNil(ActivityCatalog.activity(id: ActivityCatalog.yogaId))
        XCTAssertNotNil(ActivityCatalog.activity(id: ActivityCatalog.stretchingId))
    }

    /// Yoga and stretching produce no steps, so the day's burn must keep them.
    func test_yoga_and_stretching_are_not_step_overlapping() {
        XCTAssertFalse(DailyBurn.stepOverlappingActivityIds.contains(ActivityCatalog.yogaId))
        XCTAssertFalse(DailyBurn.stepOverlappingActivityIds.contains(ActivityCatalog.stretchingId))
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
