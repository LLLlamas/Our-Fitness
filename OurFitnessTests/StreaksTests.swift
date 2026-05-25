import XCTest

final class StreaksTests: XCTestCase {

    private let target = 2500
    private let end = ISO8601DateFormatter().date(from: "2026-05-24T12:00:00Z")!

    private func entry(_ date: String, _ cal: Int) -> FoodLogEntryDTO {
        FoodLogEntryDTO(
            userId: UUID(), date: date, slot: .other,
            perServing: PerServing(calories: cal, proteinG: 0, carbsG: 0, fatG: 0)
        )
    }

    func test_dailyCalories_sums_per_day() {
        let logs = [
            entry("2026-05-24", 500),
            entry("2026-05-24", 700),
            entry("2026-05-23", 2000),
        ]
        let out = Streaks.dailyCalories(logs)
        XCTAssertEqual(out["2026-05-24"], 1200)
        XCTAssertEqual(out["2026-05-23"], 2000)
    }

    func test_currentStreak_zero_with_no_logs() {
        XCTAssertEqual(Streaks.currentStreak([], calorieTarget: target, endDate: end), 0)
    }

    func test_currentStreak_counts_consecutive_floors() {
        let logs = [
            entry("2026-05-22", 2100),
            entry("2026-05-23", 2300),
            entry("2026-05-24", 2400),
        ]
        XCTAssertEqual(Streaks.currentStreak(logs, calorieTarget: target, endDate: end), 3)
    }

    func test_currentStreak_preserves_when_today_not_yet_hit() {
        let logs = [
            entry("2026-05-22", 2100),
            entry("2026-05-23", 2300),
            entry("2026-05-24", 500),
        ]
        XCTAssertEqual(Streaks.currentStreak(logs, calorieTarget: target, endDate: end), 2)
    }

    func test_currentStreak_breaks_on_prior_miss() {
        let logs = [
            entry("2026-05-22", 1000),
            entry("2026-05-23", 2300),
            entry("2026-05-24", 2400),
        ]
        XCTAssertEqual(Streaks.currentStreak(logs, calorieTarget: target, endDate: end), 2)
    }

    func test_adherencePct_zero_with_no_logs() {
        XCTAssertEqual(Streaks.adherencePct([], calorieTarget: target, days: 14, endDate: end), 0)
    }

    func test_adherencePct_hits_over_window() {
        let logs = [
            entry("2026-05-24", 2200),
            entry("2026-05-23", 1000),
            entry("2026-05-22", 2200),
        ]
        XCTAssertEqual(
            Streaks.adherencePct(logs, calorieTarget: target, days: 7, endDate: end),
            2.0/7.0, accuracy: 0.01
        )
    }
}
