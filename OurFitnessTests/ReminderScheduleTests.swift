import XCTest

// Pure Domain. `now` is pinned (the project's standard fixed clock — never a
// bare Date() — see CLAUDE.md CI rules) and a fixed non-UTC calendar is
// threaded into every call so results never depend on the wall clock or the
// host machine's local time zone.
//
// Date(timeIntervalSince1970: 1_780_488_000) is exactly 2026-06-03 12:00:00 UTC,
// which is 2026-06-03 08:00:00 EDT in America/New_York — a Wednesday
// (mid-week), local hour 8, zero minutes/seconds. All "today" / "hour N is
// still ahead vs. already passed" reasoning below is relative to that local
// instant.
final class ReminderScheduleTests: XCTestCase {

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

    /// A fixed absolute local instant, for the DST and calendar-boundary cases
    /// below — those need specific dates (8 Mar, 1 Nov, 31 Dec) rather than
    /// offsets from the shared `now`. Still fully pinned: no wall clock anywhere.
    private func at(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.date(from: comps)!
    }

    // MARK: - nextDueDay

    func test_nextDueDay_uses_lastDone_when_present() {
        let createdAt = day(-60) // much earlier — must be ignored once lastDone exists
        let lastDone = day(-17)
        let due = ReminderSchedule.nextDueDay(
            lastDone: lastDone, createdAt: createdAt, intervalDays: 10, calendar: calendar
        )
        XCTAssertEqual(due, day(-7)) // lastDone + 10 days
    }

    func test_nextDueDay_falls_back_to_createdAt_when_lastDone_nil() {
        let createdAt = day(-6)
        let due = ReminderSchedule.nextDueDay(
            lastDone: nil, createdAt: createdAt, intervalDays: 6, calendar: calendar
        )
        XCTAssertEqual(due, today) // createdAt + 6 days
    }

    func test_nextDueDay_snoozedUntil_before_natural_is_noop() {
        let lastDone = day(-20)
        let natural = ReminderSchedule.nextDueDay(
            lastDone: lastDone, createdAt: day(-400), intervalDays: 7, calendar: calendar
        )
        XCTAssertEqual(natural, day(-13))

        let staleSnooze = day(-15) // earlier than the natural due date
        let due = ReminderSchedule.nextDueDay(
            lastDone: lastDone, createdAt: day(-400), intervalDays: 7,
            snoozedUntil: staleSnooze, calendar: calendar
        )
        XCTAssertEqual(due, natural, "a snooze before the natural due date must not pull it earlier")
    }

    func test_nextDueDay_snoozedUntil_after_natural_wins() {
        let lastDone = day(-20) // natural due date lands on day(-13)
        let snoozedUntil = day(3)
        let due = ReminderSchedule.nextDueDay(
            lastDone: lastDone, createdAt: day(-400), intervalDays: 7,
            snoozedUntil: snoozedUntil, calendar: calendar
        )
        XCTAssertEqual(due, day(3))
    }

    func test_nextDueDay_day_boundary_shifts_by_one_calendar_day_not_24_hours() {
        // Two `lastDone` instants just 2 seconds apart in real time, straddling
        // local midnight — calendar-day semantics must treat them as a full
        // day apart, not as "basically the same moment".
        let justBeforeMidnight = instant(0, hour: 23, minute: 59, second: 59)
        let justAfterMidnight = instant(1, hour: 0, minute: 0, second: 1)
        XCTAssertEqual(justAfterMidnight.timeIntervalSince(justBeforeMidnight), 2, accuracy: 0.001)

        let earlierCreatedAt = day(-400)
        let dueA = ReminderSchedule.nextDueDay(
            lastDone: justBeforeMidnight, createdAt: earlierCreatedAt, intervalDays: 1, calendar: calendar
        )
        let dueB = ReminderSchedule.nextDueDay(
            lastDone: justAfterMidnight, createdAt: earlierCreatedAt, intervalDays: 1, calendar: calendar
        )
        XCTAssertEqual(dueA, day(1)) // startOfDay(today) + 1
        XCTAssertEqual(dueB, day(2)) // startOfDay(tomorrow) + 1
        XCTAssertEqual(calendar.dateComponents([.day], from: dueA, to: dueB).day, 1)
    }

