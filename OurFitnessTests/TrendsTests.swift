import XCTest

final class TrendsTests: XCTestCase {

    private func body(_ date: String, _ w: Double) -> BodyMetricDTO {
        BodyMetricDTO(userId: UUID(), date: date, weightLb: w)
    }

    private func marker(_ date: String, _ kind: HealthMarkerKind, _ v: Double) -> HealthMarkerDTO {
        HealthMarkerDTO(userId: UUID(), date: date, kind: kind, value: v)
    }

    func test_rollingAverage_window_1_returns_input() {
        let pts = [Trends.Point(date: "a", value: 1), Trends.Point(date: "b", value: 3)]
        XCTAssertEqual(Trends.rollingAverage(pts, window: 1), pts)
    }

    func test_rollingAverage_window_3_averages_trailing() {
        let pts = [
            Trends.Point(date: "a", value: 10),
            Trends.Point(date: "b", value: 20),
            Trends.Point(date: "c", value: 30),
            Trends.Point(date: "d", value: 40),
        ]
        let out = Trends.rollingAverage(pts, window: 3)
        XCTAssertEqual(out.map(\.value), [10, 15, 20, 30])
    }

    func test_weeklyDelta_zero_with_one_point() {
        XCTAssertEqual(Trends.weeklyWeightDelta([body("2026-05-24", 130)]), 0)
    }

    func test_weeklyDelta_positive_when_gaining() {
        let data = [
            body("2026-05-10", 128),
            body("2026-05-17", 129),
            body("2026-05-24", 130),
        ]
        // 2 lb across 14 days = 1.0 lb/week
        XCTAssertEqual(Trends.weeklyWeightDelta(data, days: 14), 1.0, accuracy: 0.1)
    }

    func test_weeklyDelta_negative_when_losing() {
        let data = [
            body("2026-05-10", 220),
            body("2026-05-17", 218),
            body("2026-05-24", 216),
        ]
        XCTAssertEqual(Trends.weeklyWeightDelta(data, days: 14), -2.0, accuracy: 0.5)
    }

    func test_markerSeries_filters_and_sorts() {
        let data = [
            marker("2026-04-01", .ldl, 150),
            marker("2026-05-01", .hdl, 45),
            marker("2026-03-01", .ldl, 160),
        ]
        let s = Trends.markerSeries(data, kind: .ldl)
        XCTAssertEqual(s.map(\.value), [160, 150])
    }

    func test_weeksStalled_zero_with_one_point() {
        XCTAssertEqual(Trends.weeksStalled([marker("2026-05-01", .ldl, 150)], kind: .ldl), 0)
    }

    func test_weeksStalled_reports_weeks_since_last_drift() {
        let data = [
            marker("2026-01-01", .ldl, 145),
            marker("2026-02-15", .ldl, 130),   // drift > 5%
            marker("2026-03-15", .ldl, 131),
            marker("2026-04-15", .ldl, 132),
        ]
        XCTAssertGreaterThanOrEqual(Trends.weeksStalled(data, kind: .ldl), 8)
    }
}
