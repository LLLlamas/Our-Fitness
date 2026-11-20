import XCTest

// Pure Domain: `CardioFitness.weeklyMinutes` and its filters (plan §4.5, §7 Q5 b
// + Q7, §9 "Phase 2 must"). `now` is pinned to Wed 2026-05-27, so this ISO week
// is Mon 2026-05-25 … Sun 2026-05-31 and last week starts Mon 2026-05-18.
final class CardioMinutesTests: XCTestCase {

    private func day(_ key: String, hour: Double = 12) -> Date {
        Dates.date(fromDayKey: key)!.addingTimeInterval(hour * 3600)
    }

    private var now: Date { day("2026-05-27") }
    private let uid = UUID()

    private func session(_ key: String, hour: Double = 12, _ minutes: Int,
                         id: String = "activity-walking") -> ActivitySessionDTO {
        ActivitySessionDTO(profileId: uid, date: day(key, hour: hour), activityId: id,
                           activityName: id, met: 3.5, durationMinutes: minutes, expectedMinutes: minutes)
    }

    private func workout(_ key: String, hour: Double = 12, _ minutes: Double,
                         kind: CardioFitness.WorkoutKind = .walking,
                         source: String = "com.apple.health.workout") -> CardioFitness.HealthWorkout {
        let start = day(key, hour: hour)
        return CardioFitness.HealthWorkout(start: start, end: start.addingTimeInterval(minutes * 60),
                                           durationSeconds: minutes * 60, kind: kind, sourceBundleId: source)
    }

    private func weekly(_ activities: [ActivitySessionDTO] = [], legacy: [CardioSessionDTO] = [],
                        health: [CardioFitness.HealthWorkout] = [], at: Date? = nil) -> CardioFitness.WeeklyMinutes {
        CardioFitness.weeklyMinutes(activities: activities, legacy: legacy, health: health, now: at ?? now)
    }

    // MARK: - ISO-week edges

    func test_week_runs_monday_to_sunday() {
        let w = weekly([
            session("2026-05-25", hour: 0.1, 10),    // Mon 00:06 → this week
            session("2026-05-24", hour: 23.9, 20),   // Sun 23:54 → last week
            session("2026-05-17", hour: 23.9, 40),   // Sun before → two weeks ago
        ])
        XCTAssertEqual(w.thisWeek, 10)
        XCTAssertEqual(w.lastWeek, 20)
    }

    func test_session_counts_in_the_week_it_started() {
        // Starts Sun 23:30, runs 60 min into Monday: all of it is last week.
        let w = weekly([session("2026-05-24", hour: 23.5, 60)])
        XCTAssertEqual(w.thisWeek, 0)
        XCTAssertEqual(w.lastWeek, 60)
    }

    func test_now_on_sunday_night_and_monday_morning() {
        let sessions = [session("2026-05-25", 15), session("2026-05-31", hour: 20, 25)]
        let sunday = weekly(sessions, at: day("2026-05-31", hour: 23.9))
        XCTAssertEqual(sunday.thisWeek, 40)
        let monday = weekly(sessions, at: day("2026-06-01", hour: 0.1))
        XCTAssertEqual(monday.thisWeek, 0)
        XCTAssertEqual(monday.lastWeek, 40)
    }

    func test_series_is_weekly_oldest_first_within_window() {
        let w = weekly([
            session("2026-05-26", 30),
            session("2026-05-19", 20),
            session("2026-03-09", 15),   // Monday 11 weeks back: oldest week shown
            session("2026-03-08", 50),   // Sunday before it: outside the window
        ])
        XCTAssertEqual(w.series.map(\.date), ["2026-03-09", "2026-05-18", "2026-05-25"])
        XCTAssertEqual(w.series.map(\.value), [15, 20, 30])
        XCTAssertEqual(Dates.dayKey(CardioFitness.healthWindowStart(now: now)), "2026-03-09")
    }

    func test_future_dated_sessions_are_ignored() {
        let w = weekly([session("2026-06-02", 30), session("2026-05-26", 10)])
        XCTAssertEqual(w.thisWeek, 10)
        XCTAssertFalse(w.series.contains { $0.date > "2026-05-25" })
    }

