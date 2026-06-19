import XCTest

final class FoodAffinityTests: XCTestCase {

    // Pinned mid-window "now" so day-window math is deterministic (CI rule:
    // never bare Date() in window/streak tests).
    private let end = ISO8601DateFormatter().date(from: "2026-05-24T12:00:00Z")!

    private func entry(_ date: String, foodId: String?) -> FoodLogEntryDTO {
        FoodLogEntryDTO(
            userId: UUID(), date: date, slot: .other, foodId: foodId,
            perServing: PerServing(calories: 100, proteinG: 5, carbsG: 10, fatG: 2)
        )
    }

    private func ingredientEntry(_ date: String, foodIds: [String]) -> FoodLogEntryDTO {
        let ings = foodIds.map {
            MealIngredient(foodId: $0, name: $0, servingLabel: "1", perServing: .zero)
        }
        return FoodLogEntryDTO(
            userId: UUID(), date: date, slot: .other,
            perServing: PerServing(calories: 100, proteinG: 5, carbsG: 10, fatG: 2),
            ingredients: ings
        )
    }

    func test_frequency_counts_foodIds_in_window() {
        let logs = [
            entry("2026-05-24", foodId: "chicken-breast"),
            entry("2026-05-23", foodId: "chicken-breast"),
            entry("2026-05-22", foodId: "rice-white"),
        ]
        let freq = FoodAffinity.frequencyByFoodId(logs, days: 30, end: end)
        XCTAssertEqual(freq["chicken-breast"], 2)
        XCTAssertEqual(freq["rice-white"], 1)
    }

    func test_frequency_ignores_logs_outside_window() {
        let logs = [
            entry("2026-05-24", foodId: "chicken-breast"),
            entry("2026-04-01", foodId: "chicken-breast"), // >30 days before end
        ]
        let freq = FoodAffinity.frequencyByFoodId(logs, days: 7, end: end)
        XCTAssertEqual(freq["chicken-breast"], 1)
    }

    func test_frequency_ignores_logs_without_foodId() {
        let logs = [entry("2026-05-24", foodId: nil), entry("2026-05-24", foodId: "egg")]
        let freq = FoodAffinity.frequencyByFoodId(logs, days: 30, end: end)
        XCTAssertNil(freq[""]) // nil ids dropped, not bucketed under empty string
        XCTAssertEqual(freq["egg"], 1)
    }

    func test_ingredient_foodIds_count() {
        let logs = [ingredientEntry("2026-05-24", foodIds: ["rice-white", "black-beans"])]
        let freq = FoodAffinity.frequencyByFoodId(logs, days: 30, end: end)
        XCTAssertEqual(freq["rice-white"], 1)
        XCTAssertEqual(freq["black-beans"], 1)
    }

    func test_mostLogged_orders_by_frequency_then_alpha() {
        let logs = [
            entry("2026-05-24", foodId: "banana"),
            entry("2026-05-23", foodId: "banana"),
            entry("2026-05-22", foodId: "banana"),
            entry("2026-05-24", foodId: "apple"),
            entry("2026-05-23", foodId: "apple"),
            entry("2026-05-22", foodId: "egg"),
        ]
        let top = FoodAffinity.mostLoggedIds(logs, days: 30, limit: 8, end: end)
        XCTAssertEqual(top, ["banana", "apple", "egg"])
    }

    func test_mostLogged_respects_limit() {
        let logs = [
            entry("2026-05-24", foodId: "a"), entry("2026-05-24", foodId: "b"),
            entry("2026-05-24", foodId: "c"),
        ]
        XCTAssertEqual(FoodAffinity.mostLoggedIds(logs, days: 30, limit: 2, end: end).count, 2)
    }
}
