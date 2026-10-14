import XCTest

/// `now` is pinned to a fixed mid-week instant everywhere — a bare `Date()` here
/// would make the window math pass or fail depending on the day the suite runs.
final class NutritionHistoryTests: XCTestCase {

    private let uid = UUID()
    private let iso = ISO8601DateFormatter()

    /// Wednesday.
    private var now: Date { iso.date(from: "2026-05-27T12:00:00Z")! }

    private func log(_ day: String, cal: Int = 400, name: String = "Meal") -> FoodLogEntryDTO {
        FoodLogEntryDTO(
            userId: uid, date: day, slot: .lunch, customName: name,
            perServing: PerServing(calories: cal, proteinG: 20, carbsG: 40, fatG: 10)
        )
    }

    // MARK: - autoWindow

    func test_autoWindow_is_zero_with_no_entries() {
        XCTAssertEqual(NutritionHistory.autoWindow([], end: now), 0)
    }

    func test_autoWindow_spans_oldest_entry_through_today_inclusive() {
        // 2026-05-25 → 2026-05-27 is 3 days counting both ends.
        let logs = [log("2026-05-25"), log("2026-05-27")]
        XCTAssertEqual(NutritionHistory.autoWindow(logs, end: now), 3)
    }

    func test_autoWindow_is_one_when_only_today_is_logged() {
        XCTAssertEqual(NutritionHistory.autoWindow([log("2026-05-27")], end: now), 1)
    }

    func test_autoWindow_respects_maxDays_cap() {
        let logs = [log("2025-01-01"), log("2026-05-27")]
        XCTAssertEqual(NutritionHistory.autoWindow(logs, maxDays: 30, end: now), 30)
    }

    func test_autoWindow_clamps_to_maxAutoWindow_without_an_explicit_cap() {
        // A log from 2020 would otherwise walk ~2,000 days.
        let logs = [log("2020-01-01"), log("2026-05-27")]
        XCTAssertEqual(NutritionHistory.autoWindow(logs, end: now),
                       NutritionHistory.maxAutoWindow)
    }

    // MARK: - loggedDays

    func test_loggedDays_is_empty_with_no_entries() {
        XCTAssertTrue(NutritionHistory.loggedDays([], end: now).isEmpty)
    }

    func test_loggedDays_returns_newest_first() {
        let logs = [log("2026-05-25"), log("2026-05-26"), log("2026-05-27")]
        let days = NutritionHistory.loggedDays(logs, end: now)
        XCTAssertEqual(days.map(\.id), ["2026-05-27", "2026-05-26", "2026-05-25"])
    }

    func test_loggedDays_drops_days_with_nothing_logged() {
        // 05-26 has no entry and must not appear as an empty row.
        let logs = [log("2026-05-25"), log("2026-05-27")]
        let days = NutritionHistory.loggedDays(logs, end: now)
        XCTAssertEqual(days.map(\.id), ["2026-05-27", "2026-05-25"])
    }

    func test_loggedDays_sums_several_entries_on_one_day() {
        let logs = [log("2026-05-27", cal: 400), log("2026-05-27", cal: 350)]
        let days = NutritionHistory.loggedDays(logs, end: now)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days.first?.totals.calories, 750)
    }

    func test_loggedDays_honours_maxDays_and_drops_older_days() {
        let logs = [log("2026-05-20"), log("2026-05-26"), log("2026-05-27")]
        // A 2-day window covers 05-26 and 05-27 only.
        let days = NutritionHistory.loggedDays(logs, maxDays: 2, end: now)
        XCTAssertEqual(days.map(\.id), ["2026-05-27", "2026-05-26"])
    }

    func test_loggedDays_agrees_with_daysLogged() {
        let logs = [log("2026-05-25"), log("2026-05-27"), log("2026-05-27")]
        let window = NutritionHistory.autoWindow(logs, end: now)
        XCTAssertEqual(NutritionHistory.loggedDays(logs, end: now).count,
                       NutritionHistory.daysLogged(logs, days: window, end: now))
    }
}