    // MARK: - Which activities count

    func test_pilates_yoga_stretching_do_not_count() {
        let w = weekly([
            session("2026-05-26", 30, id: ActivityCatalog.pilatesId),
            session("2026-05-26", 30, id: ActivityCatalog.yogaId),
            session("2026-05-26", 30, id: ActivityCatalog.stretchingId),
            session("2026-05-26", 12, id: "activity-running"),
            session("2026-05-26", 8, id: ActivityCatalog.otherId),
        ])
        XCTAssertEqual(w.thisWeek, 20)
    }

    func test_every_catalog_activity_is_classified_exactly_once() {
        for activity in ActivityCatalog.all {
            let cardio = CardioFitness.cardioActivityIds.contains(activity.id)
            let notCardio = CardioFitness.nonCardioActivityIds.contains(activity.id)
            XCTAssertTrue(cardio != notCardio, "\(activity.id) must be in exactly one set")
        }
        XCTAssertTrue(CardioFitness.cardioActivityIds.isDisjoint(with: CardioFitness.nonCardioActivityIds))
        XCTAssertFalse(CardioFitness.countsAsCardio(activityId: "activity-unknown"))
    }

    func test_legacy_cardio_rows_count() {
        let legacy = CardioType.allCases.map {
            CardioSessionDTO(profileId: uid, date: day("2026-05-26"), type: $0, durationMinutes: 5)
        }
        XCTAssertEqual(weekly(legacy: legacy).thisWeek, 5 * CardioType.allCases.count)
    }

    func test_health_workout_kinds() {
        let notCardio: Set<CardioFitness.WorkoutKind> = [.yoga, .pilates, .flexibility, .other]
        for kind in CardioFitness.WorkoutKind.allCases {
            XCTAssertEqual(kind.countsAsCardio, !notCardio.contains(kind), kind.rawValue)
        }
        let w = weekly(health: [
            workout("2026-05-26", hour: 7, 30, kind: .yoga),
            workout("2026-05-26", hour: 9, 20, kind: .pilates),
            workout("2026-05-26", hour: 10, 10, kind: .flexibility),
            workout("2026-05-26", hour: 11, 45, kind: .other),
            workout("2026-05-26", hour: 18, 25, kind: .walking),
        ])
        XCTAssertEqual(w.thisWeek, 25)
        XCTAssertEqual(w.healthThisWeek, 25)
        XCTAssertEqual(w.loggedThisWeek, 0)
    }

    func test_health_minutes_use_active_duration() {
        let start = day("2026-05-26", hour: 8)
        // 40 min on the clock, 31.6 min active (a pause) → 32.
        let paused = CardioFitness.HealthWorkout(start: start, end: start.addingTimeInterval(40 * 60),
                                                 durationSeconds: 31.6 * 60, kind: .running,
                                                 sourceBundleId: "com.example.runner")
        // A source that left duration at 0 falls back to the clock length.
        let noDuration = CardioFitness.HealthWorkout(start: day("2026-05-27", hour: 8),
                                                     end: day("2026-05-27", hour: 8.25),
                                                     durationSeconds: 0, kind: .cycling,
                                                     sourceBundleId: "com.example.bike")
        XCTAssertEqual(weekly(health: [paused, noDuration]).thisWeek, 32 + 15)
    }

    // MARK: - Dedupe rule 1: own app's workouts

    func test_own_app_and_watch_app_workouts_are_dropped() {
        let w = weekly(health: [
            workout("2026-05-26", hour: 7, 30, source: "com.ourfitness.app"),
            workout("2026-05-26", hour: 9, 30, source: "com.ourfitness.app.watchkitapp"),
            workout("2026-05-26", hour: 18, 20, source: "com.apple.health.workout"),
        ])
        XCTAssertEqual(w.thisWeek, 20)
        XCTAssertEqual(CardioFitness.ownBundleIds, ["com.ourfitness.app", "com.ourfitness.app.watchkitapp"])
    }

    // MARK: - Dedupe rule 2: overlap with a logged session

