import XCTest

// Pure Domain. `now` is pinned to the project's mid-week date (Wed 2026-05-27)
// and built from a day key at local noon, so day-key math holds in any time zone.
final class CardioFitnessTests: XCTestCase {

    private func day(_ key: String, hour: Double = 12) -> Date {
        Dates.date(fromDayKey: key)!.addingTimeInterval(hour * 3600)
    }

    private var now: Date { day("2026-05-27") }

    private let uid = UUID()

    private func marker(_ key: String, _ kind: HealthMarkerKind, _ v: Double) -> HealthMarkerDTO {
        HealthMarkerDTO(userId: uid, date: key, kind: kind, value: v, source: "healthkit")
    }

    // MARK: - No label, no range, no tint (plan §9.1)

    func test_vo2Max_is_never_classified() {
        XCTAssertNil(HealthRanges.context(for: .vo2Max))
        for v in [10.0, 14, 25, 38.5, 50, 65, 80] {
            XCTAssertEqual(HealthRanges.status(for: .vo2Max, value: v), .unknown, "value \(v)")
            XCTAssertNil(TargetRationale.markerMeaning(kind: .vo2Max, value: v, fitnessGoal: .lose))
            XCTAssertNil(TargetRationale.markerMeaning(kind: .vo2Max, value: v, fitnessGoal: .gain))
        }
    }

    func test_vo2Max_copy_carries_no_rating_words() {
        let banned = ["healthy", "optimal", "normal", "good", "poor", "excellent", "fair",
                      "average", "borderline", "worth watching", "risk", "should"]
        let trends: [CardioFitness.Trend] = [
            .tooSoon,
            .aboutTheSame(since: "2026-03-01"),
            .up(3.2, since: "2026-03-01"),
            .down(3.2, since: "2026-03-01"),
        ]
        for t in trends {
            let texts = [CardioFitness.noteText(t), CardioFitness.chipText(t) ?? ""]
            for text in texts {
                for word in banned {
                    XCTAssertFalse(text.localizedCaseInsensitiveContains(word), "\"\(text)\" contains \"\(word)\"")
                }
            }
        }
    }

    func test_vo2Max_is_not_a_stall_nudge_marker() {
        XCTAssertFalse(StallDetector.stallMarkerKinds.contains(.vo2Max))
    }

    func test_raw_value_is_pinned() {
        XCTAssertEqual(HealthMarkerKind.vo2Max.rawValue, "vo2_max")
        XCTAssertEqual(HealthMarkerKind(rawValue: "vo2_max"), .vo2Max)
    }

    // MARK: - History start (plan §9.2: no one-shot flag)

    func test_history_starts_two_years_back_when_nothing_stored() {
        let start = CardioFitness.historyStart(existing: [marker("2026-05-01", .restingHR, 60)], now: now)
        let expected = Calendar.current.date(byAdding: .year, value: -2, to: now)!
        XCTAssertEqual(start, expected)
    }

    func test_history_starts_at_newest_stored_vo2_day() {
        let existing = [
            marker("2026-04-02", .vo2Max, 37),
            marker("2026-05-20", .vo2Max, 38),
            marker("2026-05-26", .restingHR, 61),   // other kinds don't move the start
        ]
        let start = CardioFitness.historyStart(existing: existing, now: now)
        XCTAssertEqual(start, Dates.date(fromDayKey: "2026-05-20"))
    }

    // MARK: - Daily dedupe (plan §9.6)

    func test_new_readings_keep_newest_sample_per_day_and_skip_stored_days() {
        let samples = [
            CardioFitness.Reading(date: day("2026-05-20", hour: 9), value: 38.9),  // stored day → skipped
            CardioFitness.Reading(date: day("2026-05-22", hour: 8), value: 39.0),
            CardioFitness.Reading(date: day("2026-05-22", hour: 18), value: 39.4), // newer same day wins
            CardioFitness.Reading(date: day("2026-05-21", hour: 7), value: 38.7),
        ]
        let existing = [marker("2026-05-20", .vo2Max, 38.5), marker("2026-05-21", .restingHR, 60)]
        let out = CardioFitness.newDailyReadings(samples, existing: existing)
        XCTAssertEqual(out, [
            Trends.Point(date: "2026-05-21", value: 38.7),
            Trends.Point(date: "2026-05-22", value: 39.4),
        ])
    }

    func test_new_readings_empty_when_everything_is_stored() {
        let samples = [CardioFitness.Reading(date: day("2026-05-20"), value: 38.9)]
        XCTAssertEqual(CardioFitness.newDailyReadings(samples, existing: [marker("2026-05-20", .vo2Max, 38.5)]), [])
    }

    // MARK: - Trend

    func test_trend_no_verdict_on_one_reading() {
        XCTAssertEqual(CardioFitness.vo2Trend(samples: [], now: now), .tooSoon)
        XCTAssertEqual(CardioFitness.vo2Trend(samples: [Trends.Point(date: "2026-05-20", value: 40)], now: now), .tooSoon)
        XCTAssertNil(CardioFitness.chipText(.tooSoon))
    }

