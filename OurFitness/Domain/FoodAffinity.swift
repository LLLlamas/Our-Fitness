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

    // MARK: - Logged foods by id

    /// foodId → the most recent way this profile logged that food. `logs` must be
    /// NEWEST FIRST (`Repos.listFoodLog` order): the first hit per id wins and
    /// later hits are skipped. Ingredient foodIds count too, matching how
    /// `frequencyByFoodId` counts them. Numbers are as logged (ingredient
    /// quantity applied) — the watch's one-tap shortcuts replay exactly that.
    public static func loggedFoodIndex(
        _ logs: [FoodLogEntryDTO]
    ) -> [String: (name: String, perServing: PerServing)] {
        var out: [String: (name: String, perServing: PerServing)] = [:]
        for e in logs {
            if let ings = e.ingredients, !ings.isEmpty {
                for ing in ings {
                    guard let id = ing.foodId, out[id] == nil else { continue }
                    out[id] = (ing.name, ing.scaledPerServing)
                }
            } else if let id = e.foodId, out[id] == nil {
                out[id] = (e.customName ?? id, e.perServing)
            }
        }
        return out
    }

    /// The same lookup as loggable foods at ONE serving (ingredients keep their
    /// own `perServing` and serving label, not the quantity logged), newest
    /// log first like `loggedFoodIndex`. Lets a favorite that isn't in the
    /// curated list reopen from what the user logged.
    public static func loggedFoods(_ logs: [FoodLogEntryDTO]) -> [String: CommonFood] {
        func food(_ id: String, _ name: String, _ label: String, _ p: PerServing) -> CommonFood {
            CommonFood(id: id, name: name, aliases: [], servingLabel: label, calories: p.calories,
                       proteinG: p.proteinG, carbsG: p.carbsG, fatG: p.fatG, fiberG: p.fiberG)
        }
        var out: [String: CommonFood] = [:]
        for e in logs {
            if let ings = e.ingredients, !ings.isEmpty {
                for ing in ings {
                    guard let id = ing.foodId, out[id] == nil else { continue }
                    out[id] = food(id, ing.name, ing.servingLabel, ing.perServing)
                }
            } else if let id = e.foodId, out[id] == nil {
                out[id] = food(id, e.customName ?? id, "1 serving", e.perServing)
            }
        }
        return out
    }

    // MARK: - "My Foods" (Add food's empty state)

    public static let myFoodsFavoritesCap = 8
    public static let myFoodsRecentCap = 5
    public static let myFoodsMostLoggedCap = 5
    public static let myFoodsRecipesCap = 8

    public struct MyFoodsSections: Equatable, Sendable {
        /// A–Z.
        public var favorites: [CommonFood] = []
        /// Newest first; reopen at `repeatIngredients`.
        public var recent: [FoodLogEntryDTO] = []
        /// Most-logged foods over 30 days.
        public var mostLogged: [CommonFood] = []
        /// Saved templates (recipes and single foods the user saved), newest first.
        public var recipes: [SavedMealTemplateDTO] = []

        public var isEmpty: Bool { favorites.isEmpty && recent.isEmpty && mostLogged.isEmpty && recipes.isEmpty }
    }

    /// What one log entry IS, for "no food twice": its foodId — or its single
    /// ingredient's — else its lowercased name.
    static func identityKey(of entry: FoodLogEntryDTO) -> String {
        if let id = entry.foodId { return id }
        if let ings = entry.ingredients, ings.count == 1, let id = ings[0].foodId { return id }
        return "name:" + (entry.customName ?? entry.id.uuidString).lowercased()
    }

    static func identityKey(of template: SavedMealTemplateDTO) -> String {
        if template.ingredients.count == 1, let id = template.ingredients[0].foodId { return id }
        return "name:" + template.name.lowercased()
    }

    /// The four sections in screen order — Favorites, Recent, Most logged,
    /// Recipes & my foods — each capped, and each food shown ONCE on the whole
    /// screen (a later section skips what an earlier one already shows, then
    /// takes the next in line).
    /// - Parameters:
    ///   - favorites: already resolved (curated → own logs → database).
    ///   - logs: the profile's food log, NEWEST FIRST.
    ///   - templates: saved templates, NEWEST FIRST.
    ///   - resolve: foodId → loggable food, for the most-logged ids.
    public static func myFoodsSections(
        favorites: [CommonFood], logs: [FoodLogEntryDTO], templates: [SavedMealTemplateDTO],
        resolve: (String) -> CommonFood?, end: Date = Date()
    ) -> MyFoodsSections {
        var out = MyFoodsSections()
        var seen = Set<String>()

        for f in favorites.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        where out.favorites.count < myFoodsFavoritesCap && seen.insert(f.id).inserted {
            out.favorites.append(f)
        }
        for e in logs where out.recent.count < myFoodsRecentCap && seen.insert(identityKey(of: e)).inserted {
            out.recent.append(e)
        }
        for id in mostLoggedIds(logs, days: 30, limit: 100, end: end) where out.mostLogged.count < myFoodsMostLoggedCap {
            guard !seen.contains(id), let food = resolve(id) else { continue }
            seen.insert(id)
            out.mostLogged.append(food)
        }
        for t in templates where out.recipes.count < myFoodsRecipesCap && seen.insert(identityKey(of: t)).inserted {
            out.recipes.append(t)
        }
        return out
    }

    /// Saved templates whose NAME matches a typed query (`FoodSearchQuery.tier`:
    /// exact, starts-with, all words), best match first, newest first within a
    /// tier. `templates` arrive newest first.
    public static func matchingTemplates(_ templates: [SavedMealTemplateDTO], query: String) -> [SavedMealTemplateDTO] {
        let q = FoodSearchQuery(query)
        guard !q.isEmpty else { return [] }
        var hits: [(template: SavedMealTemplateDTO, tier: Int, order: Int)] = []
        for (i, t) in templates.enumerated() {
            if let tier = q.tier(name: t.name, aliases: []) { hits.append((t, tier, i)) }
        }
        hits.sort { $0.tier != $1.tier ? $0.tier < $1.tier : $0.order < $1.order }
        return hits.map { $0.template }
    }
}