    // MARK: - daysUntilDue / isDue / overdueDays

    func test_daysUntilDue_zero_when_due_today() {
        XCTAssertEqual(ReminderSchedule.daysUntilDue(dueDay: today, now: now, calendar: calendar), 0)
    }

    func test_daysUntilDue_negative_when_overdue() {
        XCTAssertEqual(ReminderSchedule.daysUntilDue(dueDay: day(-3), now: now, calendar: calendar), -3)
    }

    func test_daysUntilDue_positive_when_due_in_future() {
        XCTAssertEqual(ReminderSchedule.daysUntilDue(dueDay: day(5), now: now, calendar: calendar), 5)
    }

    func test_isDue_true_for_today_and_overdue() {
        XCTAssertTrue(ReminderSchedule.isDue(dueDay: today, now: now, calendar: calendar))
        XCTAssertTrue(ReminderSchedule.isDue(dueDay: day(-4), now: now, calendar: calendar))
    }

    func test_isDue_false_for_future() {
        XCTAssertFalse(ReminderSchedule.isDue(dueDay: day(1), now: now, calendar: calendar))
    }

    func test_overdueDays_zero_when_not_overdue() {
        XCTAssertEqual(ReminderSchedule.overdueDays(dueDay: today, now: now, calendar: calendar), 0)
        XCTAssertEqual(ReminderSchedule.overdueDays(dueDay: day(2), now: now, calendar: calendar), 0)
    }

    func test_overdueDays_correct_count_when_overdue() {
        XCTAssertEqual(ReminderSchedule.overdueDays(dueDay: day(-5), now: now, calendar: calendar), 5)
    }

    // MARK: - fireDate
    // `now`'s local hour is 8:00 exactly. Hour 20 is "still ahead today";
    // hours 6 and 8 (== now exactly) are "already passed / not strictly future".

    func test_fireDate_dueDay_today_hour_not_yet_passed_returns_due_day_at_hour() {
        let result = ReminderSchedule.fireDate(dueDay: today, preferredHour: 20, now: now, calendar: calendar)
        XCTAssertEqual(result, instant(0, hour: 20))
        XCTAssertGreaterThan(result, now)
    }

    func test_fireDate_future_dueDay_returns_that_day_at_hour() {
        let result = ReminderSchedule.fireDate(dueDay: day(3), preferredHour: 9, now: now, calendar: calendar)
        XCTAssertEqual(result, instant(3, hour: 9))
        XCTAssertGreaterThan(result, now)
    }

    func test_fireDate_overdue_rolls_to_today_when_preferredHour_still_ahead() {
        // 3 days overdue, but 20:00 hasn't happened yet today — floors to today at 20:00.
        let result = ReminderSchedule.fireDate(dueDay: day(-3), preferredHour: 20, now: now, calendar: calendar)
        XCTAssertEqual(result, instant(0, hour: 20))
        XCTAssertGreaterThan(result, now)
    }

    func test_fireDate_overdue_rolls_to_tomorrow_when_preferredHour_already_passed() {
        // 3 days overdue AND 06:00 already passed today — floors to tomorrow at 06:00.
        let result = ReminderSchedule.fireDate(dueDay: day(-3), preferredHour: 6, now: now, calendar: calendar)
        XCTAssertEqual(result, instant(1, hour: 6))
        XCTAssertGreaterThan(result, now)
    }

    func test_fireDate_dueToday_hour_already_elapsed_rolls_to_tomorrow() {
        let result = ReminderSchedule.fireDate(dueDay: today, preferredHour: 6, now: now, calendar: calendar)
        XCTAssertEqual(result, instant(1, hour: 6))
        XCTAssertGreaterThan(result, now)
    }

    func test_fireDate_preferredHour_exactly_equal_to_now_still_rolls_forward() {
        // due-day-at-hour lands exactly ON `now` — not strictly in the future,
        // so it must still roll forward rather than fire immediately.
        let result = ReminderSchedule.fireDate(dueDay: today, preferredHour: 8, now: now, calendar: calendar)
        XCTAssertEqual(result, instant(1, hour: 8))
        XCTAssertGreaterThan(result, now)
    }

    // MARK: - snoozeDate

