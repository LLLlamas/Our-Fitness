// Shared curated + USDA food search used by the food library and ingredient
// pickers. Curated `CommonFoods` matches (name or alias substring) come first;
// the offline USDA database broadens the results, with curated entries winning
// on name so duplicates never appear.

import Foundation

public enum FoodSearch {

    /// Curated matches followed by USDA results whose names aren't already
    /// covered by a curated food. The FTS5 query runs on the database's
    /// background queue, so this is safe to await from a SwiftUI `.task`.
    public static func combined(matching query: String) async -> [CommonFood] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let curated = CommonFoods.all.filter { food in
            food.name.lowercased().contains(q)
                || food.aliases.contains { $0.lowercased().contains(q) }
        }
        let curatedNames = Set(curated.map { $0.name.lowercased() })
        let usda = await SQLiteFoodDatabase.shared.searchAsync(query: q, limit: 40)
            .filter { !curatedNames.contains($0.name.lowercased()) }
            .map { $0.asCommonFood }
        return curated + usda
    }
}
