import XCTest

// Pure Domain. `now` is pinned (the project's standard fixed clock — never a
// bare Date(), see CLAUDE.md CI rules) and a fixed non-UTC calendar is threaded
// into every call so results never depend on the wall clock or on the host
// machine's local time zone.
//
// Date(timeIntervalSince1970: 1_780_488_000) is exactly 2026-06-03 12:00:00 UTC,
// which is 2026-06-03 08:00:00 EDT in America/New_York — a Wednesday
// (mid-week), local hour 8, zero minutes/seconds. All "today" / "that instant is
// still ahead vs. already passed" reasoning below is relative to that local
// instant: 08:39 is still ahead of `now`, 06:35 has already gone by.
//
// WHY THIS FILE EXISTS: the medication nudge is inferred from behaviour rather
// than configured, so every number here is a guess the user never typed. The
// two failure modes that matter are (a) nudging at the wrong time of day and
// (b) nudging after the dose was already taken. Both are calendar-math bugs,
// which is why the midnight and DST cases below are load-bearing rather than
// decorative.
final class MedicationPatternTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_780_488_000)

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }()

    /// Local calendar day of `now` (midnight, America/New_York).
    private var today: Date { calendar.startOfDay(for: now) }

    /// `today` shifted by `offset` calendar days (negative = past).
    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    /// `today` shifted by `offset` calendar days, at `hour:minute:second` local time.
    private func instant(_ offset: Int, hour: Int, minute: Int = 0, second: Int = 0) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: day(offset))
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        return calendar.date(from: comps)!
    }

    /// Minutes since local midnight — the unit `typicalMinuteOfDay` speaks in.
    private func minutes(_ hour: Int, _ minute: Int) -> Int { hour * 60 + minute }

    // MARK: - Fixtures

    /// Three consecutive mornings around 8am: 08:04, 08:16, 08:09.
    /// Minutes-of-day 484 / 496 / 489, so the median is 489 == 08:09.
    private func steadyMorningRoutine() -> [Date] {
        [instant(-3, hour: 8, minute: 4),
         instant(-2, hour: 8, minute: 16),
         instant(-1, hour: 8, minute: 9)]
    }

    /// Three consecutive early mornings: 06:00, 06:10, 06:05 — median 365 == 06:05,
    /// which with the default grace lands at 06:35, already past `now`.
    private func earlyMorningRoutine() -> [Date] {
        [instant(-3, hour: 6, minute: 0),
         instant(-2, hour: 6, minute: 10),
         instant(-1, hour: 6, minute: 5)]
    }

    // MARK: - recentDailyFirstLogs

    func test_recentDailyFirstLogs_returns_one_log_per_day_oldest_first() {
        let logs = steadyMorningRoutine()
        let result = MedicationPattern.recentDailyFirstLogs(logs, now: now, calendar: calendar)
        XCTAssertEqual(result, [instant(-3, hour: 8, minute: 4),
                                instant(-2, hour: 8, minute: 16),
                                instant(-1, hour: 8, minute: 9)])
    }

    func test_recentDailyFirstLogs_takes_only_the_earliest_log_of_a_multi_dose_day() {
        // A three-times-a-day prescription. Only the morning dose describes
        // "when does this person start their day" — the 14:00 and 20:00 doses
        // are follow-ons and must not contribute a second sample.
        let logs = [instant(-2, hour: 8, minute: 0),
                    instant(-2, hour: 14, minute: 0),
                    instant(-2, hour: 20, minute: 0),
                    instant(-1, hour: 8, minute: 20)]
        let result = MedicationPattern.recentDailyFirstLogs(logs, now: now, calendar: calendar)
        XCTAssertEqual(result, [instant(-2, hour: 8, minute: 0),
                                instant(-1, hour: 8, minute: 20)])
    }

    func test_recentDailyFirstLogs_excludes_today() {
        // Today is the day being predicted; folding it back into the pattern
        // would let a single unusual morning move the estimate for that morning.
        let logs = steadyMorningRoutine() + [instant(0, hour: 6, minute: 30)]
        let result = MedicationPattern.recentDailyFirstLogs(logs, now: now, calendar: calendar)
        XCTAssertEqual(result.count, 3)
        XCTAssertFalse(result.contains(instant(0, hour: 6, minute: 30)))
        for entry in result {
            XCTAssertLessThan(entry, today, "a log from today leaked into the pattern")
        }
    }

    func test_recentDailyFirstLogs_excludes_logs_older_than_lookbackDays() {
        let logs = [instant(-30, hour: 8, minute: 0),
                    instant(-9, hour: 8, minute: 0),
                    instant(-8, hour: 8, minute: 0),
                    instant(-2, hour: 8, minute: 0)]
        let result = MedicationPattern.recentDailyFirstLogs(logs, now: now, calendar: calendar)
        XCTAssertEqual(result, [instant(-2, hour: 8, minute: 0)])
    }

    func test_recentDailyFirstLogs_covers_the_whole_lookback_window() {
        // `lookbackDays` days of history, today excluded, means day -1 through
        // day -7 inclusive. day -8 is the first one outside the window.
        XCTAssertEqual(MedicationPattern.lookbackDays, 7)
        let logs = (1...8).map { instant(-$0, hour: 9) }
        let result = MedicationPattern.recentDailyFirstLogs(logs, now: now, calendar: calendar)
        XCTAssertEqual(result.count, MedicationPattern.lookbackDays)
        XCTAssertEqual(result.first, instant(-7, hour: 9))
        XCTAssertEqual(result.last, instant(-1, hour: 9))
    }

    func test_recentDailyFirstLogs_empty_for_no_history() {
        XCTAssertTrue(MedicationPattern.recentDailyFirstLogs([], now: now, calendar: calendar).isEmpty)
    }

    func test_recentDailyFirstLogs_late_night_log_belongs_to_its_own_local_day() {
        // 10 minutes apart in real time, either side of local midnight. Day
        // bucketing has to be calendar-based, or a 23:55 dose gets merged into
        // the following morning and drags that day's "first log" backwards.
        let lateNight = instant(-2, hour: 23, minute: 55)
        let justAfterMidnight = instant(-1, hour: 0, minute: 5)
        XCTAssertEqual(justAfterMidnight.timeIntervalSince(lateNight), 600, accuracy: 0.001)

        let result = MedicationPattern.recentDailyFirstLogs(
            [lateNight, justAfterMidnight], now: now, calendar: calendar
        )
        XCTAssertEqual(result, [lateNight, justAfterMidnight], "the two logs must stay in separate day buckets")
        XCTAssertEqual(calendar.startOfDay(for: result[0]), day(-2))
        XCTAssertEqual(calendar.startOfDay(for: result[1]), day(-1))
        XCTAssertEqual(MedicationPattern.dayCount([lateNight, justAfterMidnight], now: now, calendar: calendar), 2)
    }

    func test_recentDailyFirstLogs_unsorted_input_matches_sorted_input() {
        // Logs arrive from an append-only store and are not guaranteed sorted;
        // back-dated entries in particular land out of order.
        let sorted = [instant(-3, hour: 8, minute: 4),
                      instant(-3, hour: 19, minute: 0),
                      instant(-2, hour: 8, minute: 16),
                      instant(-1, hour: 8, minute: 9),
                      instant(-1, hour: 21, minute: 30)]
        let scrambled = [sorted[3], sorted[0], sorted[4], sorted[2], sorted[1]]

        XCTAssertEqual(
            MedicationPattern.recentDailyFirstLogs(scrambled, now: now, calendar: calendar),
            MedicationPattern.recentDailyFirstLogs(sorted, now: now, calendar: calendar)
        )
        XCTAssertEqual(
            MedicationPattern.typicalMinuteOfDay(scrambled, now: now, calendar: calendar),
            MedicationPattern.typicalMinuteOfDay(sorted, now: now, calendar: calendar)
        )
    }

    // MARK: - dayCount

    func test_dayCount_counts_distinct_days_not_individual_logs() {
        let logs = [instant(-3, hour: 8),
                    instant(-3, hour: 14),
                    instant(-3, hour: 20),
                    instant(-1, hour: 8)]
        XCTAssertEqual(MedicationPattern.dayCount(logs, now: now, calendar: calendar), 2)
    }

    func test_dayCount_excludes_today_and_anything_out_of_window() {
        let logs = [instant(-20, hour: 8),
                    instant(-2, hour: 8),
                    instant(0, hour: 7),
                    instant(0, hour: 7, minute: 30)]
        XCTAssertEqual(MedicationPattern.dayCount(logs, now: now, calendar: calendar), 1)
    }

    func test_dayCount_zero_for_no_history() {
        XCTAssertEqual(MedicationPattern.dayCount([], now: now, calendar: calendar), 0)
    }

    // MARK: - typicalMinuteOfDay

    func test_typicalMinuteOfDay_median_of_a_steady_morning_routine() {
        // 08:04 / 08:16 / 08:09 -> 484 / 496 / 489 -> median 489.
        let result = MedicationPattern.typicalMinuteOfDay(steadyMorningRoutine(), now: now, calendar: calendar)
        XCTAssertEqual(result, minutes(8, 9))
    }

    func test_typicalMinuteOfDay_outlier_day_does_not_drag_the_median_out_of_the_morning() throws {
        // Four ordinary mornings plus one 11:42 "took it late" day. A mean would
        // be pulled to ~08:57 and keep sliding with every bad day; the median
        // moves by one sample position and stays inside the routine.
        let logs = steadyMorningRoutine() + [instant(-4, hour: 8, minute: 12),
                                             instant(-5, hour: 11, minute: 42)]
        // 484 / 489 / 492 / 496 / 702 -> median 492.
        let result = try XCTUnwrap(MedicationPattern.typicalMinuteOfDay(logs, now: now, calendar: calendar))
        XCTAssertEqual(result, minutes(8, 12))
        XCTAssertLessThan(result, minutes(10, 0), "the outlier dragged the estimate out of the morning")
    }

    func test_typicalMinuteOfDay_even_count_averages_the_two_middle_values() {
        // 07:00 / 08:00 / 08:20 / 09:40 -> 420 / 480 / 500 / 580.
        // Middles 480 and 500 average to exactly 490 == 08:10, which is not
        // equal to either middle sample.
        let logs = [instant(-4, hour: 7, minute: 0),
                    instant(-3, hour: 8, minute: 0),
                    instant(-2, hour: 8, minute: 20),
                    instant(-1, hour: 9, minute: 40)]
        let result = MedicationPattern.typicalMinuteOfDay(logs, now: now, calendar: calendar)
        XCTAssertEqual(result, minutes(8, 10))
        XCTAssertNotEqual(result, minutes(8, 0))
        XCTAssertNotEqual(result, minutes(8, 20))
    }

    func test_typicalMinuteOfDay_uses_only_the_earliest_log_of_a_multi_dose_day() {
        // Same fixture shape as the multi-dose test above: if the afternoon and
        // evening doses were sampled, the median would land in the afternoon.
        let logs = [instant(-3, hour: 8, minute: 0),
                    instant(-3, hour: 14, minute: 0),
                    instant(-3, hour: 20, minute: 0),
                    instant(-2, hour: 8, minute: 20),
                    instant(-1, hour: 7, minute: 40)]
        let result = MedicationPattern.typicalMinuteOfDay(logs, now: now, calendar: calendar)
        XCTAssertEqual(result, minutes(8, 0))
    }

    func test_typicalMinuteOfDay_ignores_todays_logs() {
        let withoutToday = MedicationPattern.typicalMinuteOfDay(
            steadyMorningRoutine(), now: now, calendar: calendar
        )
        let withToday = MedicationPattern.typicalMinuteOfDay(
            steadyMorningRoutine() + [instant(0, hour: 5, minute: 0)], now: now, calendar: calendar
        )
        XCTAssertEqual(withToday, withoutToday)
        XCTAssertEqual(withToday, minutes(8, 9))
    }

    func test_typicalMinuteOfDay_nil_without_recent_history() {
        XCTAssertNil(MedicationPattern.typicalMinuteOfDay([], now: now, calendar: calendar))
        // Only-today and only-stale histories are both "no recent history".
        XCTAssertNil(MedicationPattern.typicalMinuteOfDay([instant(0, hour: 7)], now: now, calendar: calendar))
        XCTAssertNil(MedicationPattern.typicalMinuteOfDay([instant(-40, hour: 7)], now: now, calendar: calendar))
    }

    func test_typicalMinuteOfDay_stays_inside_a_single_day() throws {
        // 00:01 and 23:59 — the extremes. The result is a minute-of-day, so it
        // must stay in 0..<1440 however far apart the samples are.
        let logs = [instant(-2, hour: 0, minute: 1), instant(-1, hour: 23, minute: 59)]
        let result = try XCTUnwrap(MedicationPattern.typicalMinuteOfDay(logs, now: now, calendar: calendar))
        XCTAssertGreaterThanOrEqual(result, 0)
        XCTAssertLessThan(result, 1_440)
        XCTAssertEqual(result, minutes(12, 0)) // (1 + 1439) / 2
    }

    // MARK: - hasDisplayablePattern / hasLogToday

    func test_hasDisplayablePattern_false_below_minDaysForDisplay() {
        XCTAssertEqual(MedicationPattern.minDaysForDisplay, 2)
        XCTAssertFalse(MedicationPattern.hasDisplayablePattern([], now: now, calendar: calendar))
        XCTAssertFalse(MedicationPattern.hasDisplayablePattern(
            [instant(-1, hour: 8, minute: 9)], now: now, calendar: calendar
        ), "one day is not yet a pattern worth showing")
    }

    func test_hasDisplayablePattern_true_at_minDaysForDisplay() {
        let twoDays = [instant(-2, hour: 8, minute: 4), instant(-1, hour: 8, minute: 9)]
        XCTAssertEqual(MedicationPattern.dayCount(twoDays, now: now, calendar: calendar),
                       MedicationPattern.minDaysForDisplay)
        XCTAssertTrue(MedicationPattern.hasDisplayablePattern(twoDays, now: now, calendar: calendar))
        XCTAssertTrue(MedicationPattern.hasDisplayablePattern(steadyMorningRoutine(), now: now, calendar: calendar))
    }

    func test_hasDisplayablePattern_ignores_repeat_doses_on_a_single_day() {
        // Three logs, one day — not three days of evidence.
        let oneBusyDay = [instant(-1, hour: 8), instant(-1, hour: 14), instant(-1, hour: 20)]
        XCTAssertFalse(MedicationPattern.hasDisplayablePattern(oneBusyDay, now: now, calendar: calendar))
    }

    func test_hasLogToday_sees_todays_logs_that_the_pattern_excludes() {
        let logs = steadyMorningRoutine() + [instant(0, hour: 6, minute: 30)]
        XCTAssertTrue(MedicationPattern.hasLogToday(logs, now: now, calendar: calendar))
        // ...while the pattern itself still ignores them.
        XCTAssertEqual(MedicationPattern.dayCount(logs, now: now, calendar: calendar), 3)
    }

    func test_hasLogToday_false_without_a_log_today() {
        XCTAssertFalse(MedicationPattern.hasLogToday([], now: now, calendar: calendar))
        XCTAssertFalse(MedicationPattern.hasLogToday(steadyMorningRoutine(), now: now, calendar: calendar))
        XCTAssertFalse(MedicationPattern.hasLogToday(
            [instant(-1, hour: 23, minute: 59)], now: now, calendar: calendar
        ), "last night at 23:59 is not today")
    }

    func test_hasLogToday_true_for_a_log_later_today() {
        // A back-dated / future-in-the-day entry is still today's dose.
        XCTAssertTrue(MedicationPattern.hasLogToday([instant(0, hour: 21)], now: now, calendar: calendar))
    }

    // MARK: - nextFireDate

    func test_nextFireDate_nil_without_usable_history() {
        XCTAssertNil(MedicationPattern.nextFireDate([], now: now, calendar: calendar))
        XCTAssertNil(MedicationPattern.nextFireDate([instant(0, hour: 7)], now: now, calendar: calendar))
        XCTAssertNil(MedicationPattern.nextFireDate([instant(-40, hour: 7)], now: now, calendar: calendar))
    }

    func test_nextFireDate_schedules_from_one_day_of_history() {
        // The scheduling threshold is deliberately lower than the display
        // threshold: we won't claim "you usually take this at 8:09" on one
        // sample, but we will quietly try a nudge.
        let oneDay = [instant(-1, hour: 8, minute: 9)]
        XCTAssertEqual(MedicationPattern.dayCount(oneDay, now: now, calendar: calendar), 1)
        XCTAssertFalse(MedicationPattern.hasDisplayablePattern(oneDay, now: now, calendar: calendar))

        let result = MedicationPattern.nextFireDate(oneDay, now: now, calendar: calendar)
        XCTAssertNotNil(result, "one day of history must still be enough to schedule")
        XCTAssertEqual(result, instant(0, hour: 8, minute: 39))
    }

    func test_nextFireDate_today_at_typical_time_plus_grace_when_nothing_logged_yet() throws {
        // Typical 08:09 + 30 minutes of grace = 08:39, still ahead of 08:00.
        let result = try XCTUnwrap(
            MedicationPattern.nextFireDate(steadyMorningRoutine(), now: now, calendar: calendar)
        )
        XCTAssertEqual(result, instant(0, hour: 8, minute: 39))
        XCTAssertGreaterThan(result, now)
    }

    func test_nextFireDate_rolls_to_tomorrow_once_a_log_exists_today() {
        // This is the whole mechanism by which logging cancels the nudge: the
        // same history, plus one dose taken today, moves the fire instant out of
        // today entirely.
        let logs = steadyMorningRoutine() + [instant(0, hour: 7, minute: 15)]
        XCTAssertTrue(MedicationPattern.hasLogToday(logs, now: now, calendar: calendar))
        XCTAssertEqual(MedicationPattern.nextFireDate(logs, now: now, calendar: calendar),
                       instant(1, hour: 8, minute: 39))
    }

    func test_nextFireDate_rolls_to_tomorrow_when_todays_instant_already_passed() throws {
        // Typical 06:05 + 30 = 06:35, which went by two hours ago.
        let result = try XCTUnwrap(
            MedicationPattern.nextFireDate(earlyMorningRoutine(), now: now, calendar: calendar)
        )
        XCTAssertEqual(result, instant(1, hour: 6, minute: 35))
        XCTAssertGreaterThan(result, now)
    }

    func test_nextFireDate_honours_a_custom_grace_period() throws {
        XCTAssertEqual(MedicationPattern.defaultGraceMinutes, 30)
        let logs = steadyMorningRoutine() // typical 08:09

        let noGrace = try XCTUnwrap(
            MedicationPattern.nextFireDate(logs, now: now, calendar: calendar, graceMinutes: 0)
        )
        let ninety = try XCTUnwrap(
            MedicationPattern.nextFireDate(logs, now: now, calendar: calendar, graceMinutes: 90)
        )
        XCTAssertEqual(noGrace, instant(0, hour: 8, minute: 9))
        XCTAssertEqual(ninety, instant(0, hour: 9, minute: 39))
        XCTAssertEqual(ninety.timeIntervalSince(noGrace), 90 * 60, accuracy: 0.001,
                       "grace must shift the fire instant by exactly the minutes given")
    }

    func test_nextFireDate_default_grace_matches_the_explicit_default() {
        let logs = steadyMorningRoutine()
        XCTAssertEqual(
            MedicationPattern.nextFireDate(logs, now: now, calendar: calendar),
            MedicationPattern.nextFireDate(logs, now: now, calendar: calendar,
                                           graceMinutes: MedicationPattern.defaultGraceMinutes)
        )
    }

    func test_nextFireDate_late_night_routine_crosses_midnight_onto_the_next_day() throws {
        // Typical 23:55 + 30 minutes of grace is 00:25 — which belongs to the
        // FOLLOWING day. A minute-of-day implementation that wraps with `% 1440`
        // and then stamps 00:25 onto today produces an instant eight hours in
        // the past, i.e. a notification that fires immediately or not at all.
        let lateRoutine = [instant(-3, hour: 23, minute: 55),
                           instant(-2, hour: 23, minute: 50),
                           instant(-1, hour: 23, minute: 58)]
        XCTAssertEqual(MedicationPattern.typicalMinuteOfDay(lateRoutine, now: now, calendar: calendar),
                       minutes(23, 55))

        let result = try XCTUnwrap(MedicationPattern.nextFireDate(lateRoutine, now: now, calendar: calendar))
        XCTAssertEqual(result, instant(1, hour: 0, minute: 25))
        XCTAssertNotEqual(result, instant(0, hour: 0, minute: 25), "the grace period wrapped instead of carrying")
        XCTAssertGreaterThan(result, now)
        XCTAssertEqual(calendar.startOfDay(for: result), day(1), "must land on the day after the 23:55 dose day")
    }

    func test_nextFireDate_keeps_wall_clock_time_across_a_dst_spring_forward() throws {
        // America/New_York springs forward at 02:00 on Sunday 2027-03-14, so
        // the day that starts on Saturday 2027-03-13 is only 23 real hours long.
        // A reminder is a wall-clock promise ("06:35"), not a duration promise
        // ("86,400 seconds from now") — only calendar component math gets this
        // right; adding 24 * 3600 lands the user at 07:35.
        func moment(_ dayOfMonth: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(from: DateComponents(
                year: 2027, month: 3, day: dayOfMonth, hour: hour, minute: minute
            ))!
        }

        let dstNow = moment(13, 8, 0)      // Saturday 2027-03-13 08:00 EST
        let history = [moment(10, 6, 0), moment(11, 6, 10), moment(12, 6, 5)] // median 06:05
        XCTAssertEqual(MedicationPattern.typicalMinuteOfDay(history, now: dstNow, calendar: calendar),
                       minutes(6, 5))

        // 06:35 today has already gone by at 08:00, so this rolls onto the
        // spring-forward day itself.
        let fire = try XCTUnwrap(
            MedicationPattern.nextFireDate(history, now: dstNow, calendar: calendar)
        )

        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        XCTAssertEqual(comps.year, 2027)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 14, "must land on the next calendar day")
        XCTAssertEqual(comps.hour, 6, "same wall-clock hour, not a fixed 24h offset")
        XCTAssertEqual(comps.minute, 35)

        // The proof that this is calendar math: the same wall-clock time on the
        // following day is 23 real hours later, not 24.
        XCTAssertEqual(fire.timeIntervalSince(moment(13, 6, 35)), 23 * 3_600, accuracy: 0.001)
        XCTAssertNotEqual(fire.timeIntervalSince(moment(13, 6, 35)), 24 * 3_600)
        XCTAssertGreaterThan(fire, dstNow)
    }

    func test_nextFireDate_unsorted_input_matches_sorted_input() {
        let sorted = steadyMorningRoutine()
        let scrambled = [sorted[2], sorted[0], sorted[1]]
        XCTAssertEqual(
            MedicationPattern.nextFireDate(scrambled, now: now, calendar: calendar),
            MedicationPattern.nextFireDate(sorted, now: now, calendar: calendar)
        )
        XCTAssertEqual(MedicationPattern.nextFireDate(scrambled, now: now, calendar: calendar),
                       instant(0, hour: 8, minute: 39))
    }

    // MARK: - Constants

    func test_constants_are_the_documented_values() {
        XCTAssertEqual(MedicationPattern.lookbackDays, 7)
        XCTAssertEqual(MedicationPattern.defaultGraceMinutes, 30)
        XCTAssertEqual(MedicationPattern.minDaysForDisplay, 2)
        XCTAssertLessThan(MedicationPattern.minDaysForDisplay, MedicationPattern.lookbackDays)
    }
}