    func test_snoozeDate_returns_tomorrow_at_preferredHour() {
        let result = ReminderSchedule.snoozeDate(now: now, preferredHour: 9, calendar: calendar)
        XCTAssertEqual(result, instant(1, hour: 9))
    }

    // MARK: - clampInterval
    // Pure integer logic — no clock involved, so nothing to pin here.

    func test_clampInterval_below_floor_raises_to_min() {
        XCTAssertEqual(ReminderSchedule.clampInterval(0), 1)
        XCTAssertEqual(ReminderSchedule.clampInterval(-1), 1)
        XCTAssertEqual(ReminderSchedule.clampInterval(-9_999), 1)
    }

    func test_clampInterval_at_bounds_is_unchanged() {
        XCTAssertEqual(ReminderSchedule.clampInterval(ReminderSchedule.minIntervalDays), 1)
        XCTAssertEqual(ReminderSchedule.clampInterval(ReminderSchedule.maxIntervalDays), 365)
    }

    func test_clampInterval_inside_range_is_unchanged() {
        XCTAssertEqual(ReminderSchedule.clampInterval(2), 2)
        XCTAssertEqual(ReminderSchedule.clampInterval(7), 7)
        XCTAssertEqual(ReminderSchedule.clampInterval(45), 45)
        XCTAssertEqual(ReminderSchedule.clampInterval(364), 364)
    }

    func test_clampInterval_above_ceiling_lowers_to_max() {
        XCTAssertEqual(ReminderSchedule.clampInterval(366), 365)
        XCTAssertEqual(ReminderSchedule.clampInterval(10_000), 365)
    }

    // MARK: - intervalLabel

    func test_intervalLabel_preset_days_return_preset_label() {
        XCTAssertEqual(ReminderSchedule.intervalLabel(days: 1), "Daily")
        XCTAssertEqual(ReminderSchedule.intervalLabel(days: 7), "Weekly")
        XCTAssertEqual(ReminderSchedule.intervalLabel(days: 14), "Every 2 weeks")
        XCTAssertEqual(ReminderSchedule.intervalLabel(days: 30), "Monthly")
        XCTAssertEqual(ReminderSchedule.intervalLabel(days: 365), "Yearly")
    }

    func test_intervalLabel_non_preset_days_fall_back_to_day_count() {
        XCTAssertEqual(ReminderSchedule.intervalLabel(days: 5), "Every 5 days")
        XCTAssertEqual(ReminderSchedule.intervalLabel(days: 45), "Every 45 days")
    }

    func test_intervalLabel_every_preset_resolves_to_its_own_label() {
        for preset in ReminderSchedule.intervalPresets {
            XCTAssertEqual(
                ReminderSchedule.intervalLabel(days: preset.days),
                preset.label,
                "interval \(preset.days) must render as its preset label"
            )
        }
    }

    /// Regression: hand-rolled "Every \(days) days" interpolation at each call
    /// site kept shipping the ungrammatical "Every 1 days". `intervalLabel`
    /// exists to be the single place that gets this right — a daily cadence
    /// must read "Daily". Named so the bug can't quietly return.
    func test_intervalLabel_one_day_is_not_the_Every_1_days_plural_bug() {
        let label = ReminderSchedule.intervalLabel(days: 1)
        XCTAssertNotEqual(label, "Every 1 days", "the 'Every 1 days' plural bug is back")
        XCTAssertEqual(label, "Daily")
    }

    // MARK: - intervalPresets integrity

    func test_intervalPresets_are_all_within_clamp_bounds() {
        for preset in ReminderSchedule.intervalPresets {
            XCTAssertGreaterThanOrEqual(preset.days, ReminderSchedule.minIntervalDays, "\(preset.label) is below the floor")
            XCTAssertLessThanOrEqual(preset.days, ReminderSchedule.maxIntervalDays, "\(preset.label) is above the ceiling")
            XCTAssertEqual(ReminderSchedule.clampInterval(preset.days), preset.days, "\(preset.label) must survive clamping unchanged")
        }
    }

    func test_intervalPresets_day_values_are_unique() {
        // `days` is the Identifiable id — a duplicate breaks SwiftUI ForEach.
        let days = ReminderSchedule.intervalPresets.map(\.days)
        XCTAssertEqual(Set(days).count, days.count, "duplicate preset day values: \(days)")
        let ids = ReminderSchedule.intervalPresets.map(\.id)
        XCTAssertEqual(ids, days, "id must be the day count")
    }

