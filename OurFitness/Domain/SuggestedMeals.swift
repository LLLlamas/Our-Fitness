// Curated meal suggestions shown in the Meals tab.
// Personalised at call time: filtered by mode + allergen restrictions, then
// ranked by today's largest macro gap (protein-first vs calorie-dense first).
//
// TODO: bias toward the user's day-to-day cuisine patterns once enough log
// history exists. The curated catalog below stays as the fallback corpus.

import Foundation

public struct SuggestedMeal: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let emoji: String
    public let description: String
    public let perServing: PerServing
    /// Coarse allergen tags (lowercase). Matched against `ProfileDTO.restrictions`
    /// substring-style so "dairy" filters out "dairy-free" restrictions too.
    public let allergens: [String]

    public init(
        id: String, name: String, emoji: String, description: String,
        perServing: PerServing, allergens: [String] = []
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.description = description
        self.perServing = perServing
        self.allergens = allergens
    }
}

public enum SuggestedMeals {

    // MARK: - All suggestions (both modes)

    public static let all: [SuggestedMeal] = build + circuit + shared

    // MARK: - Build-mode meals (higher calorie, liquid-friendly)

    private static let build: [SuggestedMeal] = [
        SuggestedMeal(
            id: "anchor-smoothie",
            name: "The Anchor Smoothie",
            emoji: "🥤",
            description: "Milk, whey, banana, frozen berries, mango, honey, oats. ~4 min.",
            perServing: PerServing(calories: 720, proteinG: 38, carbsG: 110, fatG: 9, fiberG: 12),
            allergens: ["dairy", "gluten"]
        ),
        SuggestedMeal(
            id: "choco-mango-smoothie",
            name: "Chocolate Mango Lift",
            emoji: "🍫",
            description: "Chocolate milk, whey, frozen banana, mango. ~3 min.",
            perServing: PerServing(calories: 540, proteinG: 35, carbsG: 80, fatG: 7, fiberG: 6),
            allergens: ["dairy"]
        ),
        SuggestedMeal(
            id: "chicken-rice-bowl",
            name: "Chicken + Rice Bowl",
            emoji: "🍚",
            description: "Grilled chicken breast + steamed white rice + broccoli.",
            perServing: PerServing(calories: 450, proteinG: 42, carbsG: 50, fatG: 5, fiberG: 6)
        ),
        SuggestedMeal(
            id: "eggs-toast",
            name: "Scrambled Eggs & Toast",
            emoji: "🍳",
            description: "3 eggs scrambled in butter + 2 slices whole wheat toast.",
            perServing: PerServing(calories: 370, proteinG: 24, carbsG: 30, fatG: 18, fiberG: 4),
            allergens: ["egg", "dairy", "gluten"]
        ),
        SuggestedMeal(
            id: "greek-yogurt-berries",
            name: "Greek Yogurt & Berries",
            emoji: "🫐",
            description: "Full-fat Greek yogurt + mixed berries + a drizzle of honey.",
            perServing: PerServing(calories: 310, proteinG: 21, carbsG: 35, fatG: 11, fiberG: 4),
            allergens: ["dairy"]
        ),
        SuggestedMeal(
            id: "oatmeal-pb-banana",
            name: "Oatmeal, Peanut Butter & Banana",
            emoji: "🌾",
            description: "Oatmeal cooked in milk + 1 tbsp peanut butter + banana.",
            perServing: PerServing(calories: 450, proteinG: 15, carbsG: 65, fatG: 14, fiberG: 8),
            allergens: ["dairy", "peanut", "gluten"]
        ),
        SuggestedMeal(
            id: "pasta-chicken",
            name: "Pasta & Chicken",
            emoji: "🍝",
            description: "1.5 cups cooked pasta + 4 oz grilled chicken + marinara.",
            perServing: PerServing(calories: 520, proteinG: 48, carbsG: 60, fatG: 7, fiberG: 4),
            allergens: ["gluten"]
        ),
        SuggestedMeal(
            id: "burrito-bowl",
            name: "Burrito Bowl",
            emoji: "🌯",
            description: "Rice, beans, chicken, salsa, avocado, cheese.",
            perServing: PerServing(calories: 680, proteinG: 45, carbsG: 70, fatG: 22, fiberG: 12),
            allergens: ["dairy"]
        ),
    ]

    // MARK: - Circuit-mode meals (fiber-forward, lower calorie)

