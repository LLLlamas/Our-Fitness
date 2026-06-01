import XCTest

final class MovementTests: XCTestCase {

    // MARK: - Milestone gate

    func test_milestone_returns_largest_unfired_below_steps() {
        let m = Movement.shouldFireMilestone(steps: 8_200, firedSet: [3_000, 5_000])
        XCTAssertEqual(m, 8_000)
    }

    func test_milestone_returns_nil_when_below_first_threshold() {
        XCTAssertNil(Movement.shouldFireMilestone(steps: 2_500, firedSet: []))
    }

    func test_milestone_returns_nil_when_milestones_empty() {
        // No thresholds configured → nothing can fire, even with huge step counts.
        XCTAssertNil(Movement.shouldFireMilestone(steps: 50_000, firedSet: [], milestones: []))
    }

    func test_milestone_returns_nil_when_all_fired() {
        let m = Movement.shouldFireMilestone(
            steps: 10_500,
            firedSet: [3_000, 5_000, 8_000, 10_000]
        )
        XCTAssertNil(m)
    }

    func test_milestone_only_picks_unfired_even_when_higher_exists() {
        // Steps cross 5k; 3k already fired; 8k/10k still ahead. We expect 5k.
        let m = Movement.shouldFireMilestone(steps: 5_100, firedSet: [3_000])
        XCTAssertEqual(m, 5_000)
    }

    func test_milestone_set_roundtrip() {
        let original: Set<Int> = [3_000, 8_000]
        let encoded = Movement.encode(firedSet: original)
        XCTAssertEqual(Movement.decode(firedSet: encoded), original)
    }

    func test_milestone_decode_tolerates_garbage() {
        XCTAssertEqual(Movement.decode(firedSet: ""), [])
        XCTAssertEqual(Movement.decode(firedSet: "abc,3000,xyz"), [3_000])
    }

    // MARK: - Delta vs yesterday

    func test_delta_positive_when_ahead() {
        var today = Array(repeating: 0, count: 24)
        var yesterday = Array(repeating: 0, count: 24)
        for h in 0...13 { today[h] = h * 600 }      // 7800 by 1pm
        for h in 0...13 { yesterday[h] = h * 500 }  // 6500 by 1pm
        let delta = Movement.stepsDeltaVsYesterday(
            intradayToday: today, intradayYesterday: yesterday, currentHour: 13
        )
        XCTAssertEqual(delta, 1_300)
    }

    func test_delta_zero_when_arrays_wrong_length() {
        let delta = Movement.stepsDeltaVsYesterday(
            intradayToday: [1, 2, 3], intradayYesterday: [], currentHour: 12
        )
        XCTAssertEqual(delta, 0)
    }

    func test_delta_clamps_hour() {
        let today = Array(repeating: 5_000, count: 24)
        let yesterday = Array(repeating: 4_000, count: 24)
        let delta = Movement.stepsDeltaVsYesterday(
            intradayToday: today, intradayYesterday: yesterday, currentHour: 99
        )
        XCTAssertEqual(delta, 1_000)
    }

    // MARK: - Pilates weekly streak

    private func session(_ daysAgo: Int, minutes: Int = 30,
                         focus: [PilatesFocusArea] = [.core],
                         now: Date = Date()) -> PilatesSessionDTO {
        let cal = Calendar(identifier: .iso8601)
        let date = cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return PilatesSessionDTO(
            profileId: UUID(), date: date,
            durationMinutes: minutes, focusAreas: focus
        )
    }

    func test_streak_zero_when_no_sessions() {
        XCTAssertEqual(Movement.pilatesWeeklyStreak(sessions: []), 0)
    }

    func test_streak_current_week_in_grace_zone() {
        // Only one session this week — goal is 3 — but grace means we still
        // slide backward without breaking. Previous week with 0 ends the chain.
        let s = [session(0)]
        XCTAssertEqual(Movement.pilatesWeeklyStreak(sessions: s, goalSessions: 3), 0)
    }

    func test_streak_current_week_exactly_meets_goal() {
        // Boundary: current week count equals goalSessions exactly → counts as 1.
        // Previous week has nothing, so chain ends there.
        // Pin to Wednesday so days 0/1/2 all fall in the same ISO week (Mon–Sun).
        let now = ISO8601DateFormatter().date(from: "2026-05-27T12:00:00Z")!
        let s = [session(0, now: now), session(1, now: now), session(2, now: now)]
        XCTAssertEqual(Movement.pilatesWeeklyStreak(sessions: s, goalSessions: 3, now: now), 1)
    }

    func test_streak_counts_consecutive_weeks_at_goal() {
        // 3 sessions this week + 3 last week → 2-week streak.
        // Pin to Wednesday so days 0/1/2 stay in this ISO week and
        // days 7/8/9 stay in the previous ISO week.
        let now = ISO8601DateFormatter().date(from: "2026-05-27T12:00:00Z")!
        let s = [session(0, now: now), session(1, now: now), session(2, now: now),
                 session(7, now: now), session(8, now: now), session(9, now: now)]
        let n = Movement.pilatesWeeklyStreak(sessions: s, goalSessions: 3, now: now)
        XCTAssertEqual(n, 2)
    }

    // MARK: - Step weekly streak

    private func stepRec(_ daysAgo: Int, steps: Int, now: Date = Date()) -> StepCountDTO {
        let cal = Calendar(identifier: .iso8601)
        let date = cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return StepCountDTO(
            userId: UUID(), date: Dates.dayKey(date),
            steps: steps, source: .manual
        )
    }

    func test_stepStreak_zero_when_no_data() {
        XCTAssertEqual(
            Movement.stepWeeklyStreak(steps: [], dailyGoal: 10_000),
            0
        )
    }

    func test_stepStreak_counts_week_when_threshold_hit() {
        // Pin `now` to a Sunday so the 5 prior days all sit inside the same
        // ISO week (Mon–Sun) and the test isn't day-of-week dependent.
        let now = ISO8601DateFormatter().date(from: "2026-05-31T12:00:00Z")!  // Sunday
        let s = (0..<5).map { stepRec($0, steps: 12_000, now: now) }
        let n = Movement.stepWeeklyStreak(
            steps: s, dailyGoal: 10_000, now: now
        )
        XCTAssertEqual(n, 1)
    }

    func test_sessionsThisWeek_filters_to_current_week() {
        // Reference date is a fixed Wednesday so the iso8601 week window is stable.
        let now = ISO8601DateFormatter().date(from: "2026-05-27T12:00:00Z")!
        let s = [
            session(0, now: now),    // this week
            session(2, now: now),    // this week
            session(9, now: now),    // last week
        ]
        XCTAssertEqual(Movement.sessionsThisWeek(s, now: now).count, 2)
    }
}