    func test_intervalPresets_labels_are_non_empty() {
        for preset in ReminderSchedule.intervalPresets {
            XCTAssertFalse(
                preset.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "preset \(preset.days) has an empty label"
            )
        }
    }

    func test_intervalPresets_are_sorted_ascending_by_days() {
        // Rendered in order as a pill row, so ordering is a real contract.
        let days = ReminderSchedule.intervalPresets.map(\.days)
        XCTAssertEqual(days, days.sorted(), "presets must be listed shortest cadence first")
        XCTAssertFalse(days.isEmpty)
    }

    // MARK: - dueLabel
    // The one place due status is worded, shared by the iOS and watch UIs
    // (ReminderSchedule compiles into both targets), so the strings are a
    // contract rather than cosmetics.

    func test_dueLabel_future_days_read_as_in_N_days() {
        XCTAssertEqual(ReminderSchedule.dueLabel(daysUntilDue: 1), "in 1 day")
        XCTAssertEqual(ReminderSchedule.dueLabel(daysUntilDue: 2), "in 2 days")
        XCTAssertEqual(ReminderSchedule.dueLabel(daysUntilDue: 30), "in 30 days")
    }

    func test_dueLabel_zero_is_due_today() {
        XCTAssertEqual(ReminderSchedule.dueLabel(daysUntilDue: 0), "Due today")
    }

    func test_dueLabel_negative_days_read_as_overdue_and_are_singular_at_one() {
        XCTAssertEqual(ReminderSchedule.dueLabel(daysUntilDue: -1), "1 day overdue")
        XCTAssertEqual(ReminderSchedule.dueLabel(daysUntilDue: -3), "3 days overdue")
    }

    func test_dueLabel_composes_with_daysUntilDue() {
        // The pairing both reminder lists actually use.
        XCTAssertEqual(
            ReminderSchedule.dueLabel(
                daysUntilDue: ReminderSchedule.daysUntilDue(dueDay: today, now: now, calendar: calendar)
            ),
            "Due today"
        )
        XCTAssertEqual(
            ReminderSchedule.dueLabel(
                daysUntilDue: ReminderSchedule.daysUntilDue(dueDay: day(-2), now: now, calendar: calendar)
            ),
            "2 days overdue"
        )
        XCTAssertEqual(
            ReminderSchedule.dueLabel(
                daysUntilDue: ReminderSchedule.daysUntilDue(dueDay: day(4), now: now, calendar: calendar)
            ),
            "in 4 days"
        )
    }

    // MARK: - Daylight saving time
    //
    // America/New_York 2026: DST starts Sun 8 Mar (02:00 EST -> 03:00 EDT, a
    // 23-hour day with no 2 AM) and ends Sun 1 Nov (02:00 EDT -> 01:00 EST, a
    // 25-hour day with two 1 AMs). This is the whole reason the file documents
    // calendar-day rather than 24-hour-multiple semantics, and none of it was
    // covered before.

    func test_nextDueDay_adds_a_calendar_day_not_24_hours_across_spring_forward() {
        let saturdayEvening = at(2026, 3, 7, hour: 20)
        let oneDay = ReminderSchedule.nextDueDay(
            lastDone: saturdayEvening, createdAt: saturdayEvening, intervalDays: 1, calendar: calendar
        )
        let twoDays = ReminderSchedule.nextDueDay(
            lastDone: saturdayEvening, createdAt: saturdayEvening, intervalDays: 2, calendar: calendar
        )
        XCTAssertEqual(oneDay, at(2026, 3, 8))
        XCTAssertEqual(twoDays, at(2026, 3, 9))
        // The lost hour means those two local midnights are 23 real hours
        // apart. Adding 86,400 seconds would have landed on 9 Mar 01:00.
        XCTAssertEqual(twoDays.timeIntervalSince(oneDay), 23 * 3600, accuracy: 0.001)
        XCTAssertEqual(calendar.component(.hour, from: twoDays), 0, "still local midnight, not 1 AM")
    }

