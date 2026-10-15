import XCTest

final class TrainSectionsTests: XCTestCase {

    // Wednesday mid-week, UTC calendar — never bare Date() in weekly tests.
    private let now = ISO8601DateFormatter().date(from: "2026-05-27T12:00:00Z")!
    private var utc: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }
    private func daysAgo(_ n: Int) -> Date {
        now.addingTimeInterval(-Double(n) * 86_400)
    }

    // MARK: - Enabled set

    func test_never_set_defaults_to_sections_with_data() {
        XCTAssertEqual(TrainSections.enabled(raw: "", withData: [.pilates]), [.pilates])
        XCTAssertEqual(TrainSections.enabled(raw: "", withData: []), [])
    }

    func test_stored_csv_wins_over_data() {
        // Removing Pilates must stick even though Pilates sessions exist.
        XCTAssertEqual(TrainSections.enabled(raw: "yoga", withData: [.pilates]), [.yoga])
    }

    func test_none_sentinel_means_explicitly_empty() {
        XCTAssertEqual(TrainSections.enabled(raw: "none", withData: [.pilates, .yoga]), [])
    }

    func test_enabled_is_in_fixed_order_and_ignores_unknown_ids() {
        XCTAssertEqual(TrainSections.enabled(raw: "stretching,bogus,pilates", withData: []),
                       [.pilates, .stretching])
    }

    func test_encode_round_trips_and_never_returns_empty() {
        XCTAssertEqual(TrainSections.encode([.stretching, .pilates]), "pilates,stretching")
        XCTAssertEqual(TrainSections.encode([]), TrainSections.noneSentinel)
        let raw = TrainSections.encode([.yoga])
        XCTAssertEqual(TrainSections.enabled(raw: raw, withData: [.pilates]), [.yoga])
    }

    func test_available_lists_the_rest_in_order() {
        XCTAssertEqual(TrainSections.available(enabled: [.yoga]), [.pilates, .stretching])
        XCTAssertEqual(TrainSections.available(enabled: TrainSection.allCases), [])
    }

    // MARK: - Metadata

    func test_pilates_keeps_its_shipped_goal_key() {
        let uid = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        XCTAssertEqual(TrainSection.pilates.goalKey(profileId: uid),
                       "pilatesWeeklyGoal.\(uid.uuidString)")
        XCTAssertEqual(TrainSections.storageKey(profileId: uid),
                       "trainSections.\(uid.uuidString)")
    }

    func test_sections_resolve_to_catalog_activities() {
        for s in TrainSection.allCases {
            XCTAssertNotNil(ActivityCatalog.activity(id: s.activityId), "\(s) has no catalog entry")
        }
        XCTAssertEqual(TrainSection.pilates.activityId, ActivityCatalog.pilatesId)
        XCTAssertEqual(TrainSection.stretching.title, "Stretching")
    }

    // MARK: - Weekly progress

    func test_count_this_week_uses_monday_week() {
        // Wed now: Mon (2 days ago) is in, the previous Sunday (3 days ago) is out.
        let dates = [daysAgo(0), daysAgo(2), daysAgo(3)]
        XCTAssertEqual(TrainSections.countThisWeek(dates, now: now, calendar: utc), 2)
    }

    func test_weekly_streak_matches_pilates_rule() {
        let dates = [daysAgo(0), daysAgo(1), daysAgo(2),
                     daysAgo(7), daysAgo(8), daysAgo(9)]
        XCTAssertEqual(TrainSections.weeklyStreak(dates, goalSessions: 3, now: now, calendar: utc), 2)
        // Current week below goal is grace, previous empty week ends the chain.
        XCTAssertEqual(TrainSections.weeklyStreak([daysAgo(0)], goalSessions: 3, now: now, calendar: utc), 0)
    }
}
