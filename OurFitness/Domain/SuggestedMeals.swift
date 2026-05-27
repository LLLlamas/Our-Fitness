// Curated meal suggestions shown in the Meals tab popup.
// Extracted from the stashed Build/Circuit food libraries for initial launch.
//
// TODO: Personalise this list based on the user's mode, history, and cuisine
// preferences. The current list is a general-purpose starting point. Future
// revision should bias toward the user's day-to-day cuisine patterns.

import Foundation

public struct SuggestedMeal: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let emoji: String
    public let description: String
    public let perServing: PerServing
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
            perServing: PerServing(calories: 720, proteinG: 38, carbsG: 110, fatG: 9, fiberG: 12)
        ),
        SuggestedMeal(
            id: "choco-mango-smoothie",
            name: "Chocolate Mango Lift",
            emoji: "🍫",
            description: "Chocolate milk, whey, frozen banana, mango. ~3 min.",
            perServing: PerServing(calories: 540, proteinG: 35, carbsG: 80, fatG: 7, fiberG: 6)
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
            perServing: PerServing(calories: 370, proteinG: 24, carbsG: 30, fatG: 18, fiberG: 4)
        ),
        SuggestedMeal(
            id: "greek-yogurt-berries",
            name: "Greek Yogurt & Berries",
            emoji: "🫐",
            description: "Full-fat Greek yogurt + mixed berries + a drizzle of honey.",
            perServing: PerServing(calories: 310, proteinG: 21, carbsG: 35, fatG: 11, fiberG: 4)
        ),
        SuggestedMeal(
            id: "oatmeal-pb-banana",
            name: "Oatmeal, Peanut Butter & Banana",
            emoji: "🌾",
            description: "Oatmeal cooked in milk + 1 tbsp peanut butter + banana.",
            perServing: PerServing(calories: 450, proteinG: 15, carbsG: 65, fatG: 14, fiberG: 8)
        ),
        SuggestedMeal(
            id: "pasta-chicken",
            name: "Pasta & Chicken",
            emoji: "🍝",
            description: "1.5 cups cooked pasta + 4 oz grilled chicken + marinara.",
            perServing: PerServing(calories: 520, proteinG: 48, carbsG: 60, fatG: 7, fiberG: 4)
        ),
        SuggestedMeal(
            id: "burrito-bowl",
            name: "Burrito Bowl",
            emoji: "🌯",
            description: "Rice, beans, chicken, salsa, avocado, cheese.",
            perServing: PerServing(calories: 680, proteinG: 45, carbsG: 70, fatG: 22, fiberG: 12)
        ),
    ]

    // MARK: - Circuit-mode meals (fiber-forward, lower calorie)

    private static let circuit: [SuggestedMeal] = [
        SuggestedMeal(
            id: "salmon-sweet-potato",
            name: "Salmon & Sweet Potato",
            emoji: "🐟",
            description: "4 oz baked salmon + 1 medium sweet potato + greens.",
            perServing: PerServing(calories: 340, proteinG: 34, carbsG: 28, fatG: 12, fiberG: 5)
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
            perServing: PerServing(calories: 380, proteinG: 30, carbsG: 30, fatG: 14, fiberG: 7)
        ),
    ]

    // MARK: - Shared / neutral

    private static let shared: [SuggestedMeal] = [
        SuggestedMeal(
            id: "banana-protein-shake",
            name: "Banana Protein Shake",
            emoji: "🍌",
            description: "1 scoop whey, 1 banana, 1 cup milk, handful of oats.",
            perServing: PerServing(calories: 420, proteinG: 33, carbsG: 55, fatG: 8, fiberG: 5)
        ),
        SuggestedMeal(
            id: "cottage-cheese-fruit",
            name: "Cottage Cheese & Fruit",
            emoji: "🍓",
            description: "½ cup cottage cheese + berries or pineapple chunks.",
            perServing: PerServing(calories: 170, proteinG: 14, carbsG: 20, fatG: 5, fiberG: 3)
        ),
        SuggestedMeal(
            id: "tacos-2",
            name: "Tacos (×2)",
            emoji: "🌮",
            description: "Two flour tortillas, seasoned beef or chicken, salsa, cheese.",
            perServing: PerServing(calories: 360, proteinG: 20, carbsG: 36, fatG: 16, fiberG: 4)
        ),
    ]

    // MARK: - Mode-filtered shortcut

    public static func suggestions(for mode: Mode) -> [SuggestedMeal] {
        switch mode {
        case .build:   return build + shared
        case .circuit: return circuit + shared
        }
    }
}