    func test_nextDueDay_adds_a_calendar_day_not_24_hours_across_fall_back() {
        let eveningBefore = at(2026, 10, 31, hour: 20)
        let oneDay = ReminderSchedule.nextDueDay(
            lastDone: eveningBefore, createdAt: eveningBefore, intervalDays: 1, calendar: calendar
        )
        let twoDays = ReminderSchedule.nextDueDay(
            lastDone: eveningBefore, createdAt: eveningBefore, intervalDays: 2, calendar: calendar
        )
        XCTAssertEqual(oneDay, at(2026, 11, 1))
        XCTAssertEqual(twoDays, at(2026, 11, 2))
        // The repeated hour makes 1 Nov a 25-hour day.
        XCTAssertEqual(twoDays.timeIntervalSince(oneDay), 25 * 3600, accuracy: 0.001)
        XCTAssertEqual(calendar.component(.hour, from: twoDays), 0, "still local midnight, not 11 PM the day before")
    }

    func test_fireDate_keeps_the_wall_clock_hour_across_spring_forward() {
        let saturdayEvening = at(2026, 3, 7, hour: 20) // EST
        let result = ReminderSchedule.fireDate(
            dueDay: at(2026, 3, 8), preferredHour: 9, now: saturdayEvening, calendar: calendar
        )
        XCTAssertEqual(result, at(2026, 3, 8, hour: 9))
        XCTAssertEqual(calendar.component(.hour, from: result), 9, "9 AM means 9 AM, not 8 or 10")
        // 12 real hours, not 13: the clock skipped an hour overnight. A reminder
        // built by adding elapsed time would have fired an hour late.
        XCTAssertEqual(result.timeIntervalSince(saturdayEvening), 12 * 3600, accuracy: 0.001)
    }

    func test_fireDate_keeps_the_wall_clock_hour_across_fall_back() {
        let eveningBefore = at(2026, 10, 31, hour: 20) // EDT
        let result = ReminderSchedule.fireDate(
            dueDay: at(2026, 11, 1), preferredHour: 9, now: eveningBefore, calendar: calendar
        )
        XCTAssertEqual(result, at(2026, 11, 1, hour: 9))
        XCTAssertEqual(calendar.component(.hour, from: result), 9)
        // 14 real hours, not 13 — the extra 1 AM.
        XCTAssertEqual(result.timeIntervalSince(eveningBefore), 14 * 3600, accuracy: 0.001)
    }

    func test_fireDate_hour_that_does_not_exist_on_the_spring_forward_day_rolls_forward() {
        // 2 AM never happens on 8 Mar 2026. Documenting which way Foundation
        // resolves it matters: forward to 3 AM is a reminder slightly late,
        // backward to 1 AM would be one scheduled before its own due hour.
        let saturdayEvening = at(2026, 3, 7, hour: 20)
        let result = ReminderSchedule.fireDate(
            dueDay: at(2026, 3, 8), preferredHour: 2, now: saturdayEvening, calendar: calendar
        )
        XCTAssertEqual(calendar.component(.hour, from: result), 3, "the skipped hour resolves forward")
        XCTAssertEqual(calendar.component(.day, from: result), 8, "and stays on the due day")
        XCTAssertGreaterThan(result, saturdayEvening)
    }

    func test_fireDate_ambiguous_hour_on_the_fall_back_day_keeps_the_hour_and_stays_future() {
        // 1 AM happens twice on 1 Nov 2026. Which instant Foundation picks is
        // its business; what this feature needs is that the hour is honoured
        // and the result is never in the past.
        let eveningBefore = at(2026, 10, 31, hour: 20)
        let result = ReminderSchedule.fireDate(
            dueDay: at(2026, 11, 1), preferredHour: 1, now: eveningBefore, calendar: calendar
        )
        XCTAssertEqual(calendar.component(.hour, from: result), 1)
        XCTAssertEqual(calendar.component(.day, from: result), 1)
        XCTAssertGreaterThan(result, eveningBefore)
    }

    func test_snoozeDate_keeps_the_preferred_hour_across_fall_back() {
        let eveningBefore = at(2026, 10, 31, hour: 20)
        let result = ReminderSchedule.snoozeDate(now: eveningBefore, preferredHour: 9, calendar: calendar)
        XCTAssertEqual(result, at(2026, 11, 1, hour: 9))
        XCTAssertEqual(calendar.component(.hour, from: result), 9, "snoozing into a DST change is still 9 AM")
    }