    private static let circuit: [SuggestedMeal] = [
        SuggestedMeal(
            id: "salmon-sweet-potato",
            name: "Salmon & Sweet Potato",
            emoji: "🐟",
            description: "4 oz baked salmon + 1 medium sweet potato + greens.",
            perServing: PerServing(calories: 340, proteinG: 34, carbsG: 28, fatG: 12, fiberG: 5),
            allergens: ["fish"]
        ),
        SuggestedMeal(
            id: "lentil-veggie-bowl",
            name: "Lentil Veggie Bowl",
            emoji: "🫘",
            description: "Cooked lentils + steamed broccoli + brown rice + olive oil.",
            perServing: PerServing(calories: 400, proteinG: 22, carbsG: 65, fatG: 6, fiberG: 18)
        ),
        SuggestedMeal(
            id: "turkey-quinoa",
            name: "Turkey & Quinoa Bowl",
            emoji: "🥙",
            description: "Ground turkey, quinoa, spinach, tomato, lemon.",
            perServing: PerServing(calories: 410, proteinG: 38, carbsG: 42, fatG: 11, fiberG: 6)
        ),
        SuggestedMeal(
            id: "tuna-salad-wrap",
            name: "Tuna Salad Wrap",
            emoji: "🌮",
            description: "Canned tuna, avocado, mixed greens, whole wheat tortilla.",
            perServing: PerServing(calories: 380, proteinG: 30, carbsG: 30, fatG: 14, fiberG: 7),
            allergens: ["fish", "gluten"]
        ),
    ]

    // MARK: - Shared / neutral

    private static let shared: [SuggestedMeal] = [
        SuggestedMeal(
            id: "banana-protein-shake",
            name: "Banana Protein Shake",
            emoji: "🍌",
            description: "1 scoop whey, 1 banana, 1 cup milk, handful of oats.",
            perServing: PerServing(calories: 420, proteinG: 33, carbsG: 55, fatG: 8, fiberG: 5),
            allergens: ["dairy"]
        ),
        SuggestedMeal(
            id: "cottage-cheese-fruit",
            name: "Cottage Cheese & Fruit",
            emoji: "🍓",
            description: "½ cup cottage cheese + berries or pineapple chunks.",
            perServing: PerServing(calories: 170, proteinG: 14, carbsG: 20, fatG: 5, fiberG: 3),
            allergens: ["dairy"]
        ),
        SuggestedMeal(
            id: "tacos-2",
            name: "Tacos (×2)",
            emoji: "🌮",
            description: "Two flour tortillas, seasoned beef or chicken, salsa, cheese.",
            perServing: PerServing(calories: 360, proteinG: 20, carbsG: 36, fatG: 16, fiberG: 4),
            allergens: ["dairy", "gluten"]
        ),
    ]

    // MARK: - Mode-filtered shortcut

    public static func suggestions(for mode: Mode) -> [SuggestedMeal] {
        switch mode {
        case .build:   return build + shared
        case .circuit: return circuit + shared
        }
    }

    // MARK: - Personalised ranking

    /// Returns up to 5 suggestions, filtered by the profile's mode + allergen
    /// restrictions and ranked against today's largest macro gap. When protein
    /// is the most under-target macro, high-protein options surface first; when
    /// calories are the biggest gap, calorie-dense options surface first.
    public static func ranked(
        for profile: ProfileDTO,
        totals: DailyTotals,
        limit: Int = 5
    ) -> [SuggestedMeal] {
        let pool = suggestions(for: profile.mode).filter { meal in
            !mealHasRestrictedAllergen(meal, restrictions: profile.restrictions)
        }

        let targets = profile.computedTargets
        let calorieGap = max(0, targets.calories - totals.calories)
        let proteinGap = max(0, targets.proteinG - totals.proteinG)
        // Normalise each gap as a fraction of its own target so they're comparable.
        let calorieGapPct = targets.calories > 0 ? Double(calorieGap) / Double(targets.calories) : 0
        let proteinGapPct = targets.proteinG > 0 ? Double(proteinGap) / Double(targets.proteinG) : 0

        let bias: RankBias
        if proteinGapPct == 0 && calorieGapPct == 0 {
            bias = .neutral
        } else if proteinGapPct >= calorieGapPct {
            bias = .protein
        } else {
            bias = .calorieDense
        }

        let sorted = pool.sorted { a, b in
            let sa = score(a, bias: bias)
            let sb = score(b, bias: bias)
            if sa != sb { return sa > sb }
            return a.name < b.name
        }
        return Array(sorted.prefix(limit))
    }

    private enum RankBias { case protein, calorieDense, neutral }

    private static func score(_ meal: SuggestedMeal, bias: RankBias) -> Double {
        switch bias {
        case .protein:
            // Protein-per-100kcal rewards lean options; raw protein breaks ties on density.
            let perCal = meal.perServing.calories > 0
                ? Double(meal.perServing.proteinG) / Double(meal.perServing.calories) * 100
                : 0
            return perCal * 10 + Double(meal.perServing.proteinG)
        case .calorieDense:
            return Double(meal.perServing.calories)
        case .neutral:
            return Double(meal.perServing.proteinG)
        }
    }

    private static func mealHasRestrictedAllergen(
        _ meal: SuggestedMeal, restrictions: [String]
    ) -> Bool {
        guard !restrictions.isEmpty, !meal.allergens.isEmpty else { return false }
        let normalisedRestrictions = restrictions.map { $0.lowercased() }
        return meal.allergens.contains { tag in
            normalisedRestrictions.contains { restriction in
                restriction.contains(tag) || tag.contains(restriction)
            }
        }
    }
}
