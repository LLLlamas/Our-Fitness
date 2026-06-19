// Curated meal suggestions shown in the Meals tab.
// Personalised at call time: filtered by mode + allergen restrictions, then
// ranked by today's largest macro gap (protein-first vs calorie-dense first).
//
// TODO: bias toward the user's day-to-day cuisine patterns once enough log
// history exists. The curated catalog below stays as the fallback corpus.

import Foundation

public struct MealIngredientTemplate: Sendable {
    public var foodId: String
    public var quantity: Double
    public var customName: String?

    public init(foodId: String, quantity: Double, customName: String? = nil) {
        self.foodId = foodId
        self.quantity = quantity
        self.customName = customName
    }

    public func resolve() -> MealIngredient? {
        guard let food = CommonFoods.all.first(where: { $0.id == foodId }) else { return nil }
        var ingredient = MealIngredient.from(food, quantity: quantity)
        if let override = customName { ingredient.name = override }
        return ingredient
    }
}

public struct SuggestedMeal: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let emoji: String
    public let description: String
    public let perServing: PerServing
    /// Coarse allergen tags (lowercase). Matched against `ProfileDTO.restrictions`
    /// substring-style so "dairy" filters out "dairy-free" restrictions too.
    public let allergens: [String]
    /// Editable ingredient defaults resolved from `CommonFoods` at call time.
    /// Flexible (user-editable) — their macro sum need not equal `perServing`.
    public var ingredientTemplates: [MealIngredientTemplate] = []

    public init(
        id: String, name: String, emoji: String, description: String,
        perServing: PerServing, allergens: [String] = [],
        ingredientTemplates: [MealIngredientTemplate] = []
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.description = description
        self.perServing = perServing
        self.allergens = allergens
        self.ingredientTemplates = ingredientTemplates
    }

    public func resolvedIngredients() -> [MealIngredient] {
        ingredientTemplates.compactMap { $0.resolve() }
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
            allergens: ["dairy", "gluten"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "milk-whole", quantity: 1.0),
                MealIngredientTemplate(foodId: "protein-shake", quantity: 1.0, customName: "Whey protein"),
                MealIngredientTemplate(foodId: "banana", quantity: 1.0),
                MealIngredientTemplate(foodId: "berries", quantity: 1.0),
                MealIngredientTemplate(foodId: "oatmeal", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "choco-mango-smoothie",
            name: "Chocolate Mango Lift",
            emoji: "🍫",
            description: "Chocolate milk, whey, frozen banana, mango. ~3 min.",
            perServing: PerServing(calories: 540, proteinG: 35, carbsG: 80, fatG: 7, fiberG: 6),
            allergens: ["dairy"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "chocolate-milk", quantity: 1.0),
                MealIngredientTemplate(foodId: "protein-shake", quantity: 1.0, customName: "Whey protein"),
                MealIngredientTemplate(foodId: "banana", quantity: 1.0),
                MealIngredientTemplate(foodId: "mango", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "chicken-rice-bowl",
            name: "Chicken + Rice Bowl",
            emoji: "🍚",
            description: "Grilled chicken breast + steamed white rice + broccoli.",
            perServing: PerServing(calories: 450, proteinG: 42, carbsG: 50, fatG: 5, fiberG: 6),
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "chicken-breast", quantity: 1.0),
                MealIngredientTemplate(foodId: "rice-white", quantity: 1.0),
                MealIngredientTemplate(foodId: "broccoli", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "eggs-toast",
            name: "Scrambled Eggs & Toast",
            emoji: "🍳",
            description: "3 eggs scrambled in butter + 2 slices whole wheat toast.",
            perServing: PerServing(calories: 370, proteinG: 24, carbsG: 30, fatG: 18, fiberG: 4),
            allergens: ["egg", "dairy", "gluten"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "egg", quantity: 3.0),
                MealIngredientTemplate(foodId: "bread-wheat", quantity: 2.0, customName: "Whole wheat toast")
            ]
        ),
        SuggestedMeal(
            id: "greek-yogurt-berries",
            name: "Greek Yogurt & Berries",
            emoji: "🫐",
            description: "Full-fat Greek yogurt + mixed berries + a drizzle of honey.",
            perServing: PerServing(calories: 310, proteinG: 21, carbsG: 35, fatG: 11, fiberG: 4),
            allergens: ["dairy"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "greek-yogurt", quantity: 1.0),
                MealIngredientTemplate(foodId: "berries", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "oatmeal-pb-banana",
            name: "Oatmeal, Peanut Butter & Banana",
            emoji: "🌾",
            description: "Oatmeal cooked in milk + 1 tbsp peanut butter + banana.",
            perServing: PerServing(calories: 450, proteinG: 15, carbsG: 65, fatG: 14, fiberG: 8),
            allergens: ["dairy", "peanut", "gluten"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "oatmeal", quantity: 1.0),
                MealIngredientTemplate(foodId: "peanut-butter", quantity: 0.5),
                MealIngredientTemplate(foodId: "banana", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "pasta-chicken",
            name: "Pasta & Chicken",
            emoji: "🍝",
            description: "1.5 cups cooked pasta + 4 oz grilled chicken + marinara.",
            perServing: PerServing(calories: 520, proteinG: 48, carbsG: 60, fatG: 7, fiberG: 4),
            allergens: ["gluten"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "pasta", quantity: 1.5),
                MealIngredientTemplate(foodId: "chicken-breast", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "burrito-bowl",
            name: "Burrito Bowl",
            emoji: "🌯",
            description: "Rice, beans, chicken, salsa, avocado, cheese.",
            perServing: PerServing(calories: 680, proteinG: 45, carbsG: 70, fatG: 22, fiberG: 12),
            allergens: ["dairy"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "rice-white", quantity: 1.0),
                MealIngredientTemplate(foodId: "black-beans", quantity: 0.5),
                MealIngredientTemplate(foodId: "chicken-breast", quantity: 1.0),
                MealIngredientTemplate(foodId: "avocado", quantity: 1.0),
                MealIngredientTemplate(foodId: "cheese-cheddar", quantity: 1.0)
            ]
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
            allergens: ["fish"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "salmon", quantity: 1.0),
                MealIngredientTemplate(foodId: "sweet-potato", quantity: 1.0),
                MealIngredientTemplate(foodId: "salad", quantity: 1.0, customName: "Greens")
            ]
        ),
        SuggestedMeal(
            id: "lentil-veggie-bowl",
            name: "Lentil Veggie Bowl",
            emoji: "🫘",
            description: "Cooked lentils + steamed broccoli + brown rice + olive oil.",
            perServing: PerServing(calories: 400, proteinG: 22, carbsG: 65, fatG: 6, fiberG: 18),
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "lentils", quantity: 1.0),
                MealIngredientTemplate(foodId: "broccoli", quantity: 1.0),
                MealIngredientTemplate(foodId: "rice-brown", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "turkey-quinoa",
            name: "Turkey & Quinoa Bowl",
            emoji: "🥙",
            description: "Ground turkey, quinoa, spinach, tomato, lemon.",
            perServing: PerServing(calories: 410, proteinG: 38, carbsG: 42, fatG: 11, fiberG: 6),
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "ground-turkey", quantity: 1.0),
                MealIngredientTemplate(foodId: "quinoa", quantity: 1.0),
                MealIngredientTemplate(foodId: "spinach", quantity: 1.0),
                MealIngredientTemplate(foodId: "tomato", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "tuna-salad-wrap",
            name: "Tuna Salad Wrap",
            emoji: "🌮",
            description: "Canned tuna, avocado, mixed greens, whole wheat tortilla.",
            perServing: PerServing(calories: 380, proteinG: 30, carbsG: 30, fatG: 14, fiberG: 7),
            allergens: ["fish", "gluten"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "tuna-canned", quantity: 1.0),
                MealIngredientTemplate(foodId: "avocado", quantity: 1.0),
                MealIngredientTemplate(foodId: "salad", quantity: 1.0, customName: "Mixed greens"),
                MealIngredientTemplate(foodId: "tortilla-flour", quantity: 1.0)
            ]
        ),
        // Cholesterol / BP / insulin-sensitivity targeted meals.
        // Mechanism citations live in descriptions so the rationale survives
        // any future ranking changes (descriptions surface in the Meals tab UI).
        SuggestedMeal(
            id: "circuit-berry-cottage-cheese",
            name: "Berry Cottage Cheese Bowl",
            emoji: "🍓",
            description: "½ cup cottage cheese + strawberries + blueberries. Lean protein and polyphenols shown to lower LDL oxidation.",
            perServing: PerServing(calories: 210, proteinG: 20, carbsG: 22, fatG: 5, fiberG: 5),
            allergens: ["dairy"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "cottage-cheese", quantity: 1.0),
                MealIngredientTemplate(foodId: "strawberries", quantity: 0.5),
                MealIngredientTemplate(foodId: "blueberries", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "circuit-oatmeal-blueberry",
            name: "Blueberry Oat Milk Oatmeal",
            emoji: "🫐",
            description: "Oats cooked in oat milk + blueberries + 1 date for sweetness. Beta-glucan from oats + oat milk reduces LDL 5–10% (FDA claim).",
            perServing: PerServing(calories: 270, proteinG: 8, carbsG: 53, fatG: 4, fiberG: 8),
            allergens: ["gluten"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "oatmeal", quantity: 1.0),
                MealIngredientTemplate(foodId: "oat-milk", quantity: 1.0),
                MealIngredientTemplate(foodId: "blueberries", quantity: 0.5),
                MealIngredientTemplate(foodId: "date-medjool", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "circuit-salmon-sushi",
            name: "Salmon Sushi Roll",
            emoji: "🍣",
            description: "1 salmon roll (8 pcs). EPA/DHA omega-3 reduces triglycerides 15–30%; AHA recommends 2× fatty fish/week.",
            perServing: PerServing(calories: 380, proteinG: 18, carbsG: 40, fatG: 14, fiberG: 2),
            allergens: ["fish"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "sushi-salmon-roll", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "circuit-zucchini-noodles-chicken",
            name: "Zucchini Noodles + Chicken Marinara",
            emoji: "🍅",
            description: "Spiralised zucchini + grilled chicken + tomato sauce. Lycopene from cooked tomatoes reduces LDL oxidation. Replaces pasta for lower glycemic load.",
            perServing: PerServing(calories: 250, proteinG: 38, carbsG: 12, fatG: 5, fiberG: 3),
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "zucchini", quantity: 1.0),
                MealIngredientTemplate(foodId: "chicken-breast", quantity: 1.0),
                MealIngredientTemplate(foodId: "tomato", quantity: 1.0, customName: "Tomato sauce")
            ]
        ),
        SuggestedMeal(
            id: "circuit-watermelon-cottage-cheese",
            name: "Watermelon Cottage Cheese Bowl",
            emoji: "🍉",
            description: "1 cup watermelon + ½ cup cottage cheese. Citrulline → nitric oxide → lower BP; protein from cottage cheese keeps it filling.",
            perServing: PerServing(calories: 156, proteinG: 14, carbsG: 17, fatG: 5, fiberG: 1),
            allergens: ["dairy"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "watermelon", quantity: 1.0),
                MealIngredientTemplate(foodId: "cottage-cheese", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "circuit-seaweed-salad",
            name: "Seaweed Salad + Cucumber",
            emoji: "🌿",
            description: "Seaweed salad + sliced cucumber + cherry tomatoes. Seaweed omega-3 ALAs and potassium from tomatoes/cucumber support BP reduction.",
            perServing: PerServing(calories: 90, proteinG: 3, carbsG: 12, fatG: 3, fiberG: 3),
            allergens: ["soy"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "seaweed-salad", quantity: 1.0),
                MealIngredientTemplate(foodId: "cucumber", quantity: 0.5),
                MealIngredientTemplate(foodId: "cherry-tomatoes", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "circuit-egg-veggie",
            name: "Egg & Veggie Scramble",
            emoji: "🍳",
            description: "2 eggs + diced tomatoes + zucchini. Lutein + lycopene are cardioprotective. ≤1 egg/day is safe for cardiovascular health per meta-analysis (BMJ 2020).",
            perServing: PerServing(calories: 180, proteinG: 15, carbsG: 8, fatG: 11, fiberG: 2),
            allergens: ["egg"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "egg", quantity: 2.0),
                MealIngredientTemplate(foodId: "tomato", quantity: 1.0),
                MealIngredientTemplate(foodId: "zucchini", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "circuit-berry-bowl",
            name: "Mixed Berry Bowl",
            emoji: "🍓",
            description: "Strawberries + raspberries + blueberries + plum. Anthocyanins lower LDL 2–4% and reduce blood pressure in 8-week RCTs.",
            perServing: PerServing(calories: 90, proteinG: 2, carbsG: 20, fatG: 1, fiberG: 6),
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "strawberries", quantity: 0.5),
                MealIngredientTemplate(foodId: "raspberries", quantity: 0.5),
                MealIngredientTemplate(foodId: "blueberries", quantity: 0.5),
                MealIngredientTemplate(foodId: "plum", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "circuit-miso-seaweed",
            name: "Miso Soup + Seaweed",
            emoji: "🍜",
            description: "Reduced-sodium miso soup + wakame. Soy isoflavones reduce LDL ~3–5%. Note: watch sodium if hypertensive.",
            perServing: PerServing(calories: 55, proteinG: 4, carbsG: 7, fatG: 1, fiberG: 1),
            allergens: ["soy"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "miso-soup", quantity: 1.0),
                MealIngredientTemplate(foodId: "seaweed-wakame", quantity: 0.5, customName: "Wakame")
            ]
        ),
        SuggestedMeal(
            id: "circuit-cucumber-tomato",
            name: "Cucumber Tomato Salad",
            emoji: "🥗",
            description: "Cucumber + cherry tomatoes + drizzle of olive oil. Potassium-rich: DASH diet staple proven to lower systolic BP 8–14 mmHg.",
            perServing: PerServing(calories: 75, proteinG: 2, carbsG: 11, fatG: 3, fiberG: 3),
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "cucumber", quantity: 1.0),
                MealIngredientTemplate(foodId: "cherry-tomatoes", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "circuit-chicken-soup",
            name: "Chicken Soup (Homemade)",
            emoji: "🍲",
            description: "Lean chicken + carrots + celery in low-sodium broth. High protein, anti-inflammatory, low saturated fat.",
            perServing: PerServing(calories: 150, proteinG: 20, carbsG: 8, fatG: 3, fiberG: 2),
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "chicken-breast", quantity: 1.0),
                MealIngredientTemplate(foodId: "celery", quantity: 1.0),
                MealIngredientTemplate(foodId: "onion", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "circuit-sushi-seaweed",
            name: "Sushi + Seaweed Salad",
            emoji: "🍱",
            description: "California roll + seaweed salad side. Omega-3 from fish/seaweed, nori fiber, low saturated fat.",
            perServing: PerServing(calories: 305, proteinG: 10, carbsG: 45, fatG: 9, fiberG: 4),
            allergens: ["fish", "soy"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "sushi-california-roll", quantity: 1.0),
                MealIngredientTemplate(foodId: "seaweed-salad", quantity: 1.0)
            ]
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
            allergens: ["dairy"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "protein-shake", quantity: 1.0, customName: "Whey protein"),
                MealIngredientTemplate(foodId: "banana", quantity: 1.0),
                MealIngredientTemplate(foodId: "milk-whole", quantity: 1.0),
                MealIngredientTemplate(foodId: "oatmeal", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "cottage-cheese-fruit",
            name: "Cottage Cheese & Fruit",
            emoji: "🍓",
            description: "½ cup cottage cheese + berries or pineapple chunks.",
            perServing: PerServing(calories: 170, proteinG: 14, carbsG: 20, fatG: 5, fiberG: 3),
            allergens: ["dairy"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "cottage-cheese", quantity: 1.0),
                MealIngredientTemplate(foodId: "berries", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "tacos-2",
            name: "Tacos (×2)",
            emoji: "🌮",
            description: "Two flour tortillas, seasoned beef or chicken, salsa, cheese.",
            perServing: PerServing(calories: 360, proteinG: 20, carbsG: 36, fatG: 16, fiberG: 4),
            allergens: ["dairy", "gluten"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "tortilla-flour", quantity: 2.0),
                MealIngredientTemplate(foodId: "ground-beef", quantity: 1.0),
                MealIngredientTemplate(foodId: "cheese-cheddar", quantity: 1.0)
            ]
        ),
    ]

    // MARK: - Composite food ingredient map
    //
    // Maps CommonFood IDs that represent multi-ingredient foods (smoothies, bowls)
    // to their constituent ingredient templates. Used by the food library to expand
    // a single composite food into a full ingredient-level breakdown when the user
    // taps it, so they can see and adjust banana, milk, protein separately.

    public static let compositeIngredients: [String: [MealIngredientTemplate]] = [
        "smoothie-banana-milk": [
            MealIngredientTemplate(foodId: "protein-shake", quantity: 1.0, customName: "Whey protein"),
            MealIngredientTemplate(foodId: "banana", quantity: 1.0),
            MealIngredientTemplate(foodId: "milk-whole", quantity: 1.0),
        ],
        "acai-bowl": [
            MealIngredientTemplate(foodId: "acai-bowl", quantity: 1.0),
        ],
        "burrito-bowl": [
            MealIngredientTemplate(foodId: "rice-white", quantity: 1.0),
            MealIngredientTemplate(foodId: "black-beans", quantity: 0.5),
            MealIngredientTemplate(foodId: "chicken-breast", quantity: 1.0),
            MealIngredientTemplate(foodId: "avocado", quantity: 1.0),
            MealIngredientTemplate(foodId: "cheese-cheddar", quantity: 1.0),
        ],
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
    ///
    /// Personalisation: pass `recentLogs` and/or `favoriteFoodIds` and meals built
    /// from foods the user already eats get a multiplicative boost — so the
    /// suggestions lean toward their taste without overriding a much stronger
    /// macro match. Both default empty, so the macro-only behaviour is preserved.
    public static func ranked(
        for profile: ProfileDTO,
        totals: DailyTotals,
        recentLogs: [FoodLogEntryDTO] = [],
        favoriteFoodIds: Set<String> = [],
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

        let loved = lovedFoodIds(recentLogs: recentLogs, favoriteFoodIds: favoriteFoodIds)
        let sorted = pool.sorted { a, b in
            let sa = score(a, bias: bias) * affinityMultiplier(a, loved: loved)
            let sb = score(b, bias: bias) * affinityMultiplier(b, loved: loved)
            if sa != sb { return sa > sb }
            // Affinity then name as deterministic tiebreakers.
            let aa = affinityCount(a, loved: loved)
            let ab = affinityCount(b, loved: loved)
            if aa != ab { return aa > ab }
            return a.name < b.name
        }
        return Array(sorted.prefix(limit))
    }

    /// True when a meal is built around at least one food the user already eats
    /// (favorite or frequently logged) — lets the UI tag it "Because you like…".
    public static func isPersonalised(
        _ meal: SuggestedMeal, recentLogs: [FoodLogEntryDTO], favoriteFoodIds: Set<String>
    ) -> Bool {
        affinityCount(meal, loved: lovedFoodIds(recentLogs: recentLogs, favoriteFoodIds: favoriteFoodIds)) > 0
    }

    /// Foods the user likes: explicit favorites ∪ their top recent most-logged.
    private static func lovedFoodIds(
        recentLogs: [FoodLogEntryDTO], favoriteFoodIds: Set<String>
    ) -> Set<String> {
        var s = favoriteFoodIds
        s.formUnion(FoodAffinity.mostLoggedIds(recentLogs, limit: 8))
        return s
    }

    /// Distinct loved ingredient foodIds present in a meal.
    private static func affinityCount(_ meal: SuggestedMeal, loved: Set<String>) -> Int {
        guard !loved.isEmpty else { return 0 }
        var seen = Set<String>()
        for t in meal.ingredientTemplates where loved.contains(t.foodId) { seen.insert(t.foodId) }
        return seen.count
    }

    /// Each loved ingredient lifts a meal's score by 15%, capped at +60%.
    /// Multiplicative so it scales with whichever macro bias is active.
    private static func affinityMultiplier(_ meal: SuggestedMeal, loved: Set<String>) -> Double {
        1.0 + min(0.6, 0.15 * Double(affinityCount(meal, loved: loved)))
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
