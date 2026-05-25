import XCTest

final class StepsTests: XCTestCase {

    private let end = ISO8601DateFormatter().date(from: "2026-05-24T12:00:00Z")!

    private func rec(_ date: String, _ s: Int) -> StepCountDTO {
        StepCountDTO(userId: UUID(), date: date, steps: s)
    }

    func test_stepsForDay_zero_when_missing() {
        XCTAssertEqual(Steps.stepsForDay([], day: "2026-05-24"), 0)
    }

    func test_stepsForDay_returns_value() {
        XCTAssertEqual(Steps.stepsForDay([rec("2026-05-24", 8500)], day: "2026-05-24"), 8500)
    }

    func test_average_missing_days_count_as_zero() {
        let avg = Steps.average([rec("2026-05-24", 7000)], days: 7, end: end)
        XCTAssertEqual(avg, 1000)
    }

    func test_average_across_window() {
        let data = [
            rec("2026-05-20", 10_000),
            rec("2026-05-22", 8_000),
            rec("2026-05-24", 12_000),
        ]
        XCTAssertEqual(Steps.average(data, days: 7, end: end), 4286)
    }

    func test_hitRate_zero_with_no_data() {
        XCTAssertEqual(Steps.hitRate([], goal: 10_000, days: 14, end: end), 0)
    }

    func test_hitRate_counts_window_hits() {
        let data = [
            rec("2026-05-24", 10_000),
            rec("2026-05-23",  9_000),
            rec("2026-05-22", 11_000),
        ]
        XCTAssertEqual(Steps.hitRate(data, goal: 10_000, days: 7, end: end), 2.0/7.0, accuracy: 0.01)
    }

    func test_series_dense_oldest_first() {
        let s = Steps.series([rec("2026-05-24", 5000)], days: 3, end: end)
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.last?.value, 5000)
        XCTAssertEqual(s.first?.value, 0)
    }
}
