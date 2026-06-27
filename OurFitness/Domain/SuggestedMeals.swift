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
        SuggestedMeal(
            id: "steak-burrito-bowl-loaded",
            name: "Loaded Steak Burrito Bowl",
            emoji: "🌯",
            description: "Seared steak, rice, black beans, corn, guac & salsa. Smoky Tex-Mex. ~15 min.",
            perServing: PerServing(calories: 780, proteinG: 48, carbsG: 72, fatG: 30, fiberG: 14),
            allergens: [],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "steak", quantity: 1.0),
                MealIngredientTemplate(foodId: "rice-white", quantity: 1.0),
                MealIngredientTemplate(foodId: "black-beans", quantity: 1.0),
                MealIngredientTemplate(foodId: "corn-kernels", quantity: 0.5),
                MealIngredientTemplate(foodId: "guacamole-homemade", quantity: 1.0),
                MealIngredientTemplate(foodId: "salsa-jar", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "beef-bolognese-pasta",
            name: "Beef Bolognese Pasta",
            emoji: "🍝",
            description: "Hearty pasta in beefy marinara, showered with parmesan. Italian comfort. ~20 min.",
            perServing: PerServing(calories: 720, proteinG: 42, carbsG: 78, fatG: 26, fiberG: 8),
            allergens: ["dairy", "gluten"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "pasta", quantity: 1.0),
                MealIngredientTemplate(foodId: "ground-beef", quantity: 1.0),
                MealIngredientTemplate(foodId: "marinara-sauce", quantity: 1.0),
                MealIngredientTemplate(foodId: "parmesan", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "teriyaki-salmon-rice-bowl",
            name: "Teriyaki Salmon Rice Bowl",
            emoji: "🍣",
            description: "Glazed salmon over sticky rice with edamame & bok choy. Umami-rich. ~18 min.",
            perServing: PerServing(calories: 650, proteinG: 44, carbsG: 62, fatG: 22, fiberG: 7),
            allergens: ["gluten", "soy", "fish"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "salmon", quantity: 1.0),
                MealIngredientTemplate(foodId: "sticky-rice", quantity: 1.0),
                MealIngredientTemplate(foodId: "edamame", quantity: 0.5),
                MealIngredientTemplate(foodId: "bok-choy", quantity: 1.0),
                MealIngredientTemplate(foodId: "teriyaki-sauce", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "butter-chicken-naan-plate",
            name: "Butter Chicken & Naan",
            emoji: "🍛",
            description: "Creamy spiced chicken thigh over rice with warm naan. Indian classic. ~25 min.",
            perServing: PerServing(calories: 820, proteinG: 46, carbsG: 80, fatG: 34, fiberG: 6),
            allergens: ["dairy", "gluten"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "chicken-thigh", quantity: 1.0),
                MealIngredientTemplate(foodId: "heavy-cream", quantity: 0.5),
                MealIngredientTemplate(foodId: "rice-white", quantity: 1.0),
                MealIngredientTemplate(foodId: "naan", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "greek-chicken-pita-plate",
            name: "Greek Chicken Pita Plate",
            emoji: "🥙",
            description: "Grilled chicken, warm pita, feta, tomato & cool tzatziki. Mediterranean. ~15 min.",
            perServing: PerServing(calories: 600, proteinG: 48, carbsG: 50, fatG: 22, fiberG: 5),
            allergens: ["dairy", "gluten"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "chicken-breast", quantity: 1.0),
                MealIngredientTemplate(foodId: "pita-bread", quantity: 1.0),
                MealIngredientTemplate(foodId: "feta", quantity: 0.5),
                MealIngredientTemplate(foodId: "tomato", quantity: 1.0),
                MealIngredientTemplate(foodId: "tzatziki-sauce", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "bbq-pulled-pork-cornbread",
            name: "BBQ Pulled Pork & Cornbread",
            emoji: "🍖",
            description: "Saucy pulled pork piled on sweet cornbread with slaw of cabbage. Smoky-sweet. ~10 min.",
            perServing: PerServing(calories: 760, proteinG: 44, carbsG: 66, fatG: 32, fiberG: 5),
            allergens: ["dairy", "gluten", "egg"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "pulled-pork", quantity: 1.0),
                MealIngredientTemplate(foodId: "cornbread", quantity: 1.0),
                MealIngredientTemplate(foodId: "bbq-sauce", quantity: 0.5),
                MealIngredientTemplate(foodId: "cabbage-green", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "spicy-shrimp-noodle-bowl",
            name: "Spicy Shrimp Noodle Bowl",
            emoji: "🍜",
            description: "Sriracha shrimp tossed with udon, peppers & bok choy. Fiery & savory. ~15 min.",
            perServing: PerServing(calories: 560, proteinG: 38, carbsG: 68, fatG: 12, fiberG: 6),
            allergens: ["gluten", "soy", "shellfish"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "shrimp", quantity: 1.0),
                MealIngredientTemplate(foodId: "udon-noodles", quantity: 1.0),
                MealIngredientTemplate(foodId: "bell-pepper-red", quantity: 1.0),
                MealIngredientTemplate(foodId: "bok-choy", quantity: 1.0),
                MealIngredientTemplate(foodId: "sriracha", quantity: 0.5),
                MealIngredientTemplate(foodId: "soy-sauce", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "turkey-bacon-avocado-bagel",
            name: "Turkey Bacon Avocado Bagel",
            emoji: "🥯",
            description: "Toasted bagel stacked with deli turkey, bacon, avocado & swiss. No-cook stack. ~6 min.",
            perServing: PerServing(calories: 640, proteinG: 40, carbsG: 52, fatG: 30, fiberG: 7),
            allergens: ["dairy", "gluten"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "bagel-plain", quantity: 1.0),
                MealIngredientTemplate(foodId: "deli-turkey", quantity: 1.0),
                MealIngredientTemplate(foodId: "bacon", quantity: 1.0),
                MealIngredientTemplate(foodId: "avocado", quantity: 0.5),
                MealIngredientTemplate(foodId: "swiss-cheese", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "protein-french-toast-stack",
            name: "Protein French Toast Stack",
            emoji: "🍞",
            description: "Eggy french toast with greek yogurt, berries & a maple drizzle. Sweet breakfast. ~12 min.",
            perServing: PerServing(calories: 580, proteinG: 36, carbsG: 70, fatG: 16, fiberG: 6),
            allergens: ["dairy", "gluten", "egg"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "french-toast", quantity: 1.0),
                MealIngredientTemplate(foodId: "greek-yogurt", quantity: 1.0),
                MealIngredientTemplate(foodId: "berries", quantity: 1.0),
                MealIngredientTemplate(foodId: "maple-syrup", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "post-workout-power-shake",
            name: "Post-Workout Power Shake",
            emoji: "🥛",
            description: "Whey, 2% milk, banana, peanut butter & oats. Fast recovery fuel. ~3 min.",
            perServing: PerServing(calories: 620, proteinG: 45, carbsG: 68, fatG: 18, fiberG: 8),
            allergens: ["dairy", "gluten", "peanut"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "protein-shake", quantity: 1.0, customName: "Whey protein"),
                MealIngredientTemplate(foodId: "milk-2percent", quantity: 1.0),
                MealIngredientTemplate(foodId: "banana", quantity: 1.0),
                MealIngredientTemplate(foodId: "peanut-butter", quantity: 1.0),
                MealIngredientTemplate(foodId: "oatmeal", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "tofu-peanut-stirfry",
            name: "Peanut Tofu Stir-Fry",
            emoji: "🥢",
            description: "Crispy tofu, broccoli & peppers in peanut sauce over brown rice. Vegan & creamy. ~18 min.",
            perServing: PerServing(calories: 660, proteinG: 30, carbsG: 70, fatG: 30, fiberG: 12),
            allergens: ["gluten", "soy", "peanut"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "tofu-firm", quantity: 1.5),
                MealIngredientTemplate(foodId: "rice-brown", quantity: 1.0),
                MealIngredientTemplate(foodId: "broccoli", quantity: 1.0),
                MealIngredientTemplate(foodId: "bell-pepper-red", quantity: 1.0),
                MealIngredientTemplate(foodId: "peanut-butter", quantity: 0.5),
                MealIngredientTemplate(foodId: "soy-sauce", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "tempeh-sweet-potato-bowl",
            name: "Tempeh Sweet Potato Bowl",
            emoji: "🍠",
            description: "Smoky tempeh, roasted sweet potato, kale & tahini drizzle. Vegan & hearty. ~22 min.",
            perServing: PerServing(calories: 590, proteinG: 32, carbsG: 64, fatG: 24, fiberG: 14),
            allergens: ["soy", "sesame"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "tempeh", quantity: 1.0),
                MealIngredientTemplate(foodId: "sweet-potato", quantity: 1.0),
                MealIngredientTemplate(foodId: "kale", quantity: 1.0),
                MealIngredientTemplate(foodId: "chickpeas", quantity: 0.5),
                MealIngredientTemplate(foodId: "tahini", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "pepperoni-pesto-flatbread",
            name: "Pepperoni Pesto Flatbread",
            emoji: "🍕",
            description: "Pita crisped with pesto, fresh mozzarella & pepperoni. Salty Italian bite. ~12 min.",
            perServing: PerServing(calories: 700, proteinG: 34, carbsG: 48, fatG: 42, fiberG: 4),
            allergens: ["dairy", "gluten", "nut"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "pita-bread", quantity: 1.0),
                MealIngredientTemplate(foodId: "pesto-sauce", quantity: 0.5),
                MealIngredientTemplate(foodId: "mozzarella-fresh", quantity: 1.0),
                MealIngredientTemplate(foodId: "pepperoni", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "ground-turkey-taco-skillet",
            name: "Ground Turkey Taco Skillet",
            emoji: "🌮",
            description: "Seasoned turkey, pinto beans, corn tortillas, cheddar & salsa. Mexican comfort. ~15 min.",
            perServing: PerServing(calories: 690, proteinG: 46, carbsG: 58, fatG: 28, fiberG: 12),
            allergens: ["dairy"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "ground-turkey", quantity: 1.0),
                MealIngredientTemplate(foodId: "pinto-beans", quantity: 1.0),
                MealIngredientTemplate(foodId: "corn-tortilla", quantity: 2.0),
                MealIngredientTemplate(foodId: "cheese-cheddar", quantity: 0.5),
                MealIngredientTemplate(foodId: "salsa-jar", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "chana-masala-rice-plate",
            name: "Chana Masala & Rice",
            emoji: "🫘",
            description: "Spiced chickpeas simmered with tomato & onion over rice. Vegan Indian warmth. ~20 min.",
            perServing: PerServing(calories: 560, proteinG: 22, carbsG: 92, fatG: 12, fiberG: 16),
            allergens: [],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "chickpeas", quantity: 1.5),
                MealIngredientTemplate(foodId: "rice-white", quantity: 1.0),
                MealIngredientTemplate(foodId: "tomato", quantity: 1.0),
                MealIngredientTemplate(foodId: "onion", quantity: 0.5),
                MealIngredientTemplate(foodId: "olive-oil", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "lamb-couscous-mediterranean",
            name: "Lamb & Couscous Plate",
            emoji: "🍢",
            description: "Seared lamb chop over couscous with chickpeas, arugula & hummus. Mediterranean. ~20 min.",
            perServing: PerServing(calories: 740, proteinG: 44, carbsG: 62, fatG: 34, fiberG: 11),
            allergens: ["gluten", "sesame"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "lamb-chop", quantity: 1.0),
                MealIngredientTemplate(foodId: "couscous", quantity: 1.0),
                MealIngredientTemplate(foodId: "chickpeas", quantity: 0.5),
                MealIngredientTemplate(foodId: "arugula", quantity: 1.0),
                MealIngredientTemplate(foodId: "hummus", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "cottage-cheese-pancake-stack",
            name: "Cottage Cheese Pancake Stack",
            emoji: "🥞",
            description: "Fluffy pancakes topped with cottage cheese, strawberries & honey. Sweet protein breakfast. ~12 min.",
            perServing: PerServing(calories: 540, proteinG: 32, carbsG: 72, fatG: 12, fiberG: 5),
            allergens: ["dairy", "gluten", "egg"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "pancakes", quantity: 1.0),
                MealIngredientTemplate(foodId: "cottage-cheese", quantity: 1.0),
                MealIngredientTemplate(foodId: "strawberries", quantity: 1.0),
                MealIngredientTemplate(foodId: "honey", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "tuna-melt-sourdough",
            name: "Tuna Melt on Sourdough",
            emoji: "🐟",
            description: "Tuna mayo griddled with cheddar on sourdough. Classic American comfort. ~10 min.",
            perServing: PerServing(calories: 620, proteinG: 42, carbsG: 42, fatG: 30, fiberG: 3),
            allergens: ["dairy", "gluten", "egg", "fish"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "tuna-canned", quantity: 1.5),
                MealIngredientTemplate(foodId: "sourdough-bread", quantity: 2.0),
                MealIngredientTemplate(foodId: "cheese-cheddar", quantity: 1.0),
                MealIngredientTemplate(foodId: "mayonnaise", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "korean-beef-rice-bowl",
            name: "Korean Beef Rice Bowl",
            emoji: "🥡",
            description: "Sweet-savory ground beef over sticky rice with edamame & sriracha. Spicy umami. ~15 min.",
            perServing: PerServing(calories: 720, proteinG: 40, carbsG: 68, fatG: 30, fiberG: 6),
            allergens: ["gluten", "soy"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "ground-beef", quantity: 1.0),
                MealIngredientTemplate(foodId: "sticky-rice", quantity: 1.0),
                MealIngredientTemplate(foodId: "edamame", quantity: 0.5),
                MealIngredientTemplate(foodId: "soy-sauce", quantity: 0.5),
                MealIngredientTemplate(foodId: "sriracha", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "almond-butter-banana-oats",
            name: "Almond Butter Banana Oats",
            emoji: "🥣",
            description: "Warm oats with almond butter, banana, blueberries & chia. Creamy vegan breakfast. ~6 min.",
            perServing: PerServing(calories: 560, proteinG: 18, carbsG: 78, fatG: 22, fiberG: 14),
            allergens: ["gluten", "nut"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "oatmeal", quantity: 1.0),
                MealIngredientTemplate(foodId: "almond-butter", quantity: 1.0),
                MealIngredientTemplate(foodId: "banana", quantity: 1.0),
                MealIngredientTemplate(foodId: "blueberries", quantity: 1.0),
                MealIngredientTemplate(foodId: "chia-seeds", quantity: 0.5)
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
        SuggestedMeal(
            id: "circuit-chickpea-cucumber-salad",
            name: "Lemon Chickpea Cucumber Salad",
            emoji: "🥗",
            description: "Chickpeas, crisp cucumber, cherry tomatoes, feta and a lemon-olive oil splash. Fresh and ready in 5 min.",
            perServing: PerServing(calories: 320, proteinG: 14, carbsG: 36, fatG: 13, fiberG: 9),
            allergens: ["dairy"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "chickpeas", quantity: 1.0),
                MealIngredientTemplate(foodId: "cucumber", quantity: 0.5),
                MealIngredientTemplate(foodId: "cherry-tomatoes", quantity: 0.5),
                MealIngredientTemplate(foodId: "feta", quantity: 0.5),
                MealIngredientTemplate(foodId: "olive-oil", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "circuit-tofu-bok-choy-stir",
            name: "Ginger Tofu & Bok Choy",
            emoji: "🥢",
            description: "Firm tofu and bok choy in a light soy-ginger glaze over brown rice. Savory, vegan, 15 min.",
            perServing: PerServing(calories: 360, proteinG: 22, carbsG: 42, fatG: 11, fiberG: 7),
            allergens: ["gluten", "soy"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "tofu-firm", quantity: 1.0),
                MealIngredientTemplate(foodId: "bok-choy", quantity: 1.0),
                MealIngredientTemplate(foodId: "rice-brown", quantity: 0.5),
                MealIngredientTemplate(foodId: "soy-sauce", quantity: 0.5),
                MealIngredientTemplate(foodId: "garlic", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "circuit-cod-asparagus-quinoa",
            name: "Lemon Cod, Asparagus & Quinoa",
            emoji: "🐟",
            description: "Flaky baked cod over fluffy quinoa with roasted asparagus. Light, lean and bright.",
            perServing: PerServing(calories: 380, proteinG: 36, carbsG: 38, fatG: 8, fiberG: 7),
            allergens: ["fish"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "cod", quantity: 1.0),
                MealIngredientTemplate(foodId: "asparagus", quantity: 1.0),
                MealIngredientTemplate(foodId: "quinoa", quantity: 1.0),
                MealIngredientTemplate(foodId: "olive-oil", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "circuit-black-bean-soup",
            name: "Smoky Black Bean Soup",
            emoji: "🍲",
            description: "Warm black bean soup with onion, garlic and a pinch of spice. Hearty, vegan, fiber-packed.",
            perServing: PerServing(calories: 250, proteinG: 15, carbsG: 42, fatG: 3, fiberG: 15),
            allergens: [],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "black-beans", quantity: 1.0),
                MealIngredientTemplate(foodId: "onion", quantity: 0.5),
                MealIngredientTemplate(foodId: "garlic", quantity: 0.5),
                MealIngredientTemplate(foodId: "salsa-jar", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "circuit-shrimp-zucchini-skillet",
            name: "Garlic Shrimp & Zucchini Skillet",
            emoji: "🍤",
            description: "Quick-seared shrimp with zucchini, cherry tomatoes and garlic. High protein, low carb, 12 min.",
            perServing: PerServing(calories: 230, proteinG: 28, carbsG: 10, fatG: 9, fiberG: 3),
            allergens: ["shellfish"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "shrimp", quantity: 1.0),
                MealIngredientTemplate(foodId: "zucchini", quantity: 1.0),
                MealIngredientTemplate(foodId: "cherry-tomatoes", quantity: 0.5),
                MealIngredientTemplate(foodId: "garlic", quantity: 0.5),
                MealIngredientTemplate(foodId: "olive-oil", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "circuit-lentil-spinach-soup",
            name: "Lentil & Spinach Soup",
            emoji: "🍵",
            description: "Cozy red lentils simmered with spinach, carrots and garlic. Warm, vegan, very filling.",
            perServing: PerServing(calories: 290, proteinG: 18, carbsG: 45, fatG: 4, fiberG: 14),
            allergens: [],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "lentils", quantity: 1.0),
                MealIngredientTemplate(foodId: "spinach", quantity: 1.0),
                MealIngredientTemplate(foodId: "carrots", quantity: 0.5),
                MealIngredientTemplate(foodId: "garlic", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "circuit-edamame-soba-bowl",
            name: "Edamame Soba Noodle Bowl",
            emoji: "🍜",
            description: "Buckwheat soba with edamame, shredded carrots and a sesame-soy drizzle. Cold or warm, savory.",
            perServing: PerServing(calories: 380, proteinG: 19, carbsG: 58, fatG: 8, fiberG: 8),
            allergens: ["gluten", "soy", "sesame"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "soba-noodles", quantity: 1.0),
                MealIngredientTemplate(foodId: "edamame", quantity: 0.5),
                MealIngredientTemplate(foodId: "carrots", quantity: 0.5),
                MealIngredientTemplate(foodId: "soy-sauce", quantity: 0.5),
                MealIngredientTemplate(foodId: "tahini", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "circuit-tuna-white-bean-salad",
            name: "Tuna & White Bean Salad",
            emoji: "🥗",
            description: "Canned tuna tossed with navy beans, arugula and lemon. No-cook, lean, omega-3 rich.",
            perServing: PerServing(calories: 310, proteinG: 32, carbsG: 28, fatG: 7, fiberG: 9),
            allergens: ["fish"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "tuna-canned", quantity: 1.0),
                MealIngredientTemplate(foodId: "navy-beans", quantity: 1.0),
                MealIngredientTemplate(foodId: "arugula", quantity: 1.0),
                MealIngredientTemplate(foodId: "olive-oil", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "circuit-spicy-chickpea-kale-bowl",
            name: "Spicy Chickpea & Kale Bowl",
            emoji: "🌶️",
            description: "Roasted chickpeas over kale and farro with a hot-sauce kick. Crunchy, spicy, vegan.",
            perServing: PerServing(calories: 400, proteinG: 17, carbsG: 62, fatG: 9, fiberG: 13),
            allergens: ["gluten"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "chickpeas", quantity: 1.0),
                MealIngredientTemplate(foodId: "kale", quantity: 1.0),
                MealIngredientTemplate(foodId: "farro", quantity: 1.0),
                MealIngredientTemplate(foodId: "hot-sauce", quantity: 0.5),
                MealIngredientTemplate(foodId: "olive-oil", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "circuit-greek-yogurt-cucumber-bowl",
            name: "Tzatziki Yogurt & Cucumber Bowl",
            emoji: "🥒",
            description: "Greek yogurt with cucumber, dill-style tzatziki and a sprinkle of pumpkin seeds. Cool and tangy.",
            perServing: PerServing(calories: 200, proteinG: 19, carbsG: 14, fatG: 8, fiberG: 2),
            allergens: ["dairy"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "greek-yogurt", quantity: 1.0),
                MealIngredientTemplate(foodId: "cucumber", quantity: 0.5),
                MealIngredientTemplate(foodId: "tzatziki-sauce", quantity: 0.5),
                MealIngredientTemplate(foodId: "pumpkin-seeds", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "circuit-tilapia-tacos",
            name: "Tilapia Street Tacos",
            emoji: "🌮",
            description: "Grilled tilapia in corn tortillas with cabbage slaw and salsa. Light, tangy, 15 min.",
            perServing: PerServing(calories: 340, proteinG: 30, carbsG: 36, fatG: 8, fiberG: 6),
            allergens: ["fish"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "tilapia", quantity: 1.0),
                MealIngredientTemplate(foodId: "corn-tortilla", quantity: 1.0),
                MealIngredientTemplate(foodId: "cabbage-green", quantity: 0.5),
                MealIngredientTemplate(foodId: "salsa-jar", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "circuit-tempeh-broccoli-rice",
            name: "Teriyaki Tempeh & Broccoli",
            emoji: "🥦",
            description: "Pan-seared tempeh and broccoli glazed with teriyaki over brown rice. Savory, vegan, protein-dense.",
            perServing: PerServing(calories: 410, proteinG: 26, carbsG: 48, fatG: 13, fiberG: 9),
            allergens: ["gluten", "soy"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "tempeh", quantity: 1.0),
                MealIngredientTemplate(foodId: "broccoli", quantity: 1.0),
                MealIngredientTemplate(foodId: "rice-brown", quantity: 0.5),
                MealIngredientTemplate(foodId: "teriyaki-sauce", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "circuit-roasted-veggie-hummus-plate",
            name: "Roasted Veggie & Hummus Plate",
            emoji: "🫑",
            description: "Warm roasted bell pepper, zucchini and carrots with hummus and a pita wedge. Mezze-style, vegan.",
            perServing: PerServing(calories: 330, proteinG: 11, carbsG: 45, fatG: 13, fiberG: 10),
            allergens: ["gluten", "sesame"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "bell-pepper-red", quantity: 0.5),
                MealIngredientTemplate(foodId: "zucchini", quantity: 0.5),
                MealIngredientTemplate(foodId: "carrots", quantity: 0.5),
                MealIngredientTemplate(foodId: "hummus", quantity: 1.0),
                MealIngredientTemplate(foodId: "pita-bread", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "circuit-salmon-kale-farro",
            name: "Salmon, Kale & Farro Bowl",
            emoji: "🐟",
            description: "Flaked salmon over massaged kale and farro with lemon. Omega-3s and whole grains, deeply satisfying.",
            perServing: PerServing(calories: 440, proteinG: 33, carbsG: 40, fatG: 16, fiberG: 8),
            allergens: ["gluten", "fish"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "salmon", quantity: 1.0),
                MealIngredientTemplate(foodId: "kale", quantity: 1.0),
                MealIngredientTemplate(foodId: "farro", quantity: 1.0),
                MealIngredientTemplate(foodId: "olive-oil", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "circuit-cottage-cheese-tomato-toast",
            name: "Cottage Cheese & Tomato Toast",
            emoji: "🍅",
            description: "Whole-wheat toast topped with cottage cheese, sliced tomato and cracked pepper. Savory, 5 min.",
            perServing: PerServing(calories: 230, proteinG: 18, carbsG: 28, fatG: 5, fiberG: 5),
            allergens: ["dairy", "gluten"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "bread-wheat", quantity: 1.0),
                MealIngredientTemplate(foodId: "cottage-cheese", quantity: 1.0),
                MealIngredientTemplate(foodId: "tomato", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "circuit-black-eyed-pea-collard-bowl",
            name: "Black-Eyed Pea & Greens Bowl",
            emoji: "🫘",
            description: "Black-eyed peas with sautéed cabbage and tomato over barley. Southern-style, vegan, fiber-rich.",
            perServing: PerServing(calories: 360, proteinG: 16, carbsG: 64, fatG: 5, fiberG: 14),
            allergens: ["gluten"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "black-eyed-peas", quantity: 1.0),
                MealIngredientTemplate(foodId: "cabbage-green", quantity: 0.5),
                MealIngredientTemplate(foodId: "tomato", quantity: 0.5),
                MealIngredientTemplate(foodId: "barley", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "circuit-scallop-pea-couscous",
            name: "Seared Scallops & Pea Couscous",
            emoji: "🍽️",
            description: "Sweet seared scallops over lemony couscous with peas and arugula. Elegant and light, 18 min.",
            perServing: PerServing(calories: 350, proteinG: 27, carbsG: 45, fatG: 6, fiberG: 6),
            allergens: ["gluten", "shellfish"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "scallops", quantity: 1.0),
                MealIngredientTemplate(foodId: "couscous", quantity: 1.0),
                MealIngredientTemplate(foodId: "peas", quantity: 0.5),
                MealIngredientTemplate(foodId: "arugula", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "circuit-mango-chia-yogurt",
            name: "Mango Chia Yogurt Cup",
            emoji: "🥭",
            description: "Greek yogurt layered with mango and chia seeds. Sweet, fresh and gut-friendly, 5 min.",
            perServing: PerServing(calories: 240, proteinG: 16, carbsG: 32, fatG: 6, fiberG: 7),
            allergens: ["dairy"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "greek-yogurt", quantity: 1.0),
                MealIngredientTemplate(foodId: "mango", quantity: 1.0),
                MealIngredientTemplate(foodId: "chia-seeds", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "circuit-spicy-lentil-sweet-potato",
            name: "Spiced Lentil & Sweet Potato",
            emoji: "🍠",
            description: "Warm curried lentils over roasted sweet potato with spinach. Cozy, spicy, vegan and very filling.",
            perServing: PerServing(calories: 380, proteinG: 18, carbsG: 66, fatG: 5, fiberG: 16),
            allergens: [],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "lentils", quantity: 1.0),
                MealIngredientTemplate(foodId: "sweet-potato", quantity: 1.0),
                MealIngredientTemplate(foodId: "spinach", quantity: 0.5),
                MealIngredientTemplate(foodId: "hot-sauce", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "circuit-shrimp-mango-slaw",
            name: "Shrimp & Mango Crunch Slaw",
            emoji: "🦐",
            description: "Chilled shrimp with shredded cabbage, mango and lime. Crunchy, tangy and bright, 10 min.",
            perServing: PerServing(calories: 250, proteinG: 26, carbsG: 30, fatG: 4, fiberG: 5),
            allergens: ["shellfish"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "shrimp", quantity: 1.0),
                MealIngredientTemplate(foodId: "cabbage-green", quantity: 0.5),
                MealIngredientTemplate(foodId: "mango", quantity: 0.5),
                MealIngredientTemplate(foodId: "bell-pepper-red", quantity: 0.5)
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
            allergens: ["dairy", "gluten"],
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
        SuggestedMeal(
            id: "caprese-toast-stack",
            name: "Caprese Toast Stack",
            emoji: "🍅",
            description: "Sourdough piled with fresh mozzarella, tomato, basil pesto drizzle. ~6 min.",
            perServing: PerServing(calories: 380, proteinG: 17, carbsG: 38, fatG: 18, fiberG: 3),
            allergens: ["dairy", "gluten", "nut"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "sourdough-bread", quantity: 1.0),
                MealIngredientTemplate(foodId: "mozzarella-fresh", quantity: 1.0),
                MealIngredientTemplate(foodId: "tomato", quantity: 1.0),
                MealIngredientTemplate(foodId: "pesto-sauce", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "buffalo-chicken-wrap",
            name: "Buffalo Ranch Chicken Wrap",
            emoji: "🌯",
            description: "Spicy hot-sauce chicken, crisp lettuce, cool ranch in a soft flour wrap. ~8 min.",
            perServing: PerServing(calories: 470, proteinG: 38, carbsG: 34, fatG: 20, fiberG: 3),
            allergens: ["dairy", "gluten", "egg"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "chicken-breast", quantity: 1.0),
                MealIngredientTemplate(foodId: "tortilla-flour", quantity: 1.0),
                MealIngredientTemplate(foodId: "lettuce", quantity: 0.5),
                MealIngredientTemplate(foodId: "hot-sauce", quantity: 0.5),
                MealIngredientTemplate(foodId: "ranch-dressing", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "pb-banana-oat-bowl",
            name: "Peanut Butter Banana Oat Bowl",
            emoji: "🥜",
            description: "Warm oats, melty peanut butter, sliced banana, honey drizzle. ~5 min.",
            perServing: PerServing(calories: 420, proteinG: 13, carbsG: 62, fatG: 15, fiberG: 8),
            allergens: ["gluten", "peanut"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "oatmeal", quantity: 1.0),
                MealIngredientTemplate(foodId: "peanut-butter", quantity: 1.0),
                MealIngredientTemplate(foodId: "banana", quantity: 1.0),
                MealIngredientTemplate(foodId: "honey", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "loaded-baked-potato",
            name: "Loaded Baked Potato",
            emoji: "🥔",
            description: "Fluffy potato, melted cheddar, crispy bacon, cool comfort. ~10 min.",
            perServing: PerServing(calories: 440, proteinG: 18, carbsG: 48, fatG: 20, fiberG: 5),
            allergens: ["dairy"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "potato-baked", quantity: 1.0),
                MealIngredientTemplate(foodId: "cheese-cheddar", quantity: 0.5),
                MealIngredientTemplate(foodId: "bacon", quantity: 1.0),
                MealIngredientTemplate(foodId: "butter", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "choc-cherry-yogurt-parfait",
            name: "Chocolate Cherry Yogurt Parfait",
            emoji: "🍒",
            description: "Greek yogurt layered with cherries, crunchy granola, cacao nibs vibe. ~3 min.",
            perServing: PerServing(calories: 340, proteinG: 22, carbsG: 48, fatG: 7, fiberG: 5),
            allergens: ["dairy", "gluten"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "greek-yogurt", quantity: 1.0),
                MealIngredientTemplate(foodId: "cherries", quantity: 1.0),
                MealIngredientTemplate(foodId: "granola", quantity: 0.5),
                MealIngredientTemplate(foodId: "chocolate-milk", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "teriyaki-tofu-rice",
            name: "Teriyaki Tofu Rice Bowl",
            emoji: "🍚",
            description: "Glazed firm tofu over rice with broccoli, sticky teriyaki sauce. ~12 min.",
            perServing: PerServing(calories: 420, proteinG: 22, carbsG: 58, fatG: 11, fiberG: 6),
            allergens: ["gluten", "soy"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "tofu-firm", quantity: 1.0),
                MealIngredientTemplate(foodId: "rice-white", quantity: 1.0),
                MealIngredientTemplate(foodId: "broccoli", quantity: 1.0),
                MealIngredientTemplate(foodId: "teriyaki-sauce", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "shrimp-avocado-salad",
            name: "Shrimp Avocado Salad",
            emoji: "🦐",
            description: "Chilled shrimp, creamy avocado, cherry tomatoes, lime-bright greens. ~7 min.",
            perServing: PerServing(calories: 320, proteinG: 28, carbsG: 14, fatG: 18, fiberG: 7),
            allergens: ["shellfish"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "shrimp", quantity: 1.0),
                MealIngredientTemplate(foodId: "avocado", quantity: 0.5),
                MealIngredientTemplate(foodId: "cherry-tomatoes", quantity: 1.0),
                MealIngredientTemplate(foodId: "salad", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "hummus-veggie-pita",
            name: "Hummus Veggie Pita Pocket",
            emoji: "🥙",
            description: "Warm pita stuffed with hummus, cucumber, bell pepper, feta crumble. ~5 min.",
            perServing: PerServing(calories: 390, proteinG: 15, carbsG: 48, fatG: 16, fiberG: 8),
            allergens: ["dairy", "gluten", "sesame"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "pita-bread", quantity: 1.0),
                MealIngredientTemplate(foodId: "hummus", quantity: 1.0),
                MealIngredientTemplate(foodId: "cucumber", quantity: 0.5),
                MealIngredientTemplate(foodId: "bell-pepper-red", quantity: 0.5),
                MealIngredientTemplate(foodId: "feta", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "berry-protein-smoothie",
            name: "Triple Berry Protein Smoothie",
            emoji: "🫐",
            description: "Mixed berries, banana, almond milk, vanilla protein. Fruity and cold. ~3 min.",
            perServing: PerServing(calories: 300, proteinG: 27, carbsG: 42, fatG: 4, fiberG: 7),
            allergens: ["dairy", "nut"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "berries", quantity: 1.0),
                MealIngredientTemplate(foodId: "banana", quantity: 0.5),
                MealIngredientTemplate(foodId: "almond-milk", quantity: 1.0),
                MealIngredientTemplate(foodId: "protein-shake", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "egg-bacon-breakfast-burrito",
            name: "Egg & Bacon Breakfast Burrito",
            emoji: "🌯",
            description: "Scrambled eggs, crispy bacon, cheddar, salsa in a warm tortilla. ~9 min.",
            perServing: PerServing(calories: 520, proteinG: 28, carbsG: 34, fatG: 29, fiberG: 3),
            allergens: ["dairy", "gluten", "egg"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "egg", quantity: 2.0),
                MealIngredientTemplate(foodId: "bacon", quantity: 1.0),
                MealIngredientTemplate(foodId: "tortilla-flour", quantity: 1.0),
                MealIngredientTemplate(foodId: "cheese-cheddar", quantity: 0.5),
                MealIngredientTemplate(foodId: "salsa-jar", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "sesame-edamame-soba",
            name: "Sesame Edamame Soba",
            emoji: "🍜",
            description: "Cold soba noodles, edamame, sesame-soy dressing, scallion freshness. ~10 min.",
            perServing: PerServing(calories: 410, proteinG: 20, carbsG: 62, fatG: 10, fiberG: 7),
            allergens: ["gluten", "soy", "sesame"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "soba-noodles", quantity: 1.0),
                MealIngredientTemplate(foodId: "edamame", quantity: 1.0),
                MealIngredientTemplate(foodId: "tahini", quantity: 0.5),
                MealIngredientTemplate(foodId: "soy-sauce", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "cottage-cheese-pineapple",
            name: "Cottage Cheese & Pineapple",
            emoji: "🍍",
            description: "Creamy cottage cheese with juicy pineapple, no cook, high protein. ~2 min.",
            perServing: PerServing(calories: 250, proteinG: 24, carbsG: 28, fatG: 5, fiberG: 2),
            allergens: ["dairy"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "cottage-cheese", quantity: 1.0),
                MealIngredientTemplate(foodId: "pineapple", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "pepperoni-flatbread",
            name: "Pepperoni Mozzarella Flatbread",
            emoji: "🍕",
            description: "Naan crisped with marinara, melty mozzarella, spicy pepperoni. ~11 min.",
            perServing: PerServing(calories: 540, proteinG: 26, carbsG: 52, fatG: 26, fiberG: 3),
            allergens: ["dairy", "gluten"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "naan", quantity: 1.0),
                MealIngredientTemplate(foodId: "marinara-sauce", quantity: 0.5),
                MealIngredientTemplate(foodId: "mozzarella-fresh", quantity: 1.0),
                MealIngredientTemplate(foodId: "pepperoni", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "black-bean-sweet-potato-bowl",
            name: "Black Bean Sweet Potato Bowl",
            emoji: "🍠",
            description: "Roasted sweet potato, black beans, avocado, salsa. Hearty vegan comfort. ~14 min.",
            perServing: PerServing(calories: 450, proteinG: 15, carbsG: 72, fatG: 13, fiberG: 16),
            allergens: [],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "sweet-potato", quantity: 1.0),
                MealIngredientTemplate(foodId: "black-beans", quantity: 1.0),
                MealIngredientTemplate(foodId: "avocado", quantity: 0.5),
                MealIngredientTemplate(foodId: "salsa-jar", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "tuna-melt-english-muffin",
            name: "Tuna Melt Muffin",
            emoji: "🐟",
            description: "Toasted English muffin, creamy tuna, bubbling swiss. Warm and savory. ~8 min.",
            perServing: PerServing(calories: 390, proteinG: 30, carbsG: 28, fatG: 17, fiberG: 2),
            allergens: ["dairy", "gluten", "egg", "fish"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "english-muffin", quantity: 1.0),
                MealIngredientTemplate(foodId: "tuna-canned", quantity: 1.0),
                MealIngredientTemplate(foodId: "mayonnaise", quantity: 0.5),
                MealIngredientTemplate(foodId: "swiss-cheese", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "apple-almond-butter-rice-cakes",
            name: "Apple Almond Butter Rice Cakes",
            emoji: "🍎",
            description: "Crunchy rice cakes, almond butter swipe, crisp apple slices. ~3 min.",
            perServing: PerServing(calories: 300, proteinG: 8, carbsG: 42, fatG: 13, fiberG: 6),
            allergens: ["nut"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "rice-cakes", quantity: 2.0),
                MealIngredientTemplate(foodId: "almond-butter", quantity: 1.0),
                MealIngredientTemplate(foodId: "apple", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "chimichurri-steak-quinoa",
            name: "Chimichurri Steak Quinoa",
            emoji: "🥩",
            description: "Seared steak, herby chimichurri, fluffy quinoa, arugula. Bold and lean. ~15 min.",
            perServing: PerServing(calories: 520, proteinG: 40, carbsG: 40, fatG: 22, fiberG: 6),
            allergens: [],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "steak", quantity: 1.0),
                MealIngredientTemplate(foodId: "quinoa", quantity: 1.0),
                MealIngredientTemplate(foodId: "chimichurri", quantity: 0.5),
                MealIngredientTemplate(foodId: "arugula", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "spicy-chickpea-bowl",
            name: "Spicy Sriracha Chickpea Bowl",
            emoji: "🌶️",
            description: "Roasted chickpeas, brown rice, spinach, fiery sriracha kick. Vegan heat. ~12 min.",
            perServing: PerServing(calories: 430, proteinG: 17, carbsG: 68, fatG: 11, fiberG: 13),
            allergens: [],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "chickpeas", quantity: 1.0),
                MealIngredientTemplate(foodId: "rice-brown", quantity: 1.0),
                MealIngredientTemplate(foodId: "spinach", quantity: 1.0),
                MealIngredientTemplate(foodId: "sriracha", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "watermelon-feta-mint-salad",
            name: "Watermelon Feta Salad",
            emoji: "🍉",
            description: "Juicy watermelon, salty feta, cucumber, balsamic. Fresh and light. ~5 min.",
            perServing: PerServing(calories: 260, proteinG: 9, carbsG: 30, fatG: 13, fiberG: 3),
            allergens: ["dairy"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "watermelon", quantity: 1.0),
                MealIngredientTemplate(foodId: "feta", quantity: 0.5),
                MealIngredientTemplate(foodId: "cucumber", quantity: 0.5),
                MealIngredientTemplate(foodId: "balsamic-vinaigrette", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "turkey-swiss-bagel",
            name: "Turkey Swiss Bagel",
            emoji: "🥯",
            description: "Toasted bagel, deli turkey, swiss, honey mustard. Quick and filling. ~4 min.",
            perServing: PerServing(calories: 440, proteinG: 28, carbsG: 52, fatG: 13, fiberG: 3),
            allergens: ["dairy", "gluten"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "bagel-plain", quantity: 1.0),
                MealIngredientTemplate(foodId: "deli-turkey", quantity: 1.0),
                MealIngredientTemplate(foodId: "swiss-cheese", quantity: 0.5),
                MealIngredientTemplate(foodId: "honey-mustard", quantity: 0.5)
            ]
        ),
        SuggestedMeal(
            id: "chocolate-pb-shake",
            name: "Chocolate Peanut Butter Shake",
            emoji: "🍫",
            description: "Chocolate milk, peanut butter, banana, protein. Decadent dessert-style. ~3 min.",
            perServing: PerServing(calories: 480, proteinG: 32, carbsG: 52, fatG: 17, fiberG: 5),
            allergens: ["dairy", "peanut"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "chocolate-milk", quantity: 1.0),
                MealIngredientTemplate(foodId: "peanut-butter", quantity: 1.0),
                MealIngredientTemplate(foodId: "banana", quantity: 1.0),
                MealIngredientTemplate(foodId: "protein-shake", quantity: 1.0)
            ]
        ),
        SuggestedMeal(
            id: "salmon-rice-cucumber-bowl",
            name: "Salmon Rice Cucumber Bowl",
            emoji: "🍣",
            description: "Flaked salmon over sticky rice, cucumber, soy-sesame drizzle. Fresh poke vibe. ~12 min.",
            perServing: PerServing(calories: 480, proteinG: 34, carbsG: 50, fatG: 15, fiberG: 3),
            allergens: ["gluten", "soy", "fish", "sesame"],
            ingredientTemplates: [
                MealIngredientTemplate(foodId: "salmon", quantity: 1.0),
                MealIngredientTemplate(foodId: "sticky-rice", quantity: 1.0),
                MealIngredientTemplate(foodId: "cucumber", quantity: 0.5),
                MealIngredientTemplate(foodId: "soy-sauce", quantity: 0.5),
                MealIngredientTemplate(foodId: "tahini", quantity: 0.5)
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
