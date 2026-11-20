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

    // MARK: - Logged foods + My Foods sections

    private let per = PerServing(calories: 100, proteinG: 5, carbsG: 10, fatG: 2)

    private func log(_ date: String, id: String?, name: String, cal: Int = 100, ingredientQty: Double? = nil) -> FoodLogEntryDTO {
        let p = PerServing(calories: cal, proteinG: 5, carbsG: 10, fatG: 2)
        if let q = ingredientQty {
            let ing = MealIngredient(foodId: id, name: name, servingLabel: "1 cup", quantity: q, perServing: p)
            return FoodLogEntryDTO(userId: UUID(), date: date, slot: .other, customName: name,
                                   perServing: ing.scaledPerServing, ingredients: [ing])
        }
        return FoodLogEntryDTO(userId: UUID(), date: date, slot: .other, foodId: id, customName: name, perServing: p)
    }

    private func food(_ id: String, _ name: String) -> CommonFood {
        CommonFood(id: id, name: name, aliases: [], servingLabel: "1 serving",
                   calories: 100, proteinG: 5, carbsG: 10, fatG: 2, fiberG: 0)
    }

    private func template(_ name: String, foodId: String? = nil, minutesAgo: Int) -> SavedMealTemplateDTO {
        SavedMealTemplateDTO(
            userId: UUID(), name: name, emoji: "🍽️",
            ingredients: [MealIngredient(foodId: foodId, name: name, servingLabel: "1", perServing: per)],
            createdAt: end.addingTimeInterval(Double(-minutesAgo) * 60))
    }

    func testLoggedFoodIndexKeepsLatest() {
        // Newest first: the FIRST hit per id wins, ingredient ids count, entries without an id are skipped.
        let logs = [
            log("2026-05-24", id: "oats", name: "Oats (new)", cal: 150),
            log("2026-05-23", id: "oats", name: "Oats (old)", cal: 90),
            log("2026-05-22", id: "rice", name: "Rice", cal: 200, ingredientQty: 2),
            log("2026-05-21", id: nil, name: "Mystery", cal: 50),
        ]
        let index = FoodAffinity.loggedFoodIndex(logs)
        XCTAssertEqual(Set(index.keys), ["oats", "rice"])
        XCTAssertEqual(index["oats"]?.name, "Oats (new)")
        XCTAssertEqual(index["oats"]?.perServing.calories, 150)
        XCTAssertEqual(index["rice"]?.perServing.calories, 400)   // as logged: 2 × 200

        // The loggable version is ONE serving, whatever quantity was logged.
        let foods = FoodAffinity.loggedFoods(logs)
        XCTAssertEqual(foods["rice"]?.calories, 200)
        XCTAssertEqual(foods["rice"]?.servingLabel, "1 cup")
        XCTAssertEqual(foods["oats"]?.name, "Oats (new)")
    }

    func testMyFoodsSectionsDedupeAndCap() {
        // 10 favorites (A–Z, capped at 8); the 2nd favorite also tops recents and most-logged.
        let favs = (0..<10).map { food("fav\($0)", "Fav \(Character(UnicodeScalar(65 + $0)!))") }
        var logs: [FoodLogEntryDTO] = []   // newest first
        logs.append(log("2026-05-24", id: nil, name: "Salad"))
        logs.append(log("2026-05-24", id: "fav1", name: "Fav B"))
        for i in 0..<7 { logs.append(log("2026-05-24", id: "r\(i)", name: "Recent \(i)")) }
        for _ in 0..<4 { logs.append(log("2026-05-23", id: "fav1", name: "Fav B")) }
        for i in 0..<7 { for _ in 0..<(7 - i) { logs.append(log("2026-05-22", id: "r\(i)", name: "Recent \(i)")) } }
        for _ in 0..<2 { logs.append(log("2026-05-21", id: "m", name: "Most")) }
        let known = Dictionary(uniqueKeysWithValues:
            (favs + (0..<7).map { food("r\($0)", "Recent \($0)") } + [food("m", "Most")]).map { ($0.id, $0) })

        let templates = [template("Salad", minutesAgo: 1),                 // same name as a recent log → skipped
                         template("Oats", foodId: "r0", minutesAgo: 2)]     // same food as a recent → skipped
            + (0..<9).map { template("Recipe \($0)", minutesAgo: 10 + $0) }

        let s = FoodAffinity.myFoodsSections(favorites: favs, logs: logs, templates: templates,
                                             resolve: { known[$0] }, end: end)

        XCTAssertEqual(s.favorites.map(\.name), (0..<8).map { "Fav \(Character(UnicodeScalar(65 + $0)!))" })   // A–Z, capped
        XCTAssertEqual(s.recent.count, 5)
        XCTAssertFalse(s.recent.contains { $0.foodId == "fav1" })                  // already a favorite
        XCTAssertEqual(s.recent.map(\.customName), ["Salad", "Recent 0", "Recent 1", "Recent 2", "Recent 3"])   // newest first, next in line fills in
        XCTAssertEqual(s.mostLogged.map(\.id), ["r4", "r5", "m", "r6"])            // by count then A–Z; fav1 and r0–r3 are shown above
        XCTAssertEqual(s.recipes.count, 8)                                          // capped
        XCTAssertEqual(s.recipes.first?.name, "Recipe 0")                           // newest first, duplicates skipped
        XCTAssertFalse(s.recipes.contains { $0.name == "Salad" || $0.name == "Oats" })

        // Nothing appears twice anywhere on the screen.
        let keys = s.favorites.map(\.id) + s.recent.map { FoodAffinity.identityKey(of: $0) }
            + s.mostLogged.map(\.id) + s.recipes.map { FoodAffinity.identityKey(of: $0) }
        XCTAssertEqual(keys.count, Set(keys).count)

        // A brand-new user has nothing.
        XCTAssertTrue(FoodAffinity.myFoodsSections(favorites: [], logs: [], templates: [], resolve: { _ in nil }, end: end).isEmpty)
    }

    func testSavedTemplatesMatchTypedNamesBestFirst() {
        let names = ["Protein pancakes", "Pancakes", "My pancake stack", "Oat bowl"]
        let t = names.enumerated().map { template($1, minutesAgo: $0) }   // newest first
        XCTAssertEqual(FoodAffinity.matchingTemplates(t, query: "pancakes").map(\.name),
                       ["Pancakes", "Protein pancakes", "My pancake stack"])      // exact, then all-words by recency
        XCTAssertEqual(FoodAffinity.matchingTemplates(t, query: "oat").map(\.name), ["Oat bowl"])
        XCTAssertTrue(FoodAffinity.matchingTemplates(t, query: "pizza").isEmpty)
        XCTAssertTrue(FoodAffinity.matchingTemplates(t, query: "  ").isEmpty)
    }

    func testSingleFoodTemplateKeepsTheMacrosEntered() {
        let uid = UUID()
        let p = PerServing(calories: 412, proteinG: 30, carbsG: 40, fatG: 14, fiberG: 3)
        let t = SavedMealTemplateDTO.singleFood(userId: uid, name: "Grandma's lasagna", perServing: p)
        XCTAssertEqual(t.userId, uid)
        XCTAssertEqual(t.ingredients.count, 1)
        XCTAssertNil(t.ingredients[0].foodId)
        XCTAssertEqual(t.ingredients[0].quantity, 1)
        XCTAssertEqual(t.totalPerServing, p)
    }
}