    func test_workout_mostly_inside_a_logged_session_is_dropped() {
        // Logged 8:00–8:30. Health 8:10–8:40 overlaps 20 of 30 min (> half) → dropped.
        let w = weekly([session("2026-05-26", hour: 8, 30)],
                       health: [workout("2026-05-26", hour: 8 + 10.0 / 60, 30)])
        XCTAssertEqual(w.thisWeek, 30)
        XCTAssertEqual(w.healthThisWeek, 0)
    }

    func test_workout_overlapping_half_or_less_is_kept() {
        // Logged 8:00–8:30. Health 8:15–8:45 overlaps exactly half → kept.
        let half = weekly([session("2026-05-26", hour: 8, 30)],
                          health: [workout("2026-05-26", hour: 8.25, 30)])
        XCTAssertEqual(half.thisWeek, 60)
        // Health 8:20–8:50 overlaps 10 of 30 min → kept.
        let little = weekly([session("2026-05-26", hour: 8, 30)],
                            health: [workout("2026-05-26", hour: 8 + 20.0 / 60, 30)])
        XCTAssertEqual(little.healthThisWeek, 30)
    }

    func test_overlap_is_measured_against_the_workout_length() {
        // A short Health workout fully inside a long logged session is dropped,
        let inside = weekly([session("2026-05-26", hour: 8, 90)],
                            health: [workout("2026-05-26", hour: 8.5, 20)])
        XCTAssertEqual(inside.thisWeek, 90)
        // while a long Health workout that only contains a short logged session is kept.
        let around = weekly([session("2026-05-26", hour: 8.5, 10)],
                            health: [workout("2026-05-26", hour: 8, 60)])
        XCTAssertEqual(around.thisWeek, 70)
    }

    func test_non_cardio_logged_sessions_do_not_hide_health_workouts() {
        // A logged yoga session isn't counted, so it can't double-count a Health walk.
        let w = weekly([session("2026-05-26", hour: 8, 30, id: ActivityCatalog.yogaId)],
                       health: [workout("2026-05-26", hour: 8, 30)])
        XCTAssertEqual(w.thisWeek, 30)
    }

    // MARK: - Notes (own history only)

    func test_note_approaching() {
        let w = weekly([session("2026-05-19", 40), session("2026-05-26", 30)])
        XCTAssertEqual(w.note, .approaching(remaining: 10))
        XCTAssertEqual(CardioFitness.minutesNoteText(w.note), "10 min to match last week")
    }

    func test_note_none_when_well_below_last_week() {
        let w = weekly([session("2026-05-19", 40), session("2026-05-26", 29)])
        XCTAssertEqual(w.note, .none)
        XCTAssertNil(CardioFitness.minutesNoteText(w.note))
    }

    func test_note_passed() {
        let w = weekly([session("2026-05-19", 40)], health: [workout("2026-05-26", 48)])
        XCTAssertEqual(w.note, .passed(by: 8))
        XCTAssertEqual(CardioFitness.minutesNoteText(w.note), "+8 vs last week")
    }

    func test_note_none_when_equal() {
        XCTAssertEqual(weekly([session("2026-05-19", 30), session("2026-05-26", 30)]).note, .none)
    }

    func test_note_first_week_back_after_a_gap() {
        let w = weekly([session("2026-05-05", 30), session("2026-05-26", 10)])
        XCTAssertEqual(w.note, .firstWeekBack)
        XCTAssertEqual(CardioFitness.minutesNoteText(w.note), "First week back")
    }

    func test_note_none_for_a_very_first_week_or_an_empty_week() {
        XCTAssertEqual(weekly([session("2026-05-26", 10)]).note, .none)
        XCTAssertEqual(weekly([session("2026-05-19", 30)]).note, .none)
        XCTAssertEqual(weekly(), .empty)
    }

    func test_notes_carry_no_push_or_shame_words() {
        let banned = ["push", "should", "missed", "failed", "behind", "best", "target", "goal"]
        let notes: [CardioFitness.MinutesNote] = [.approaching(remaining: 5), .passed(by: 5), .firstWeekBack]
        for n in notes {
            let text = CardioFitness.minutesNoteText(n)!.lowercased()
            for word in banned { XCTAssertFalse(text.contains(word), "\(text) contains \(word)") }
        }
    }
}