    func test_trend_needs_a_reading_eight_weeks_earlier() {
        // 2026-03-26 → 2026-05-20 is 55 days: one short of 8 weeks.
        let pts = [Trends.Point(date: "2026-03-26", value: 35), Trends.Point(date: "2026-05-20", value: 40)]
        XCTAssertEqual(CardioFitness.vo2Trend(samples: pts, now: now), .tooSoon)
    }

    func test_trend_compares_with_newest_reading_at_least_eight_weeks_earlier() {
        let pts = [
            Trends.Point(date: "2026-05-20", value: 41.0),
            Trends.Point(date: "2026-01-10", value: 30.0),
            Trends.Point(date: "2026-03-25", value: 36.5),   // exactly 56 days before latest → baseline
            Trends.Point(date: "2026-04-30", value: 39.0),   // too recent to compare
        ]
        XCTAssertEqual(CardioFitness.vo2Trend(samples: pts, now: now), .up(4.5, since: "2026-03-25"))
    }

    func test_trend_inside_noise_band_is_about_the_same() {
        let up2 = [Trends.Point(date: "2026-03-01", value: 38.1), Trends.Point(date: "2026-05-20", value: 40.1)]
        XCTAssertEqual(CardioFitness.vo2Trend(samples: up2, now: now), .aboutTheSame(since: "2026-03-01"))
        let down2 = [Trends.Point(date: "2026-03-01", value: 40.0), Trends.Point(date: "2026-05-20", value: 38.0)]
        XCTAssertEqual(CardioFitness.vo2Trend(samples: down2, now: now), .aboutTheSame(since: "2026-03-01"))
    }

    func test_trend_down_is_reported_plainly() {
        let pts = [Trends.Point(date: "2026-03-01", value: 42.0), Trends.Point(date: "2026-05-20", value: 38.4)]
        let t = CardioFitness.vo2Trend(samples: pts, now: now)
        XCTAssertEqual(t, .down(3.6, since: "2026-03-01"))
        XCTAssertTrue(CardioFitness.noteText(t).contains("3.6 lower"))
        XCTAssertTrue(CardioFitness.noteText(t).contains("estimate"))
    }

    func test_trend_ignores_days_after_now() {
        let pts = [
            Trends.Point(date: "2026-03-01", value: 38.0),
            Trends.Point(date: "2026-05-20", value: 38.5),
            Trends.Point(date: "2026-06-30", value: 45.0),
        ]
        XCTAssertEqual(CardioFitness.vo2Trend(samples: pts, now: now), .aboutTheSame(since: "2026-03-01"))
    }

    // MARK: - "as of" (plan §9.5: date only)

    func test_as_of_label_is_date_only() {
        let label = CardioFitness.asOfLabel(dayKey: "2026-11-18")
        XCTAssertEqual(label, "as of " + Dates.formatShort("2026-11-18"))
        XCTAssertFalse(label.contains(":"), "no time of day")
    }

    // MARK: - One-time tracker migration (plan §10, Q8 = b)

    func test_enabled_trackers_migration() {
        // Defaults (empty) already include the tracker: leave the sentinel alone.
        XCTAssertEqual(CardioFitness.enabledTrackers("", adding: "vo2Max"), "")
        // Customized: appended, nothing else touched.
        XCTAssertEqual(CardioFitness.enabledTrackers("weight,bp,waist", adding: "vo2Max"), "weight,bp,waist,vo2Max")
        // Already there: unchanged.
        XCTAssertEqual(CardioFitness.enabledTrackers("weight,vo2Max", adding: "vo2Max"), "weight,vo2Max")
        // "show nothing" sentinel → just this tracker (never "none,vo2Max").
        XCTAssertEqual(CardioFitness.enabledTrackers("none", adding: "vo2Max"), "vo2Max")
    }

    func test_cardio_minutes_migration_runs_after_vo2() {
        // ProgressTabView runs the VO₂ migration, then the cardio-minutes one
        // (its own flag), both through enabledTrackers. Raw values pinned here:
        // StatKind lives in the app target, not Domain.
        func both(_ csv: String) -> String {
            CardioFitness.enabledTrackers(CardioFitness.enabledTrackers(csv, adding: "vo2Max"), adding: "cardioMinutes")
        }
        XCTAssertEqual(both(""), "", "defaults already include both")
        XCTAssertEqual(both("weight,bp"), "weight,bp,vo2Max,cardioMinutes")
        XCTAssertEqual(both("none"), "vo2Max,cardioMinutes", "never \"none,…\"")
        // A profile whose VO₂ flag already ran (and kept or hid vo2Max).
        XCTAssertEqual(CardioFitness.enabledTrackers("weight,vo2Max", adding: "cardioMinutes"), "weight,vo2Max,cardioMinutes")
        XCTAssertEqual(CardioFitness.enabledTrackers("weight", adding: "cardioMinutes"), "weight,cardioMinutes")
        XCTAssertEqual(CardioFitness.enabledTrackers("none", adding: "cardioMinutes"), "cardioMinutes")
        XCTAssertEqual(CardioFitness.enabledTrackers("cardioMinutes,weight", adding: "cardioMinutes"), "cardioMinutes,weight")
    }

    func test_supported_range_matches_apple() {
        XCTAssertEqual(CardioFitness.supportedRange.lowerBound, 14)
        XCTAssertEqual(CardioFitness.supportedRange.upperBound, 65)
    }
}
