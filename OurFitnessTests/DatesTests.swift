import XCTest
@testable import OurFitness

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

    func test_formatTimeAgo_just_now() {
        XCTAssertEqual(Dates.formatTimeAgo(Date().addingTimeInterval(-1)), "just now")
    }

    func test_formatTimeAgo_minutes() {
        XCTAssertEqual(Dates.formatTimeAgo(Date().addingTimeInterval(-300)), "5m ago")
    }

    func test_formatTimeAgo_hours() {
        XCTAssertEqual(Dates.formatTimeAgo(Date().addingTimeInterval(-3 * 3600)), "3h ago")
    }
}
