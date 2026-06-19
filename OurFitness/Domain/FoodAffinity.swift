// Personalised food affinity — which curated foods the user actually logs most.
// Pure Domain (no SwiftData/SwiftUI). Feeds SuggestedMeals ranking so the meals
// surfaced lean toward what this person already eats, and powers any
// "you keep logging X" surfaces.
//
// Only foods with a stable `foodId` count — free-text / AI meals without one have
// no identity to learn from. Ingredient-level foodIds count too, so a composite
// meal teaches the recommender about its parts.

import Foundation

public enum FoodAffinity {

    /// Log frequency per `foodId` over the last `days` (ending `end`), counting
    /// ingredient foodIds when an entry is ingredient-based.
    public static func frequencyByFoodId(
        _ logs: [FoodLogEntryDTO], days: Int = 30, end: Date = Date()
    ) -> [String: Int] {
        let window = Set(Dates.lastNDays(days, end: end))
        var out: [String: Int] = [:]
        for e in logs {
            guard window.contains(e.date) else { continue }
            if let ings = e.ingredients, !ings.isEmpty {
                for ing in ings { if let id = ing.foodId { out[id, default: 0] += 1 } }
            } else if let id = e.foodId {
                out[id, default: 0] += 1
            }
        }
        return out
    }

    /// Top `limit` most-logged `foodId`s in the window, most-frequent first.
    /// Ties broken alphabetically so ordering is deterministic (and test-stable).
    public static func mostLoggedIds(
        _ logs: [FoodLogEntryDTO], days: Int = 30, limit: Int = 8, end: Date = Date()
    ) -> [String] {
        frequencyByFoodId(logs, days: days, end: end)
            .sorted { a, b in a.value != b.value ? a.value > b.value : a.key < b.key }
            .prefix(limit)
            .map(\.key)
    }
}
