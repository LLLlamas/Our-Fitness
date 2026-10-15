import XCTest

// Pure Domain. `now` is pinned and a fixed America/New_York calendar is
// threaded through every call (never a bare Date() — CLAUDE.md CI rules).
//
// Date(timeIntervalSince1970: 1_780_488_000) is 2026-06-03 12:00:00 UTC =
// 2026-06-03 08:00 EDT, a Wednesday. Breakfast nudges for today (typical 07:30
// + 60 min grace = 08:30) are therefore still ahead of `now`.
final class MealLogPatternTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_780_488_000)

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }()

    private let user = UUID()

    /// Local instant `dayOffset` days from `now`'s day at hour:minute.
    private func at(_ dayOffset: Int, _ hour: Int, _ minute: Int, from base: Date? = nil) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: base ?? now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    /// A real-time log (filed under the day it was logged) unless `filedOn` says otherwise.
    private func entry(_ slot: Slot, at ts: Date, filedOn: Date? = nil) -> FoodLogEntryDTO {
        FoodLogEntryDTO(userId: user,
                        date: MealLogPattern.dayKey(filedOn ?? ts, calendar: calendar),
                        slot: slot,
                        perServing: PerServing(calories: 400, proteinG: 20, carbsG: 40, fatG: 15),
                        timestamp: ts)
    }

    private func minutes(_ h: Int, _ m: Int) -> Int { h * 60 + m }

    /// Breakfast on the 5 days before today at 07:20, 07:30, 07:30, 07:40, 09:55.
    private func breakfastRoutine(from base: Date? = nil) -> [FoodLogEntryDTO] {
        [(-1, 7, 20), (-2, 7, 30), (-3, 7, 30), (-4, 7, 40), (-5, 9, 55)].map {
            entry(.breakfast, at: at($0.0, $0.1, $0.2, from: base))
        }
    }

    // MARK: - Learning

    func test_typical_time_is_median_of_daily_first_logs() {
        XCTAssertEqual(MealLogPattern.typicalMinuteOfDay(breakfastRoutine(), slot: .breakfast,
                                                         now: now, calendar: calendar),
                       minutes(7, 30), "median ignores the 09:55 outlier")
    }

    func test_later_items_on_the_same_day_do_not_drag_the_time() {
        var logs = breakfastRoutine()
        logs += (1...5).map { entry(.breakfast, at: at(-$0, 10, 45)) }   // second item each day
        XCTAssertEqual(MealLogPattern.typicalMinuteOfDay(logs, slot: .breakfast, now: now, calendar: calendar),
                       minutes(7, 30))
    }

    func test_needs_min_days_before_trusting_a_slot() {
        let three = Array(breakfastRoutine().prefix(MealLogPattern.minDays - 1))
        XCTAssertNil(MealLogPattern.typicalMinuteOfDay(three, slot: .breakfast, now: now, calendar: calendar))
        XCTAssertTrue(MealLogPattern.plan(three, now: now, calendar: calendar).isEmpty,
                      "no fallback defaults — nothing is planned before history exists")
    }

    func test_today_and_out_of_window_logs_are_excluded() {
        var logs = Array(breakfastRoutine().prefix(3))
        logs.append(entry(.breakfast, at: at(0, 6, 0)))                              // today
        logs.append(entry(.breakfast, at: at(-(MealLogPattern.lookbackDays + 1), 7, 0))) // too old
        XCTAssertNil(MealLogPattern.typicalMinuteOfDay(logs, slot: .breakfast, now: now, calendar: calendar))
    }

    func test_backfilled_entries_do_not_teach_a_time() {
        // Yesterday's..5-days-ago dinner, all entered this morning at 07:00-ish
        // from the day strip: filed under the past day, logged on another.
        let backfilled = (1...5).map { entry(.dinner, at: at(0, 7, $0), filedOn: at(-$0, 12, 0)) }
        XCTAssertNil(MealLogPattern.typicalMinuteOfDay(backfilled, slot: .dinner, now: now, calendar: calendar))
    }

    func test_untracked_slots_are_never_learned() {
        let snacks = (1...6).map { entry(.snack, at: at(-$0, 15, 0)) }
        XCTAssertTrue(MealLogPattern.learnedTimes(snacks, now: now, calendar: calendar).isEmpty)
    }

    // MARK: - Planning

    func test_plan_covers_horizon_with_grace_and_wall_clock_times() {
        let plan = MealLogPattern.plan(breakfastRoutine(), now: now, calendar: calendar)
        XCTAssertEqual(plan.count, MealLogPattern.defaultHorizonDays)
        XCTAssertEqual(plan.map(\.fireDate), [at(0, 8, 30), at(1, 8, 30), at(2, 8, 30)])
        XCTAssertEqual(plan.first?.dayKey, MealLogPattern.dayKey(now, calendar: calendar))
        XCTAssertEqual(plan.first?.typicalMinuteOfDay, minutes(7, 30))
    }

    func test_slot_logged_today_is_not_nudged_today() {
        let logs = breakfastRoutine() + [entry(.breakfast, at: at(0, 7, 5))]
        let plan = MealLogPattern.plan(logs, now: now, calendar: calendar)
        XCTAssertEqual(plan.map(\.fireDate), [at(1, 8, 30), at(2, 8, 30)])
    }

    func test_backfilled_entry_for_today_still_counts_as_logged() {
        // Filed under today though stamped yesterday evening (pre-logged).
        let logs = breakfastRoutine() + [entry(.breakfast, at: at(-1, 21, 0), filedOn: now)]
        let plan = MealLogPattern.plan(logs, now: now, calendar: calendar)
        XCTAssertFalse(plan.contains { $0.dayKey == MealLogPattern.dayKey(now, calendar: calendar) })
    }

    func test_passed_fire_time_rolls_to_tomorrow() {
        let later = at(0, 9, 0)
        let plan = MealLogPattern.plan(breakfastRoutine(), now: later, calendar: calendar)
        XCTAssertEqual(plan.first?.fireDate, at(1, 8, 30))
    }

    func test_quiet_hours_drop_late_nudges() {
        let lateDinner = (1...5).map { entry(.dinner, at: at(-$0, 21, 30)) }   // 21:30 + 60 = 22:30
        XCTAssertEqual(MealLogPattern.learnedTimes(lateDinner, now: now, calendar: calendar).first?.minuteOfDay,
                       minutes(21, 30), "still learned — just not nudged")
        XCTAssertTrue(MealLogPattern.plan(lateDinner, now: now, calendar: calendar).isEmpty)
    }

    func test_plan_is_sorted_across_slots() {
        let lunch = (1...5).map { entry(.lunch, at: at(-$0, 12, 30)) }
        let plan = MealLogPattern.plan(breakfastRoutine() + lunch, now: now, calendar: calendar)
        XCTAssertEqual(plan.count, 6)
        XCTAssertEqual(plan.map(\.fireDate), plan.map(\.fireDate).sorted())
        XCTAssertEqual(plan.prefix(2).map(\.slot), [.breakfast, .lunch])
    }

    func test_plan_keeps_wall_clock_time_across_dst_spring_forward() {
        // America/New_York springs forward at 02:00 on Sunday 2027-03-14; the day
        // that starts Saturday 2027-03-13 is 23 real hours long.
        let dstNow = calendar.date(from: DateComponents(year: 2027, month: 3, day: 13, hour: 9, minute: 0))!
        let plan = MealLogPattern.plan(breakfastRoutine(from: dstNow), now: dstNow, calendar: calendar)

        // 08:30 Saturday already passed → Sunday (spring-forward day) and Monday.
        XCTAssertEqual(plan.count, 2)
        let sunday = plan[0].fireDate
        let comps = calendar.dateComponents([.month, .day, .hour, .minute], from: sunday)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 14)
        XCTAssertEqual(comps.hour, 8, "same wall-clock hour, not a fixed 24h offset")
        XCTAssertEqual(comps.minute, 30)
        let saturdayFire = calendar.date(from: DateComponents(year: 2027, month: 3, day: 13, hour: 8, minute: 30))!
        XCTAssertEqual(sunday.timeIntervalSince(saturdayFire), 23 * 3_600, accuracy: 0.001)
        XCTAssertEqual(plan[0].dayKey, "2027-03-14")
    }

    func test_history_learned_across_dst_keeps_clock_minutes() {
        // Five breakfasts at 07:30 local straddling the spring-forward; "now" is
        // the Tuesday after. Every one must read as 07:30, not 06:30/08:30.
        let tuesday = calendar.date(from: DateComponents(year: 2027, month: 3, day: 16, hour: 6, minute: 0))!
        let logs = (1...5).map { entry(.breakfast, at: at(-$0, 7, 30, from: tuesday)) }
        XCTAssertEqual(MealLogPattern.typicalMinuteOfDay(logs, slot: .breakfast, now: tuesday, calendar: calendar),
                       minutes(7, 30))
    }

    func test_day_key_matches_food_log_shape() {
        XCTAssertEqual(MealLogPattern.dayKey(now, calendar: calendar), "2026-06-03")
    }
}
