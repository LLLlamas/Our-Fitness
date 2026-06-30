import XCTest

final class StallDetectorTests: XCTestCase {

    // Pinned mid-month (no DST boundary near June) so day math is deterministic.
    private let now = ISO8601DateFormatter().date(from: "2026-06-15T12:00:00Z")!
    private let uid = UUID()

    private func date(_ daysAgo: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!
    }
    private func day(_ daysAgo: Int) -> String { Dates.dayKey(date(daysAgo)) }

    private func step(_ daysAgo: Int, _ steps: Int) -> StepCountDTO {
        StepCountDTO(userId: uid, date: day(daysAgo), steps: steps)
    }
    private func set(_ daysAgo: Int) -> WorkoutSetDTO {
        WorkoutSetDTO(userId: uid, exerciseId: "squat", reps: 10, timestamp: date(daysAgo))
    }
    private func pil(_ daysAgo: Int) -> PilatesSessionDTO {
        PilatesSessionDTO(profileId: uid, date: date(daysAgo), durationMinutes: 20, focusAreas: [.core])
    }
    private func weight(_ daysAgo: Int, _ lb: Double) -> BodyMetricDTO {
        BodyMetricDTO(userId: uid, date: day(daysAgo), weightLb: lb)
    }
    private func marker(_ daysAgo: Int, _ kind: HealthMarkerKind, _ v: Double) -> HealthMarkerDTO {
        HealthMarkerDTO(userId: uid, date: day(daysAgo), kind: kind, value: v)
    }

    // MARK: - No history / active → nil

    func test_no_history_is_not_a_stall() {
        XCTAssertNil(StallDetector.detect(mode: .build, now: now))
        XCTAssertNil(StallDetector.detect(mode: .circuit, now: now))
    }

    func test_active_user_is_not_stalled() {
        let out = StallDetector.detect(
            mode: .build, steps: [step(0, 9000), step(1, 8000)], sets: [set(0)], now: now)
        XCTAssertNil(out)
    }

    // MARK: - Steps gap

    func test_steps_gap_when_last_active_day_is_old() {
        let out = StallDetector.detect(mode: .build, steps: [step(3, 8000), step(4, 7000)], now: now)
        XCTAssertEqual(out, .stepsGap(days: 3))
    }

    func test_recent_low_steps_do_not_count_as_active() {
        // Logged today but only 200 steps; last real activity 3 days ago.
        let out = StallDetector.detect(mode: .build, steps: [step(0, 200), step(3, 8000)], now: now)
        XCTAssertEqual(out, .stepsGap(days: 3))
    }

    func test_steps_yesterday_is_not_a_gap() {
        XCTAssertNil(StallDetector.detect(mode: .build, steps: [step(1, 9000)], now: now))
    }

    // MARK: - Workout gap (mode-dependent threshold)

    func test_workout_gap_build_at_5_days() {
        XCTAssertEqual(StallDetector.detect(mode: .build, sets: [set(5)], now: now), .workoutGap(days: 5))
    }

    func test_workout_gap_circuit_needs_7_days() {
        XCTAssertEqual(StallDetector.detect(mode: .build, sets: [set(6)], now: now), .workoutGap(days: 6))
        XCTAssertNil(StallDetector.detect(mode: .circuit, sets: [set(6)], now: now))
        XCTAssertEqual(StallDetector.detect(mode: .circuit, sets: [set(7)], now: now), .workoutGap(days: 7))
    }

    // MARK: - Pilates gap (Circuit only)

    func test_pilates_gap_circuit_only() {
        XCTAssertEqual(StallDetector.detect(mode: .circuit, pilates: [pil(8)], now: now), .pilatesGap(days: 8))
        XCTAssertNil(StallDetector.detect(mode: .build, pilates: [pil(30)], now: now))
    }

    // MARK: - Weight stall (Circuit only)

    func test_weight_stall_when_flat() {
        let out = StallDetector.detect(mode: .circuit, weights: [weight(14, 180), weight(0, 179.9)], now: now)
        XCTAssertEqual(out, .weightStall(weeks: 2))
    }

    func test_no_weight_stall_when_losing() {
        // ~1 lb/week loss → on track.
        XCTAssertNil(StallDetector.detect(mode: .circuit, weights: [weight(14, 182), weight(0, 180)], now: now))
    }

    func test_weight_stall_ignored_in_build() {
        XCTAssertNil(StallDetector.detect(mode: .build, weights: [weight(14, 180), weight(0, 180)], now: now))
    }

    // MARK: - Marker stall

    func test_marker_stall_when_ldl_flat_6_weeks() {
        let out = StallDetector.detect(mode: .circuit, markers: [marker(49, .ldl, 130), marker(0, .ldl, 129)], now: now)
        guard case .markerStall(.ldl, _) = out else { return XCTFail("expected LDL markerStall, got \(String(describing: out))") }
    }

    func test_marker_not_stalled_when_improving() {
        // LDL dropped ~15% → moving, not stalled.
        XCTAssertNil(StallDetector.detect(mode: .circuit, markers: [marker(49, .ldl, 150), marker(0, .ldl, 127)], now: now))
    }

    func test_marker_not_stalled_without_old_enough_reading() {
        // Both readings inside the 6-week window → can't judge a 6-week stall.
        XCTAssertNil(StallDetector.detect(mode: .circuit, markers: [marker(10, .ldl, 130), marker(0, .ldl, 129)], now: now))
    }

    // MARK: - Priority

    func test_priority_steps_over_workout() {
        let out = StallDetector.detect(mode: .build, steps: [step(3, 8000)], sets: [set(10)], now: now)
        XCTAssertEqual(out, .stepsGap(days: 3))
    }

    // MARK: - Copy

    func test_every_stall_has_nonempty_nudge_copy() {
        let stalls: [StallDetector.Stall] = [
            .stepsGap(days: 3), .workoutGap(days: 6), .pilatesGap(days: 8),
            .weightStall(weeks: 2), .markerStall(.ldl, weeks: 7),
        ]
        for s in stalls {
            for mode in [Mode.build, .circuit] {
                let m = EncouragementEngine.stallMessage(s, mode: mode)
                XCTAssertFalse(m.headline.isEmpty)
                XCTAssertFalse(m.detail.isEmpty)
                XCTAssertEqual(m.tone, .nudge)
            }
        }
    }
}