    func test_snoozeDate_keeps_the_preferred_hour_across_spring_forward() {
        let saturdayEvening = at(2026, 3, 7, hour: 20)
        let result = ReminderSchedule.snoozeDate(now: saturdayEvening, preferredHour: 9, calendar: calendar)
        XCTAssertEqual(result, at(2026, 3, 8, hour: 9))
        XCTAssertEqual(calendar.component(.hour, from: result), 9)
    }

    func test_daysUntilDue_counts_calendar_days_across_a_dst_change() {
        // 7 Mar 20:00 -> 9 Mar 00:00 is 50 real hours (one hour lost), which an
        // elapsed-time division would floor to 2 only by accident and would get
        // wrong in the other direction in November.
        XCTAssertEqual(
            ReminderSchedule.daysUntilDue(dueDay: at(2026, 3, 9), now: at(2026, 3, 7, hour: 20), calendar: calendar),
            2
        )
        XCTAssertEqual(
            ReminderSchedule.daysUntilDue(dueDay: at(2026, 11, 2), now: at(2026, 10, 31, hour: 20), calendar: calendar),
            2
        )
    }

    // MARK: - Month / year boundaries

    func test_nextDueDay_crosses_a_month_boundary() {
        let jan31 = at(2026, 1, 31, hour: 10)
        XCTAssertEqual(
            ReminderSchedule.nextDueDay(lastDone: jan31, createdAt: jan31, intervalDays: 1, calendar: calendar),
            at(2026, 2, 1)
        )
        // A "Monthly" preset off the 31st lands on 2 Mar in a non-leap year —
        // 30 days, not "the same date next month".
        XCTAssertEqual(
            ReminderSchedule.nextDueDay(lastDone: jan31, createdAt: jan31, intervalDays: 30, calendar: calendar),
            at(2026, 3, 2)
        )
    }

    func test_nextDueDay_crosses_a_year_boundary() {
        let dec31 = at(2026, 12, 31, hour: 10)
        XCTAssertEqual(
            ReminderSchedule.nextDueDay(lastDone: dec31, createdAt: dec31, intervalDays: 1, calendar: calendar),
            at(2027, 1, 1)
        )
        // The "Yearly" preset, at the maximum interval.
        XCTAssertEqual(
            ReminderSchedule.nextDueDay(
                lastDone: dec31, createdAt: dec31,
                intervalDays: ReminderSchedule.maxIntervalDays, calendar: calendar
            ),
            at(2027, 12, 31)
        )
    }

    func test_nextDueDay_crosses_a_leap_day() {
        let feb28 = at(2028, 2, 28, hour: 10) // 2028 is a leap year
        XCTAssertEqual(
            ReminderSchedule.nextDueDay(lastDone: feb28, createdAt: feb28, intervalDays: 1, calendar: calendar),
            at(2028, 2, 29),
            "29 Feb is a real day and must not be skipped"
        )
        XCTAssertEqual(
            ReminderSchedule.nextDueDay(lastDone: feb28, createdAt: feb28, intervalDays: 2, calendar: calendar),
            at(2028, 3, 1)
        )
    }

    func test_daysUntilDue_counts_across_a_year_boundary() {
        XCTAssertEqual(
            ReminderSchedule.daysUntilDue(
                dueDay: at(2027, 1, 2), now: at(2026, 12, 30, hour: 23), calendar: calendar
            ),
            3
        )
        XCTAssertEqual(
            ReminderSchedule.overdueDays(
                dueDay: at(2026, 12, 29), now: at(2027, 1, 1, hour: 8), calendar: calendar
            ),
            3
        )
    }

    func test_fireDate_rolls_across_a_month_boundary_when_the_hour_has_passed() {
        // Due 28 Feb, 06:00 already gone on the 28th -> 1 Mar at 06:00.
        let lateOnTheLastDayOfFebruary = at(2026, 2, 28, hour: 8)
        let result = ReminderSchedule.fireDate(
            dueDay: at(2026, 2, 28), preferredHour: 6,
            now: lateOnTheLastDayOfFebruary, calendar: calendar
        )
        XCTAssertEqual(result, at(2026, 3, 1, hour: 6))
        XCTAssertGreaterThan(result, lateOnTheLastDayOfFebruary)
    }
}
