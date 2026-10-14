import XCTest

final class DatesTests: XCTestCase {

    func test_dayKey_format() {
        let cal = Calendar(identifier: .gregorian)
        let comps = DateComponents(year: 2026, month: 5, day: 24, hour: 12)
        let date = cal.date(from: comps)!
        XCTAssertEqual(Dates.dayKey(date), "2026-05-24")
    }

    func test_lastNDays_returns_N_oldest_first() {
        let cal = Calendar(identifier: .gregorian)
        let end = cal.date(from: DateComponents(year: 2026, month: 5, day: 24, hour: 12))!
        let keys = Dates.lastNDays(7, end: end)
        XCTAssertEqual(keys.count, 7)
        XCTAssertEqual(keys.last, "2026-05-24")
        XCTAssertEqual(keys.first, "2026-05-18")
    }

    func test_daysBetween_positive_when_b_later() {
        XCTAssertEqual(Dates.daysBetween("2026-05-20", "2026-05-24"), 4)
    }

    func test_isTodayOrYesterday_uses_local_day_window() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 5, day: 24, hour: 12))!
        let yesterday = cal.date(from: DateComponents(year: 2026, month: 5, day: 23, hour: 1))!
        let older = cal.date(from: DateComponents(year: 2026, month: 5, day: 22, hour: 23))!
        let tomorrow = cal.date(from: DateComponents(year: 2026, month: 5, day: 25, hour: 0))!

        XCTAssertTrue(Dates.isTodayOrYesterday(now, now: now))
        XCTAssertTrue(Dates.isTodayOrYesterday(yesterday, now: now))
        XCTAssertFalse(Dates.isTodayOrYesterday(older, now: now))
        XCTAssertFalse(Dates.isTodayOrYesterday(tomorrow, now: now))
    }

    func test_formatTimeAgo_just_now() {
        XCTAssertEqual(Dates.formatTimeAgo(Date().addingTimeInterval(-1)), "just now")
    }

    func test_formatTimeAgo_minutes() {
        XCTAssertEqual(Dates.formatTimeAgo(Date().addingTimeInterval(-300)), "5m ago")
    }

    func test_formatTimeAgo_hours() {
        XCTAssertEqual(Dates.formatTimeAgo(Date().addingTimeInterval(-3 * 3600)), "3h ago")
    }

    // MARK: - ISO weeks

    private func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func test_startOfISOWeek_anchors_on_monday_midnight() {
        let start = Dates.startOfISOWeek(local(2026, 5, 27, 15))   // Wednesday
        XCTAssertEqual(Dates.dayKey(start), "2026-05-25")
        let comps = Calendar(identifier: .gregorian).dateComponents([.hour, .minute, .weekday], from: start)
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 0)
        XCTAssertEqual(comps.weekday, 2, "Monday — not Sunday, which Calendar.current would give in the US")
    }

    func test_startOfISOWeek_sunday_stays_in_the_week_that_began_monday() {
        XCTAssertEqual(Dates.dayKey(Dates.startOfISOWeek(local(2026, 5, 31, 23))), "2026-05-25")
        XCTAssertEqual(Dates.dayKey(Dates.startOfISOWeek(local(2026, 5, 25, 0))), "2026-05-25")
    }

    func test_startOfISOWeek_weeksAgo_steps_whole_weeks() {
        let wed = local(2026, 5, 27)
        XCTAssertEqual(Dates.dayKey(Dates.startOfISOWeek(wed, weeksAgo: 1)), "2026-05-18")
        XCTAssertEqual(Dates.dayKey(Dates.startOfISOWeek(wed, weeksAgo: 3)), "2026-05-04")
        XCTAssertEqual(Dates.dayKey(Dates.startOfISOWeek(wed, weeksAgo: -1)), "2026-06-01")
    }
}
