// Build-mode food library. Picky-eater friendly, nut-free, calorie-dense.
// Ported from nutrition-plan-research.md.

import Foundation

public enum SeedFoodsBuild {

    private static func costTier(_ c: Double) -> CostTier {
        c < 2 ? .low : (c < 4 ? .mid : .high)
    }

    private static func f(
        id: String, name: String, category: FoodCategory, recipe: String,
        cal: Int, p: Int, c: Int, ft: Int, fib: Int = 0,
        na: Int = 0, sug: Int = 0, sat: Int = 0,
        cost: Double, prep: Int = 5,
        allergens: [String] = [], ingredients: [String] = [],
        tags: [String] = [], appetiteFriendly: Bool = false
    ) -> FoodDTO {
        FoodDTO(
            id: id, name: name, modeFit: [.build], category: category,
            recipe: recipe,
            perServing: PerServing(
                calories: cal, proteinG: p, carbsG: c, fatG: ft,
                fiberG: fib, sodiumMg: na, addedSugarG: sug, saturatedFatG: sat
            ),
            costUsd: cost, costTier: costTier(cost), prepMinutes: prep,
            allergens: allergens, ingredients: ingredients, tags: tags,
            appetiteFriendly: appetiteFriendly
        )
    }

    public static let all: [FoodDTO] = [
        // Smoothies — the strongest weapon
        f(id: "build-smoothie-anchor", name: "The Anchor Smoothie", category: .smoothie,
          recipe: "1 cup milk + 1 scoop whey + banana + 1 cup frozen berries + 1 cup mango + 2 tbsp honey + ½ cup oats. Blend.",
          cal: 720, p: 38, c: 110, ft: 9, fib: 12, na: 180, sug: 24, sat: 3,
          cost: 2.10, prep: 4, allergens: ["dairy"],
          ingredients: ["milk","whey","banana","frozen-berries","mango","honey","oats"],
          tags: ["liquid","anchor","post-workout"], appetiteFriendly: true),

        f(id: "build-smoothie-chocolate-mango", name: "Chocolate Mango Lift", category: .smoothie,
          recipe: "1 cup chocolate milk + 1 scoop whey + frozen banana + 1 cup mango. Blend with ice.",
          cal: 540, p: 35, c: 80, ft: 7, fib: 6, na: 220, sug: 22, sat: 3,
          cost: 1.85, prep: 3, allergens: ["dairy"],
          ingredients: ["chocolate-milk","whey","banana","mango"],
          tags: ["liquid","post-workout"], appetiteFriendly: true),

        f(id: "build-smoothie-mass", name: "Mass Builder", category: .smoothie,
          recipe: "1.5 cups whole milk + 2 scoops whey + 1 cup oats + banana + 3 tbsp honey + 2 cups berries.",
          cal: 1050, p: 60, c: 145, ft: 14, fib: 18, na: 260, sug: 38, sat: 6,
          cost: 3.20, prep: 5, allergens: ["dairy"],
          ingredients: ["whole-milk","whey","oats","banana","honey","berries"],
          tags: ["liquid","emergency","high-calorie"], appetiteFriendly: true),

        f(id: "build-smoothie-bedtime", name: "Bedtime Casein-Style", category: .smoothie,
          recipe: "1 cup milk + 1 scoop whey + ½ cup oats + banana + 1 tbsp honey. Thick, slow-digesting.",
          cal: 520, p: 32, c: 75, ft: 8, fib: 8, na: 180, sug: 14, sat: 3,
          cost: 1.60, prep: 4, allergens: ["dairy"],
          ingredients: ["milk","whey","oats","banana","honey"],
          tags: ["liquid","bedtime"], appetiteFriendly: true),

        f(id: "build-smoothie-tropical", name: "Tropical Recovery", category: .smoothie,
          recipe: "1 cup OJ + 1 cup mango + banana + 1 scoop whey + ½ cup yogurt. Best 60min post-workout.",
          cal: 480, p: 28, c: 92, ft: 3, fib: 6, na: 120, sug: 18, sat: 1,
          cost: 2.40, prep: 3, allergens: ["dairy"],
          ingredients: ["orange-juice","mango","banana","whey","yogurt"],
          tags: ["liquid","post-workout","recovery"], appetiteFriendly: true),

        // Breakfast / post-workout
        f(id: "build-bf-spam-egg-rice", name: "Spam, Egg & Rice", category: .breakfast,
          recipe: "3 eggs scrambled + 3 slices fried spam + 1 cup rice + drizzle of soy.",
          cal: 780, p: 40, c: 65, ft: 38, fib: 2, na: 1800, sug: 0, sat: 13,
          cost: 2.20, prep: 12, allergens: ["eggs"],
          ingredients: ["eggs","spam","rice","soy-sauce"],
          tags: ["post-workout","hot"]),

        f(id: "build-bf-bagel-stack", name: "Bagel Stack", category: .breakfast,
          recipe: "1 everything bagel toasted + cream cheese + 2 fried eggs + 2 slices crispy spam.",
          cal: 720, p: 32, c: 75, ft: 32, fib: 3, na: 1500, sug: 4, sat: 12,
          cost: 2.50, prep: 10, allergens: ["gluten","dairy","eggs"],
          ingredients: ["bagel","cream-cheese","eggs","spam"],
          tags: ["post-workout"]),

        f(id: "build-bf-oatmeal-power", name: "Oatmeal Power Bowl", category: .breakfast,
          recipe: "1 cup oats in milk + banana + ½ cup berries + 2 tbsp honey + scoop whey stirred cold after.",
          cal: 640, p: 32, c: 105, ft: 11, fib: 11, na: 150, sug: 24, sat: 3,
          cost: 1.40, prep: 8, allergens: ["dairy"],
          ingredients: ["oats","milk","banana","berries","honey","whey"],
          tags: ["warm","breakfast"], appetiteFriendly: true),

        f(id: "build-bf-pancake-stack", name: "Pancake Stack + Eggs", category: .breakfast,
          recipe: "3 pancakes + butter + maple syrup + 3 scrambled eggs + glass chocolate milk.",
          cal: 890, p: 30, c: 115, ft: 32, fib: 3, na: 1100, sug: 38, sat: 12,
          cost: 2.10, prep: 15, allergens: ["gluten","dairy","eggs"],
          ingredients: ["pancake-mix","butter","maple-syrup","eggs","chocolate-milk"],
          tags: ["weekend"]),

        f(id: "build-bf-cereal-mega", name: "Cereal Mega Bowl", category: .breakfast,
          recipe: "2 cups cereal + 1.5 cups whole milk + sliced banana + 1 scoop whey mixed in milk first.",
          cal: 620, p: 35, c: 95, ft: 14, fib: 5, na: 480, sug: 18, sat: 6,
          cost: 1.50, prep: 3, allergens: ["gluten","dairy"],
          ingredients: ["cereal","whole-milk","banana","whey"],
          tags: ["quick"], appetiteFriendly: true),

        // Mains
        f(id: "build-main-katsu", name: "Chicken Katsu Rice Bowl", category: .main,
          recipe: "1 panko-fried cutlet + 1.5 cups rice + tonkatsu sauce + carrots/broccoli.",
          cal: 780, p: 45, c: 85, ft: 28, fib: 4, na: 920, sug: 8, sat: 7,
          cost: 3.80, prep: 25, allergens: ["gluten","eggs"],
          ingredients: ["chicken-cutlet","panko","rice","tonkatsu-sauce","broccoli"],
          tags: ["hot","protein"]),

        f(id: "build-main-spam-fried-rice", name: "Spam Fried Rice", category: .main,
          recipe: "2 cups rice + 4 oz diced spam + 2 eggs + frozen peas/carrots + soy + sesame oil.",
          cal: 820, p: 32, c: 92, ft: 36, fib: 3, na: 1600, sug: 2, sat: 11,
          cost: 2.40, prep: 15, allergens: ["eggs"],
          ingredients: ["rice","spam","eggs","peas","carrots","soy-sauce"],
          tags: ["hot"]),

        f(id: "build-main-salmon", name: "Salmon + Rice + Broccoli", category: .main,
          recipe: "5 oz pan-seared salmon + 1 cup rice + 1 cup roasted broccoli w/ olive oil.",
          cal: 680, p: 42, c: 55, ft: 32, fib: 5, na: 350, sug: 0, sat: 6,
          cost: 5.20, prep: 20, allergens: ["fish"],
          ingredients: ["salmon","rice","broccoli","olive-oil"],
          tags: ["omega-3","quality"]),

        f(id: "build-main-burger", name: "Burger + Fries", category: .main,
          recipe: "Smash burger (¼ lb beef) on bun w/ cheese + 1.5 cups oven fries + dipping sauce.",
          cal: 920, p: 40, c: 78, ft: 48, fib: 4, na: 1400, sug: 6, sat: 18,
          cost: 3.60, prep: 20, allergens: ["gluten","dairy"],
          ingredients: ["ground-beef","bun","cheese","fries"],
          tags: ["hot"]),

        f(id: "build-main-nuggets", name: "Chicken Nugget Combo", category: .main,
          recipe: "10 chicken nuggets + 1 cup fries + dipping sauces + glass chocolate milk.",
          cal: 780, p: 32, c: 72, ft: 38, fib: 3, na: 1500, sug: 18, sat: 10,
          cost: 3.10, prep: 15, allergens: ["gluten","dairy"],
          ingredients: ["chicken-nuggets","fries","chocolate-milk"],
          appetiteFriendly: true),

        f(id: "build-main-cup-noodles", name: "Cup Noodles Upgrade", category: .main,
          recipe: "1 cup noodles + crack egg in during cook + spam slices + sesame oil.",
          cal: 580, p: 22, c: 65, ft: 24, fib: 2, na: 1900, sug: 2, sat: 9,
          cost: 1.80, prep: 5, allergens: ["gluten","eggs"],
          ingredients: ["cup-noodles","egg","spam","sesame-oil"],
          tags: ["low-effort"], appetiteFriendly: true),

        f(id: "build-main-pizza", name: "Pizza Night", category: .main,
          recipe: "3 slices NY-style cheese pizza + side of fried cauliflower or pickles.",
          cal: 950, p: 38, c: 110, ft: 38, fib: 5, na: 2100, sug: 8, sat: 14,
          cost: 5.00, prep: 0, allergens: ["gluten","dairy"],
          ingredients: ["pizza"],
          tags: ["weekend"], appetiteFriendly: true),

        // Snacks
        f(id: "build-snack-popcorn-cm", name: "Popcorn + Chocolate Milk", category: .snack,
          recipe: "1 bag popcorn (light butter) + 12oz chocolate milk.",
          cal: 480, p: 14, c: 70, ft: 14, fib: 6, na: 580, sug: 22, sat: 5,
          cost: 1.20, prep: 5, allergens: ["dairy"],
          ingredients: ["popcorn","chocolate-milk"],
          tags: ["anchor"], appetiteFriendly: true),

        f(id: "build-snack-donut-cm", name: "Donut + Chocolate Milk", category: .snack,
          recipe: "1 glazed donut + 12oz chocolate milk. Treat that doubles as calories.",
          cal: 510, p: 12, c: 75, ft: 20, fib: 1, na: 380, sug: 32, sat: 8,
          cost: 2.20, prep: 1, allergens: ["gluten","dairy"],
          ingredients: ["donut","chocolate-milk"],
          tags: ["treat"], appetiteFriendly: true),

        f(id: "build-snack-bagel-jelly", name: "Bagel + Jelly", category: .snack,
          recipe: "1 bagel toasted w/ butter and jelly + glass of juice.",
          cal: 450, p: 10, c: 88, ft: 8, fib: 3, na: 480, sug: 26, sat: 3,
          cost: 1.40, prep: 5, allergens: ["gluten","dairy"],
          ingredients: ["bagel","butter","jelly"],
          tags: ["quick"], appetiteFriendly: true),
    ]
}
