// Reset-mode food library. DASH + Mediterranean leaning.
// High fiber, low sodium, low added sugar, omega-3 forward, satiety-per-calorie.
// No restrictions on this user.

import Foundation

public enum SeedFoodsReset {

    private static func costTier(_ c: Double) -> CostTier {
        c < 2 ? .low : (c < 4 ? .mid : .high)
    }

    private static func f(
        id: String, name: String, category: FoodCategory, recipe: String,
        cal: Int, p: Int, c: Int, ft: Int, fib: Int,
        na: Int, sug: Int, sat: Int,
        cost: Double, prep: Int = 10,
        allergens: [String] = [], ingredients: [String] = [],
        tags: [String] = []
    ) -> FoodDTO {
        FoodDTO(
            id: id, name: name, modeFit: [.reset], category: category,
            recipe: recipe,
            perServing: PerServing(
                calories: cal, proteinG: p, carbsG: c, fatG: ft,
                fiberG: fib, sodiumMg: na, addedSugarG: sug, saturatedFatG: sat
            ),
            costUsd: cost, costTier: costTier(cost), prepMinutes: prep,
            allergens: allergens, ingredients: ingredients, tags: tags
        )
    }

    public static let all: [FoodDTO] = [
        // Breakfast
        f(id: "reset-bf-overnight-oats", name: "Overnight Oats + Berries", category: .breakfast,
          recipe: "½ cup rolled oats + ¾ cup unsweetened soy/low-fat milk + 1 tbsp chia + ¾ cup mixed berries + ½ tsp cinnamon. Soak overnight.",
          cal: 340, p: 14, c: 58, ft: 8, fib: 12, na: 90, sug: 0, sat: 1,
          cost: 1.20, prep: 5, ingredients: ["oats","milk","chia","berries","cinnamon"],
          tags: ["high-fiber","dash","mediterranean","no-cook"]),

        f(id: "reset-bf-greek-yogurt-parfait", name: "Greek Yogurt Parfait", category: .breakfast,
          recipe: "¾ cup nonfat Greek yogurt + ½ cup berries + 2 tbsp walnuts + 1 tsp honey.",
          cal: 280, p: 22, c: 28, ft: 10, fib: 5, na: 70, sug: 5, sat: 1,
          cost: 2.10, prep: 3, allergens: ["dairy","tree-nut"],
          ingredients: ["greek-yogurt","berries","walnuts","honey"],
          tags: ["high-protein","mediterranean"]),

        f(id: "reset-bf-veggie-scramble", name: "Veggie Scramble + Avocado Toast", category: .breakfast,
          recipe: "2 eggs + 1 egg white scrambled w/ spinach, tomatoes, onions + 1 slice whole-grain toast + ¼ avocado.",
          cal: 360, p: 22, c: 24, ft: 19, fib: 7, na: 320, sug: 0, sat: 4,
          cost: 2.40, prep: 12, allergens: ["eggs","gluten"],
          ingredients: ["eggs","spinach","tomato","onion","whole-grain-bread","avocado"],
          tags: ["dash","high-fiber"]),

        f(id: "reset-bf-steel-cut-oats", name: "Steel-Cut Oats + Apple", category: .breakfast,
          recipe: "½ cup steel-cut oats cooked + diced apple + 1 tbsp ground flax + cinnamon.",
          cal: 320, p: 10, c: 58, ft: 7, fib: 10, na: 10, sug: 0, sat: 1,
          cost: 0.90, prep: 18, ingredients: ["steel-cut-oats","apple","flax","cinnamon"],
          tags: ["soluble-fiber","cholesterol-friendly"]),

        // Mains
        f(id: "reset-main-salmon-quinoa", name: "Salmon Quinoa Bowl", category: .bowl,
          recipe: "4 oz baked salmon + ¾ cup quinoa + 1 cup roasted broccoli + 1 cup spinach + 1 tbsp olive oil + lemon.",
          cal: 520, p: 38, c: 42, ft: 22, fib: 8, na: 240, sug: 0, sat: 4,
          cost: 6.50, prep: 25, allergens: ["fish"],
          ingredients: ["salmon","quinoa","broccoli","spinach","olive-oil","lemon"],
          tags: ["omega-3","dash","mediterranean","high-protein"]),

        f(id: "reset-main-mediterranean-bowl", name: "Mediterranean Chickpea Bowl", category: .bowl,
          recipe: "1 cup chickpeas + ½ cup brown rice + cucumber + tomato + red onion + 2 tbsp hummus + parsley + 1 tbsp olive oil + lemon.",
          cal: 510, p: 18, c: 72, ft: 17, fib: 14, na: 280, sug: 0, sat: 2,
          cost: 2.80, prep: 15,
          ingredients: ["chickpeas","brown-rice","cucumber","tomato","onion","hummus","olive-oil"],
          tags: ["mediterranean","high-fiber","plant-protein"]),

        f(id: "reset-main-lentil-soup", name: "Hearty Lentil Soup", category: .soup,
          recipe: "1.5 cups lentils simmered w/ carrots, celery, onion, garlic, low-sodium broth, cumin, bay leaf. Top w/ parsley + lemon.",
          cal: 380, p: 22, c: 60, ft: 4, fib: 18, na: 380, sug: 0, sat: 1,
          cost: 1.50, prep: 35,
          ingredients: ["lentils","carrot","celery","onion","garlic","low-sodium-broth"],
          tags: ["high-fiber","soluble-fiber","cholesterol-friendly","meal-prep"]),

        f(id: "reset-main-chicken-veg-stirfry", name: "Chicken + Veg Stir-Fry", category: .main,
          recipe: "4 oz chicken breast + 2 cups mixed veg + 2 tsp olive oil + low-sodium soy + ginger + garlic + ½ cup brown rice.",
          cal: 450, p: 38, c: 42, ft: 14, fib: 7, na: 420, sug: 0, sat: 2,
          cost: 3.40, prep: 20,
          ingredients: ["chicken-breast","bell-pepper","broccoli","snap-peas","olive-oil","low-sodium-soy","brown-rice"],
          tags: ["high-protein","dash"]),

        f(id: "reset-main-turkey-chili", name: "Turkey Bean Chili", category: .soup,
          recipe: "4 oz lean ground turkey + 1 cup black beans + ½ cup kidney beans + diced tomato + onion + bell pepper + chili spices.",
          cal: 440, p: 36, c: 48, ft: 10, fib: 16, na: 320, sug: 0, sat: 2,
          cost: 3.20, prep: 35,
          ingredients: ["ground-turkey","black-beans","kidney-beans","tomato","onion","bell-pepper"],
          tags: ["high-fiber","high-protein","meal-prep"]),

        f(id: "reset-main-tuna-greens", name: "Tuna Power Greens", category: .main,
          recipe: "1 can chunk light tuna (water) + 3 cups mixed greens + cucumber + cherry tomato + chickpeas + 1 tbsp olive oil + balsamic.",
          cal: 380, p: 34, c: 28, ft: 14, fib: 10, na: 380, sug: 0, sat: 2,
          cost: 3.00, prep: 8, allergens: ["fish"],
          ingredients: ["tuna","mixed-greens","cucumber","cherry-tomato","chickpeas","olive-oil"],
          tags: ["omega-3","high-protein","low-carb","mediterranean"]),

        f(id: "reset-main-tofu-bowl", name: "Tofu Veggie Bowl", category: .bowl,
          recipe: "5 oz baked tofu + ½ cup brown rice + 1.5 cups roasted Brussels + carrots + tahini-lemon drizzle.",
          cal: 470, p: 26, c: 48, ft: 18, fib: 12, na: 260, sug: 0, sat: 2,
          cost: 3.40, prep: 30, allergens: ["soy","sesame"],
          ingredients: ["tofu","brown-rice","brussels-sprouts","carrots","tahini","lemon"],
          tags: ["plant-protein","high-fiber","mediterranean"]),

        // Snacks
        f(id: "reset-snack-apple-pb", name: "Apple + Almond Butter", category: .snack,
          recipe: "1 medium apple sliced + 1 tbsp almond butter.",
          cal: 200, p: 4, c: 30, ft: 9, fib: 6, na: 50, sug: 0, sat: 1,
          cost: 1.20, prep: 2, allergens: ["tree-nut"],
          ingredients: ["apple","almond-butter"],
          tags: ["soluble-fiber","no-cook"]),

        f(id: "reset-snack-cottage-berries", name: "Cottage Cheese + Berries", category: .snack,
          recipe: "¾ cup low-fat cottage cheese + ½ cup blueberries + cinnamon.",
          cal: 200, p: 22, c: 18, ft: 3, fib: 3, na: 380, sug: 0, sat: 2,
          cost: 1.80, prep: 2, allergens: ["dairy"],
          ingredients: ["cottage-cheese","blueberries","cinnamon"],
          tags: ["high-protein","low-carb"]),

        f(id: "reset-snack-hummus-veg", name: "Hummus + Crudité", category: .snack,
          recipe: "¼ cup hummus + carrot sticks + cucumber + bell pepper.",
          cal: 180, p: 7, c: 22, ft: 8, fib: 6, na: 280, sug: 0, sat: 1,
          cost: 1.60, prep: 5,
          ingredients: ["hummus","carrot","cucumber","bell-pepper"],
          tags: ["mediterranean","high-fiber"]),

        f(id: "reset-snack-edamame", name: "Steamed Edamame", category: .snack,
          recipe: "1 cup edamame in pods, lightly salted.",
          cal: 190, p: 17, c: 15, ft: 8, fib: 8, na: 100, sug: 0, sat: 1,
          cost: 1.40, prep: 5, allergens: ["soy"],
          ingredients: ["edamame"],
          tags: ["plant-protein","high-fiber"]),

        f(id: "reset-snack-walnuts-fruit", name: "Walnuts + Pear", category: .snack,
          recipe: "1 oz walnuts + 1 medium pear.",
          cal: 290, p: 5, c: 28, ft: 18, fib: 8, na: 0, sug: 0, sat: 2,
          cost: 1.80, prep: 1, allergens: ["tree-nut"],
          ingredients: ["walnuts","pear"],
          tags: ["omega-3","mediterranean","no-cook"]),

        // Sides
        f(id: "reset-side-roasted-veg", name: "Roasted Rainbow Veg", category: .side,
          recipe: "2 cups mixed (broccoli, cauliflower, peppers, zucchini) + 1 tsp olive oil + herbs.",
          cal: 140, p: 5, c: 18, ft: 6, fib: 7, na: 60, sug: 0, sat: 1,
          cost: 1.50, prep: 25,
          ingredients: ["broccoli","cauliflower","bell-pepper","zucchini","olive-oil"],
          tags: ["dash","high-fiber"]),

        f(id: "reset-side-quinoa-pilaf", name: "Quinoa Herb Pilaf", category: .side,
          recipe: "¾ cup quinoa cooked in low-sodium broth + parsley + lemon + scallion.",
          cal: 220, p: 8, c: 39, ft: 4, fib: 5, na: 120, sug: 0, sat: 0,
          cost: 1.40, prep: 20,
          ingredients: ["quinoa","low-sodium-broth","parsley","lemon","scallion"],
          tags: ["whole-grain","mediterranean"]),

        // Drinks
        f(id: "reset-drink-protein-shake", name: "Berry Protein Shake", category: .drink,
          recipe: "1 scoop whey or plant protein + 1 cup unsweetened almond milk + ½ cup frozen berries + 1 tsp chia.",
          cal: 200, p: 26, c: 14, ft: 5, fib: 5, na: 180, sug: 0, sat: 1,
          cost: 1.70, prep: 3, allergens: ["tree-nut"],
          ingredients: ["whey","almond-milk","berries","chia"],
          tags: ["high-protein","post-workout"]),
    ]
}
