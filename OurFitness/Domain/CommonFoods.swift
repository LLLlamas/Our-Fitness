// Local food reference database.
// One entry per common food; values are per the listed serving size.
// Used by FoodParser to resolve natural-language meal descriptions
// into logged macros — no network call, no backend required.
//
// Sources:
//   USDA FoodData Central (fdc.nal.usda.gov) — primary authority
//   NIH NutritionData (nutritiondata.self.com) — cross-check
//   Canadian Nutrient File (canada.ca) — select items
//
// Critical values tracked: calories, protein, carbs, fat, fiber.
// Sodium/sugar/sat-fat omitted here — users who care log manually.

import Foundation

public struct CommonFood: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let aliases: [String]         // synonyms the parser should match
    public let servingLabel: String      // human-readable serving description
    public let calories: Int
    public let proteinG: Int
    public let carbsG: Int
    public let fatG: Int
    public let fiberG: Int
}

public enum CommonFoods {

    public static let all: [CommonFood] = grains + proteins + eggsAndDairy
        + vegetables + fruits + legumes + nutsAndFats + drinks + soups + preparedMeals
        + snacksAndSweets + fastFood

    // MARK: - Grains & Starches

    private static let grains: [CommonFood] = [
        CommonFood(
            id: "rice-white", name: "White rice",
            aliases: ["rice", "steamed rice", "jasmine rice", "white rice", "bowl of rice", "cup of rice"],
            servingLabel: "1 cup cooked (186 g)",
            calories: 206, proteinG: 4, carbsG: 45, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "rice-brown", name: "Brown rice",
            aliases: ["brown rice", "whole grain rice"],
            servingLabel: "1 cup cooked (195 g)",
            calories: 216, proteinG: 5, carbsG: 45, fatG: 2, fiberG: 4
        ),
        CommonFood(
            id: "oatmeal", name: "Oatmeal",
            aliases: ["oats", "oatmeal", "porridge", "rolled oats", "overnight oats"],
            servingLabel: "1 cup cooked (234 g)",
            calories: 166, proteinG: 6, carbsG: 28, fatG: 4, fiberG: 4
        ),
        CommonFood(
            id: "pasta", name: "Pasta",
            aliases: ["pasta", "noodles", "spaghetti", "penne", "fettuccine", "macaroni", "rigatoni"],
            servingLabel: "1 cup cooked (140 g)",
            calories: 220, proteinG: 8, carbsG: 43, fatG: 1, fiberG: 3
        ),
        CommonFood(
            id: "bread-white", name: "White bread",
            aliases: ["bread", "white bread", "toast", "slice of bread", "white toast"],
            servingLabel: "1 slice (30 g)",
            calories: 79, proteinG: 3, carbsG: 15, fatG: 1, fiberG: 1
        ),
        CommonFood(
            id: "bread-wheat", name: "Whole wheat bread",
            aliases: ["whole wheat bread", "wheat bread", "whole grain bread", "multigrain bread"],
            servingLabel: "1 slice (38 g)",
            calories: 81, proteinG: 4, carbsG: 14, fatG: 1, fiberG: 2
        ),
        CommonFood(
            id: "tortilla-flour", name: "Flour tortilla",
            aliases: ["tortilla", "flour tortilla", "wrap"],
            servingLabel: "1 medium 8\" (45 g)",
            calories: 146, proteinG: 4, carbsG: 26, fatG: 3, fiberG: 2
        ),
        CommonFood(
            id: "quinoa", name: "Quinoa",
            aliases: ["quinoa"],
            servingLabel: "1 cup cooked (185 g)",
            calories: 222, proteinG: 8, carbsG: 39, fatG: 4, fiberG: 5
        ),
        CommonFood(
            id: "potato-baked", name: "Baked potato",
            aliases: ["potato", "baked potato", "white potato"],
            servingLabel: "1 medium (173 g)",
            calories: 161, proteinG: 4, carbsG: 37, fatG: 0, fiberG: 4
        ),
        CommonFood(
            id: "sweet-potato", name: "Sweet potato",
            aliases: ["sweet potato", "yam"],
            servingLabel: "1 medium (130 g)",
            calories: 103, proteinG: 2, carbsG: 24, fatG: 0, fiberG: 4
        ),
        CommonFood(
            id: "gnocchi", name: "Gnocchi",
            aliases: ["gnocchi"],
            servingLabel: "1 cup cooked (173 g)",
            calories: 250, proteinG: 6, carbsG: 55, fatG: 1, fiberG: 2
        ),
        CommonFood(
            id: "granola", name: "Granola",
            aliases: ["granola", "granola bar"],
            servingLabel: "½ cup (58 g)",
            calories: 298, proteinG: 8, carbsG: 32, fatG: 15, fiberG: 4
        ),
        CommonFood(
            id: "pancakes", name: "Pancakes",
            aliases: ["pancake", "pancakes", "flapjacks"],
            servingLabel: "2 medium (154 g)",
            calories: 347, proteinG: 8, carbsG: 52, fatG: 11, fiberG: 1
        ),
        CommonFood(
            id: "waffles", name: "Waffles",
            aliases: ["waffle", "waffles"],
            servingLabel: "2 waffles (210 g)",
            calories: 406, proteinG: 11, carbsG: 56, fatG: 16, fiberG: 2
        ),
        CommonFood(
            id: "naan", name: "Naan",
            aliases: ["naan", "naan bread"],
            servingLabel: "1 piece (90 g)",
            calories: 262, proteinG: 9, carbsG: 45, fatG: 5, fiberG: 2
        ),
        CommonFood(
            id: "croissant", name: "Croissant",
            aliases: ["croissant"],
            servingLabel: "1 medium (57 g)",
            calories: 231, proteinG: 5, carbsG: 26, fatG: 12, fiberG: 1
        ),
        CommonFood(
            id: "biscuit", name: "Biscuit",
            aliases: ["biscuit", "buttermilk biscuit"],
            servingLabel: "1 (60 g)",
            calories: 212, proteinG: 4, carbsG: 27, fatG: 10, fiberG: 1
        ),
        CommonFood(
            id: "mashed-potato", name: "Mashed potatoes",
            aliases: ["mashed potatoes", "mashed potato", "mash"],
            servingLabel: "1 cup (210 g)",
            calories: 237, proteinG: 4, carbsG: 35, fatG: 9, fiberG: 3
        ),
        CommonFood(
            id: "hash-browns", name: "Hash browns",
            aliases: ["hash browns", "hashbrowns", "hash brown"],
            servingLabel: "1 cup (156 g)",
            calories: 326, proteinG: 3, carbsG: 35, fatG: 20, fiberG: 3
        ),
        CommonFood(
            id: "french-toast", name: "French toast",
            aliases: ["french toast"],
            servingLabel: "2 slices (130 g)",
            calories: 298, proteinG: 10, carbsG: 33, fatG: 14, fiberG: 1
        ),
        CommonFood(
            id: "ramen", name: "Ramen (instant)",
            aliases: ["ramen", "instant noodles", "cup noodles", "instant ramen"],
            servingLabel: "1 package prepared (85 g dry)",
            calories: 385, proteinG: 8, carbsG: 52, fatG: 15, fiberG: 2
        ),
    ]

    // MARK: - Proteins

    private static let proteins: [CommonFood] = [
        CommonFood(
            id: "chicken-breast", name: "Chicken breast",
            aliases: ["chicken", "grilled chicken", "chicken breast", "baked chicken", "chicken fillet"],
            servingLabel: "4 oz cooked (113 g)",
            calories: 187, proteinG: 35, carbsG: 0, fatG: 4, fiberG: 0
        ),
        CommonFood(
            id: "ground-turkey", name: "Ground turkey",
            aliases: ["turkey", "ground turkey", "turkey meat", "lean turkey"],
            servingLabel: "4 oz cooked (113 g)",
            calories: 170, proteinG: 22, carbsG: 0, fatG: 9, fiberG: 0
        ),
        CommonFood(
            id: "ground-beef", name: "Ground beef (80/20)",
            aliases: ["beef", "ground beef", "hamburger meat", "beef patty", "beef mince"],
            servingLabel: "4 oz cooked (113 g)",
            calories: 290, proteinG: 20, carbsG: 0, fatG: 23, fiberG: 0
        ),
        CommonFood(
            id: "steak", name: "Steak",
            aliases: ["steak", "sirloin", "beef steak", "grilled steak"],
            servingLabel: "4 oz cooked (113 g)",
            calories: 220, proteinG: 26, carbsG: 0, fatG: 12, fiberG: 0
        ),
        CommonFood(
            id: "salmon", name: "Salmon",
            aliases: ["salmon", "grilled salmon", "baked salmon", "smoked salmon"],
            servingLabel: "4 oz cooked (113 g)",
            calories: 234, proteinG: 32, carbsG: 0, fatG: 12, fiberG: 0
        ),
        CommonFood(
            id: "tuna-canned", name: "Canned tuna",
            aliases: ["tuna", "canned tuna", "tuna fish", "albacore"],
            servingLabel: "3 oz drained (85 g)",
            calories: 100, proteinG: 22, carbsG: 0, fatG: 1, fiberG: 0
        ),
        CommonFood(
            id: "shrimp", name: "Shrimp",
            aliases: ["shrimp", "prawns"],
            servingLabel: "4 oz cooked (113 g)",
            calories: 112, proteinG: 22, carbsG: 0, fatG: 2, fiberG: 0
        ),
        CommonFood(
            id: "pepperoni", name: "Pepperoni",
            aliases: ["pepperoni", "pepperoni slices"],
            servingLabel: "1 oz (28 g)",
            calories: 130, proteinG: 5, carbsG: 1, fatG: 12, fiberG: 0
        ),
        CommonFood(
            id: "salami", name: "Salami",
            aliases: ["salami"],
            servingLabel: "1 oz (28 g)",
            calories: 104, proteinG: 6, carbsG: 1, fatG: 9, fiberG: 0
        ),
        CommonFood(
            id: "ham", name: "Ham",
            aliases: ["ham", "deli ham", "cold cut", "cold cuts"],
            servingLabel: "2 oz deli (57 g)",
            calories: 68, proteinG: 11, carbsG: 0, fatG: 2, fiberG: 0
        ),
        CommonFood(
            id: "sausage", name: "Sausage",
            aliases: ["sausage", "breakfast sausage", "pork sausage"],
            servingLabel: "1 link grilled (56 g)",
            calories: 190, proteinG: 10, carbsG: 2, fatG: 16, fiberG: 0
        ),
        CommonFood(
            id: "spam", name: "Spam",
            aliases: ["spam", "canned meat", "luncheon meat"],
            servingLabel: "2 oz (56 g)",
            calories: 180, proteinG: 7, carbsG: 2, fatG: 16, fiberG: 0
        ),
        CommonFood(
            id: "chicken-thigh", name: "Chicken thigh",
            aliases: ["chicken thigh", "chicken thighs", "dark meat chicken"],
            servingLabel: "1 thigh cooked (52 g)",
            calories: 109, proteinG: 13, carbsG: 0, fatG: 6, fiberG: 0
        ),
        CommonFood(
            id: "chicken-wings", name: "Chicken wings",
            aliases: ["chicken wings", "wings", "buffalo wings"],
            servingLabel: "4 wings (~120 g)",
            calories: 320, proteinG: 30, carbsG: 0, fatG: 21, fiberG: 0
        ),
        CommonFood(
            id: "meatballs", name: "Meatballs",
            aliases: ["meatball", "meatballs"],
            servingLabel: "3 medium (85 g)",
            calories: 230, proteinG: 14, carbsG: 6, fatG: 16, fiberG: 1
        ),
        CommonFood(
            id: "pork-tenderloin", name: "Pork tenderloin",
            aliases: ["pork tenderloin", "pork loin"],
            servingLabel: "4 oz cooked (113 g)",
            calories: 163, proteinG: 27, carbsG: 0, fatG: 5, fiberG: 0
        ),
        CommonFood(
            id: "tuna-steak", name: "Tuna steak",
            aliases: ["tuna steak", "ahi tuna", "seared tuna", "fresh tuna"],
            servingLabel: "4 oz cooked (113 g)",
            calories: 156, proteinG: 34, carbsG: 0, fatG: 1, fiberG: 0
        ),
        CommonFood(
            id: "deli-turkey", name: "Deli turkey",
            aliases: ["deli turkey", "turkey breast deli", "sliced turkey", "turkey cold cut"],
            servingLabel: "2 oz (57 g)",
            calories: 60, proteinG: 11, carbsG: 1, fatG: 1, fiberG: 0
        ),
        CommonFood(
            id: "rotisserie-chicken", name: "Rotisserie chicken",
            aliases: ["rotisserie chicken", "roast chicken", "roasted chicken"],
            servingLabel: "3 oz mixed (85 g)",
            calories: 170, proteinG: 22, carbsG: 0, fatG: 9, fiberG: 0
        ),
    ]

    // MARK: - Eggs & Dairy

    private static let eggsAndDairy: [CommonFood] = [
        CommonFood(
            id: "egg", name: "Egg",
            aliases: ["egg", "eggs", "fried egg", "scrambled egg", "scrambled eggs", "boiled egg", "poached egg"],
            servingLabel: "1 large (50 g)",
            calories: 72, proteinG: 6, carbsG: 0, fatG: 5, fiberG: 0
        ),
        CommonFood(
            id: "greek-yogurt", name: "Greek yogurt",
            aliases: ["greek yogurt", "yogurt", "greek yoghurt", "plain yogurt"],
            servingLabel: "1 cup (245 g)",
            calories: 220, proteinG: 20, carbsG: 9, fatG: 11, fiberG: 0
        ),
        CommonFood(
            id: "milk-whole", name: "Whole milk",
            aliases: ["milk", "whole milk", "full-fat milk", "full fat milk"],
            servingLabel: "1 cup (244 ml)",
            calories: 149, proteinG: 8, carbsG: 12, fatG: 8, fiberG: 0
        ),
        CommonFood(
            id: "cheese-cheddar", name: "Cheddar cheese",
            aliases: ["cheese", "cheddar", "cheddar cheese", "shredded cheese"],
            servingLabel: "1 oz (28 g)",
            calories: 115, proteinG: 7, carbsG: 0, fatG: 9, fiberG: 0
        ),
        CommonFood(
            id: "cottage-cheese", name: "Cottage cheese",
            aliases: ["cottage cheese"],
            servingLabel: "½ cup (113 g)",
            calories: 110, proteinG: 13, carbsG: 4, fatG: 5, fiberG: 0
        ),
        CommonFood(
            id: "string-cheese", name: "String cheese",
            aliases: ["string cheese", "cheese stick", "mozzarella stick", "cheese string", "lactose free cheese stick"],
            servingLabel: "1 stick (28 g)",
            calories: 80, proteinG: 7, carbsG: 1, fatG: 6, fiberG: 0
        ),
        CommonFood(
            id: "oat-milk", name: "Oat milk",
            aliases: ["oat milk", "oatmilk", "oat drink"],
            servingLabel: "1 cup (240 ml)",
            calories: 130, proteinG: 4, carbsG: 24, fatG: 2, fiberG: 2
        ),
        CommonFood(
            id: "almond-milk", name: "Almond milk (unsweetened)",
            aliases: ["almond milk", "unsweetened almond milk"],
            servingLabel: "1 cup (240 ml)",
            calories: 40, proteinG: 1, carbsG: 2, fatG: 3, fiberG: 1
        ),
        CommonFood(
            id: "whipped-cream", name: "Whipped cream",
            aliases: ["whipped cream", "whip cream", "whipped topping", "reddi wip", "cool whip"],
            servingLabel: "2 tbsp (6 g)",
            calories: 15, proteinG: 0, carbsG: 1, fatG: 1, fiberG: 0
        ),
        CommonFood(
            id: "skim-milk", name: "Skim milk",
            aliases: ["skim milk", "nonfat milk", "fat free milk", "skimmed milk"],
            servingLabel: "1 cup (245 ml)",
            calories: 83, proteinG: 8, carbsG: 12, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "soy-milk", name: "Soy milk",
            aliases: ["soy milk", "soymilk"],
            servingLabel: "1 cup (243 ml)",
            calories: 105, proteinG: 6, carbsG: 12, fatG: 4, fiberG: 1
        ),
        CommonFood(
            id: "yogurt-regular", name: "Yogurt (lowfat)",
            aliases: ["lowfat yogurt", "fruit yogurt", "flavored yogurt", "low fat yogurt"],
            servingLabel: "1 cup (245 g)",
            calories: 154, proteinG: 13, carbsG: 17, fatG: 4, fiberG: 0
        ),
        CommonFood(
            id: "feta", name: "Feta cheese",
            aliases: ["feta", "feta cheese"],
            servingLabel: "1 oz (28 g)",
            calories: 75, proteinG: 4, carbsG: 1, fatG: 6, fiberG: 0
        ),
        CommonFood(
            id: "egg-whites", name: "Egg whites",
            aliases: ["egg white", "egg whites", "egg white only"],
            servingLabel: "2 large whites (66 g)",
            calories: 34, proteinG: 7, carbsG: 0, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "omelette", name: "Omelette",
            aliases: ["omelette", "omelet", "veggie omelette", "cheese omelette"],
            servingLabel: "2-egg with fillings (~150 g)",
            calories: 220, proteinG: 15, carbsG: 3, fatG: 16, fiberG: 1
        ),
    ]

    // MARK: - Vegetables

    private static let vegetables: [CommonFood] = [
        CommonFood(
            id: "broccoli", name: "Broccoli",
            aliases: ["broccoli", "steamed broccoli"],
            servingLabel: "1 cup chopped (91 g)",
            calories: 55, proteinG: 4, carbsG: 11, fatG: 1, fiberG: 5
        ),
        CommonFood(
            id: "spinach", name: "Spinach",
            aliases: ["spinach", "baby spinach", "cooked spinach"],
            servingLabel: "1 cup raw (30 g)",
            calories: 7, proteinG: 1, carbsG: 1, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "salad", name: "Side salad",
            aliases: ["salad", "garden salad", "mixed salad", "side salad", "green salad"],
            servingLabel: "2 cups mixed greens (80 g)",
            calories: 20, proteinG: 1, carbsG: 4, fatG: 0, fiberG: 2
        ),
        CommonFood(
            id: "avocado", name: "Avocado",
            aliases: ["avocado", "avo"],
            servingLabel: "½ medium (68 g)",
            calories: 160, proteinG: 2, carbsG: 9, fatG: 15, fiberG: 7
        ),
        CommonFood(
            id: "tomato", name: "Tomato",
            aliases: ["tomato", "tomatoes", "roma tomato"],
            servingLabel: "1 medium (123 g)",
            calories: 22, proteinG: 1, carbsG: 5, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "cherry-tomatoes", name: "Cherry tomatoes",
            aliases: ["cherry tomatoes", "cherry tomato", "grape tomatoes"],
            servingLabel: "1 cup (149 g)",
            calories: 27, proteinG: 1, carbsG: 6, fatG: 0, fiberG: 2
        ),
        CommonFood(
            id: "cucumber", name: "Cucumber",
            aliases: ["cucumber"],
            servingLabel: "1 medium (201 g)",
            calories: 30, proteinG: 1, carbsG: 7, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "zucchini", name: "Zucchini",
            aliases: ["zucchini", "zucchini noodles", "courgette", "zoodles"],
            servingLabel: "1 cup spiralized (124 g)",
            calories: 20, proteinG: 2, carbsG: 4, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "seaweed-wakame", name: "Seaweed (wakame)",
            aliases: ["seaweed", "wakame", "kelp", "nori"],
            servingLabel: "1 cup rehydrated (80 g)",
            calories: 36, proteinG: 2, carbsG: 6, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "lettuce", name: "Lettuce",
            aliases: ["lettuce", "romaine", "iceberg lettuce", "romaine lettuce"],
            servingLabel: "1 cup shredded (47 g)",
            calories: 8, proteinG: 1, carbsG: 2, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "onion", name: "Onion",
            aliases: ["onion", "onions", "red onion", "white onion"],
            servingLabel: "1 cup chopped (160 g)",
            calories: 64, proteinG: 2, carbsG: 15, fatG: 0, fiberG: 3
        ),
        CommonFood(
            id: "peas", name: "Peas",
            aliases: ["peas", "green peas", "garden peas"],
            servingLabel: "1 cup (145 g)",
            calories: 117, proteinG: 8, carbsG: 21, fatG: 1, fiberG: 7
        ),
        CommonFood(
            id: "brussels-sprouts", name: "Brussels sprouts",
            aliases: ["brussels sprouts", "brussel sprouts"],
            servingLabel: "1 cup (88 g)",
            calories: 38, proteinG: 3, carbsG: 8, fatG: 0, fiberG: 3
        ),
        CommonFood(
            id: "eggplant", name: "Eggplant",
            aliases: ["eggplant", "aubergine"],
            servingLabel: "1 cup cubed cooked (99 g)",
            calories: 35, proteinG: 1, carbsG: 9, fatG: 0, fiberG: 2
        ),
        CommonFood(
            id: "celery", name: "Celery",
            aliases: ["celery", "celery sticks"],
            servingLabel: "1 cup chopped (101 g)",
            calories: 16, proteinG: 1, carbsG: 3, fatG: 0, fiberG: 2
        ),
    ]

    // MARK: - Fruits

    private static let fruits: [CommonFood] = [
        CommonFood(
            id: "banana", name: "Banana",
            aliases: ["banana"],
            servingLabel: "1 medium (118 g)",
            calories: 105, proteinG: 1, carbsG: 27, fatG: 0, fiberG: 3
        ),
        CommonFood(
            id: "apple", name: "Apple",
            aliases: ["apple"],
            servingLabel: "1 medium (182 g)",
            calories: 95, proteinG: 0, carbsG: 25, fatG: 0, fiberG: 4
        ),
        CommonFood(
            id: "orange", name: "Orange",
            aliases: ["orange"],
            servingLabel: "1 medium (131 g)",
            calories: 62, proteinG: 1, carbsG: 15, fatG: 0, fiberG: 3
        ),
        CommonFood(
            id: "berries", name: "Mixed berries",
            aliases: ["berries", "mixed berries"],
            servingLabel: "1 cup (150 g)",
            calories: 65, proteinG: 1, carbsG: 16, fatG: 0, fiberG: 4
        ),
        CommonFood(
            id: "strawberries", name: "Strawberries",
            aliases: ["strawberry", "strawberries"],
            servingLabel: "1 cup (152 g)",
            calories: 49, proteinG: 1, carbsG: 12, fatG: 0, fiberG: 3
        ),
        CommonFood(
            id: "raspberries", name: "Raspberries",
            aliases: ["raspberry", "raspberries"],
            servingLabel: "1 cup (123 g)",
            calories: 64, proteinG: 1, carbsG: 15, fatG: 1, fiberG: 8
        ),
        CommonFood(
            id: "blueberries", name: "Blueberries",
            aliases: ["blueberry", "blueberries"],
            servingLabel: "1 cup (148 g)",
            calories: 84, proteinG: 1, carbsG: 21, fatG: 0, fiberG: 4
        ),
        CommonFood(
            id: "mango", name: "Mango",
            aliases: ["mango"],
            servingLabel: "1 cup diced (165 g)",
            calories: 99, proteinG: 1, carbsG: 25, fatG: 1, fiberG: 3
        ),
        CommonFood(
            id: "plum", name: "Plum",
            aliases: ["plum", "plums"],
            servingLabel: "1 medium (66 g)",
            calories: 30, proteinG: 0, carbsG: 8, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "date-medjool", name: "Medjool date",
            aliases: ["date", "dates", "medjool date"],
            servingLabel: "1 date (24 g)",
            calories: 66, proteinG: 0, carbsG: 18, fatG: 0, fiberG: 2
        ),
        CommonFood(
            id: "watermelon", name: "Watermelon",
            aliases: ["watermelon"],
            servingLabel: "1 cup diced (152 g)",
            calories: 46, proteinG: 1, carbsG: 11, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "dragonfruit", name: "Dragonfruit",
            aliases: ["dragonfruit", "dragon fruit", "pitaya", "pitahaya"],
            servingLabel: "1 cup cubed (227 g)",
            calories: 136, proteinG: 3, carbsG: 29, fatG: 0, fiberG: 7
        ),
        CommonFood(
            id: "lychee", name: "Lychee",
            aliases: ["lychee", "lychees", "litchi", "leechee"],
            servingLabel: "1 cup (190 g)",
            calories: 125, proteinG: 2, carbsG: 31, fatG: 0, fiberG: 2
        ),
        CommonFood(
            id: "acai-puree", name: "Açaí (unsweetened)",
            aliases: ["acai", "açaí", "acai puree", "acai pack", "acai pulp"],
            servingLabel: "1 pack (100 g, unsweetened)",
            calories: 70, proteinG: 1, carbsG: 6, fatG: 5, fiberG: 3
        ),
        CommonFood(
            id: "grapes-table", name: "Grapes",
            aliases: ["grapes", "grape", "green grapes", "red grapes"],
            servingLabel: "1 cup (151 g)",
            calories: 104, proteinG: 1, carbsG: 27, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "cherries", name: "Cherries",
            aliases: ["cherry", "cherries"],
            servingLabel: "1 cup (154 g)",
            calories: 97, proteinG: 2, carbsG: 25, fatG: 0, fiberG: 3
        ),
        CommonFood(
            id: "pomegranate", name: "Pomegranate",
            aliases: ["pomegranate", "pomegranate seeds", "arils"],
            servingLabel: "½ cup arils (87 g)",
            calories: 72, proteinG: 1, carbsG: 16, fatG: 1, fiberG: 4
        ),
        CommonFood(
            id: "grapefruit-half", name: "Grapefruit",
            aliases: ["grapefruit"],
            servingLabel: "½ medium (123 g)",
            calories: 52, proteinG: 1, carbsG: 13, fatG: 0, fiberG: 2
        ),
    ]

    // MARK: - Legumes

    private static let legumes: [CommonFood] = [
        CommonFood(
            id: "black-beans", name: "Black beans",
            aliases: ["black beans", "beans", "frijoles", "refried beans"],
            servingLabel: "1 cup cooked (172 g)",
            calories: 227, proteinG: 15, carbsG: 41, fatG: 1, fiberG: 15
        ),
        CommonFood(
            id: "lentils", name: "Lentils",
            aliases: ["lentils", "lentil soup", "red lentils"],
            servingLabel: "1 cup cooked (198 g)",
            calories: 230, proteinG: 18, carbsG: 40, fatG: 1, fiberG: 16
        ),
        CommonFood(
            id: "chickpeas", name: "Chickpeas",
            aliases: ["chickpeas", "garbanzo beans"],
            servingLabel: "1 cup cooked (164 g)",
            calories: 269, proteinG: 15, carbsG: 45, fatG: 4, fiberG: 13
        ),
    ]

    // MARK: - Nuts & Fats

    private static let nutsAndFats: [CommonFood] = [
        CommonFood(
            id: "almonds", name: "Almonds",
            aliases: ["almonds", "almond"],
            servingLabel: "1 oz (28 g, ~23 nuts)",
            calories: 164, proteinG: 6, carbsG: 6, fatG: 14, fiberG: 3
        ),
        CommonFood(
            id: "peanut-butter", name: "Peanut butter",
            aliases: ["peanut butter", "pb", "natural peanut butter"],
            servingLabel: "2 tbsp (32 g)",
            calories: 191, proteinG: 7, carbsG: 7, fatG: 16, fiberG: 2
        ),
        CommonFood(
            id: "walnuts", name: "Walnuts",
            aliases: ["walnuts", "walnut"],
            servingLabel: "1 oz (28 g, ~14 halves)",
            calories: 185, proteinG: 4, carbsG: 4, fatG: 18, fiberG: 2
        ),
    ]

    // MARK: - Drinks

    private static let drinks: [CommonFood] = [
        CommonFood(
            id: "oj", name: "Orange juice",
            aliases: ["orange juice", "oj", "juice"],
            servingLabel: "1 cup (240 ml)",
            calories: 112, proteinG: 2, carbsG: 26, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "cola", name: "Cola soda",
            aliases: ["coke", "cola", "pepsi", "soda", "pop", "diet coke"],
            servingLabel: "12 oz can",
            calories: 140, proteinG: 0, carbsG: 39, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "coffee", name: "Black coffee",
            aliases: ["coffee", "black coffee", "americano", "espresso"],
            servingLabel: "1 cup (240 ml)",
            calories: 2, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "protein-shake", name: "Protein shake",
            aliases: ["protein shake", "whey shake", "protein powder", "shake", "protein"],
            servingLabel: "1 scoop in 8 oz water",
            calories: 120, proteinG: 25, carbsG: 3, fatG: 2, fiberG: 1
        ),
        CommonFood(
            id: "smoothie-banana-milk", name: "Banana smoothie",
            aliases: ["smoothie", "banana smoothie", "fruit smoothie", "protein smoothie"],
            servingLabel: "16 oz (banana + milk + protein)",
            calories: 420, proteinG: 30, carbsG: 55, fatG: 8, fiberG: 4
        ),
        CommonFood(
            id: "bubble-tea", name: "Bubble tea (milk tea + boba)",
            aliases: ["bubble tea", "boba", "boba tea", "milk tea", "pearl milk tea", "boba milk tea"],
            servingLabel: "16 oz with tapioca pearls",
            calories: 280, proteinG: 2, carbsG: 60, fatG: 5, fiberG: 0
        ),
        CommonFood(
            id: "chocolate-milk", name: "Chocolate milk",
            aliases: ["chocolate milk", "nesquik", "choccy milk", "chocolate nesquik"],
            servingLabel: "1 cup (240 ml)",
            calories: 190, proteinG: 8, carbsG: 30, fatG: 5, fiberG: 1
        ),
        CommonFood(
            id: "milk-2percent", name: "2% milk",
            aliases: ["2% milk", "two percent milk", "reduced fat milk", "semi-skimmed milk"],
            servingLabel: "1 cup (244 ml)",
            calories: 122, proteinG: 8, carbsG: 12, fatG: 5, fiberG: 0
        ),
        CommonFood(
            id: "latte", name: "Latte",
            aliases: ["latte", "caffe latte", "cafe latte", "flat white"],
            servingLabel: "16 oz with whole milk",
            calories: 220, proteinG: 12, carbsG: 18, fatG: 11, fiberG: 0
        ),
        CommonFood(
            id: "cappuccino", name: "Cappuccino",
            aliases: ["cappuccino"],
            servingLabel: "12 oz with whole milk",
            calories: 120, proteinG: 6, carbsG: 10, fatG: 6, fiberG: 0
        ),
        CommonFood(
            id: "iced-coffee-sweet", name: "Sweetened iced coffee",
            aliases: ["iced coffee", "sweet coffee", "iced latte"],
            servingLabel: "16 oz with milk + sugar",
            calories: 190, proteinG: 5, carbsG: 32, fatG: 5, fiberG: 0
        ),
        CommonFood(
            id: "green-tea", name: "Green tea",
            aliases: ["green tea", "tea", "matcha tea", "herbal tea"],
            servingLabel: "1 cup (240 ml, unsweetened)",
            calories: 2, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "energy-drink", name: "Energy drink",
            aliases: ["energy drink", "red bull", "monster", "energy"],
            servingLabel: "16 oz can",
            calories: 210, proteinG: 2, carbsG: 54, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "sports-drink", name: "Sports drink",
            aliases: ["sports drink", "gatorade", "powerade", "electrolyte drink"],
            servingLabel: "20 oz bottle",
            calories: 140, proteinG: 0, carbsG: 36, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "beer", name: "Beer",
            aliases: ["beer", "lager", "ale"],
            servingLabel: "12 oz can",
            calories: 153, proteinG: 2, carbsG: 13, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "wine-red", name: "Red wine",
            aliases: ["red wine", "wine", "glass of wine"],
            servingLabel: "5 oz glass (147 ml)",
            calories: 125, proteinG: 0, carbsG: 4, fatG: 0, fiberG: 0
        ),
    ]

    // MARK: - Soups

    private static let soups: [CommonFood] = [
        CommonFood(
            id: "chicken-noodle-soup", name: "Chicken noodle soup",
            aliases: ["chicken noodle soup", "chicken soup", "canned soup"],
            servingLabel: "1 cup canned (248 g)",
            calories: 75, proteinG: 4, carbsG: 9, fatG: 2, fiberG: 1
        ),
        CommonFood(
            id: "miso-soup", name: "Miso soup",
            aliases: ["miso soup", "miso broth"],
            servingLabel: "1 cup (240 ml)",
            calories: 40, proteinG: 3, carbsG: 5, fatG: 1, fiberG: 0
        ),
        CommonFood(
            id: "corn-soup", name: "Corn soup",
            aliases: ["corn soup", "corn chowder", "cream of corn"],
            servingLabel: "1 cup (240 ml)",
            calories: 133, proteinG: 4, carbsG: 22, fatG: 4, fiberG: 2
        ),
        CommonFood(
            id: "clam-chowder", name: "Clam chowder (New England)",
            aliases: ["clam chowder", "clam soup", "new england chowder"],
            servingLabel: "1 cup (248 g)",
            calories: 190, proteinG: 9, carbsG: 18, fatG: 10, fiberG: 1
        ),
    ]

    // MARK: - Prepared meals

    private static let preparedMeals: [CommonFood] = [
        CommonFood(
            id: "burger", name: "Hamburger",
            aliases: ["burger", "hamburger", "cheeseburger"],
            servingLabel: "1 standard burger",
            calories: 450, proteinG: 25, carbsG: 40, fatG: 20, fiberG: 2
        ),
        CommonFood(
            id: "pizza-slice", name: "Pizza slice",
            aliases: ["pizza", "slice of pizza", "slice"],
            servingLabel: "1 slice (14\" pepperoni, 107 g)",
            calories: 298, proteinG: 12, carbsG: 34, fatG: 13, fiberG: 2
        ),
        CommonFood(
            id: "tacos", name: "Tacos",
            aliases: ["taco", "tacos"],
            servingLabel: "2 tacos (~200 g)",
            calories: 360, proteinG: 18, carbsG: 36, fatG: 16, fiberG: 4
        ),
        CommonFood(
            id: "burrito-bowl", name: "Burrito bowl",
            aliases: ["burrito bowl", "chipotle bowl", "rice bowl", "burrito"],
            servingLabel: "1 bowl (~450 g)",
            calories: 650, proteinG: 40, carbsG: 65, fatG: 20, fiberG: 10
        ),
        CommonFood(
            id: "acai-bowl", name: "Açaí bowl",
            aliases: ["acai bowl", "açaí bowl", "acai smoothie bowl"],
            servingLabel: "1 bowl (~350 g, with granola + fruit)",
            calories: 450, proteinG: 6, carbsG: 80, fatG: 12, fiberG: 9
        ),
        CommonFood(
            id: "sandwich", name: "Turkey sandwich",
            aliases: ["sandwich", "turkey sandwich", "sub", "deli sandwich"],
            servingLabel: "1 6\" sandwich (~220 g)",
            calories: 350, proteinG: 22, carbsG: 40, fatG: 10, fiberG: 4
        ),
        CommonFood(
            id: "cereal", name: "Cereal",
            aliases: ["cereal", "corn flakes", "cheerios"],
            servingLabel: "1 cup with milk (~280 g)",
            calories: 210, proteinG: 9, carbsG: 40, fatG: 3, fiberG: 2
        ),
        CommonFood(
            id: "eggs-toast", name: "Eggs & toast",
            aliases: ["eggs and toast", "egg toast", "breakfast"],
            servingLabel: "2 eggs + 2 slices toast",
            calories: 301, proteinG: 18, carbsG: 30, fatG: 12, fiberG: 3
        ),
        CommonFood(
            id: "chicken-rice-bowl", name: "Chicken rice bowl",
            aliases: ["chicken and rice", "chicken rice", "chicken bowl", "rice and chicken"],
            servingLabel: "4 oz chicken + 1 cup rice",
            calories: 393, proteinG: 39, carbsG: 45, fatG: 4, fiberG: 1
        ),
        CommonFood(
            id: "salmon-sweet-potato", name: "Salmon & sweet potato",
            aliases: ["salmon and sweet potato", "salmon with sweet potato"],
            servingLabel: "4 oz salmon + 1 medium sweet potato",
            calories: 337, proteinG: 34, carbsG: 24, fatG: 12, fiberG: 4
        ),
        CommonFood(
            id: "oatmeal-banana", name: "Oatmeal & banana",
            aliases: ["oatmeal and banana", "oatmeal with banana"],
            servingLabel: "1 cup oatmeal + 1 banana",
            calories: 271, proteinG: 7, carbsG: 55, fatG: 4, fiberG: 7
        ),
        CommonFood(
            id: "grilled-cheese", name: "Grilled cheese",
            aliases: ["grilled cheese", "toasted cheese sandwich"],
            servingLabel: "1 sandwich (150 g)",
            calories: 290, proteinG: 12, carbsG: 28, fatG: 15, fiberG: 1
        ),
        CommonFood(
            id: "corndog", name: "Corndog",
            aliases: ["corndog", "corn dog"],
            servingLabel: "1 (175 g)",
            calories: 258, proteinG: 8, carbsG: 22, fatG: 15, fiberG: 1
        ),
        CommonFood(
            id: "sushi-salmon-roll", name: "Salmon sushi roll",
            aliases: ["salmon roll", "sushi roll", "salmon sushi", "salmon maki"],
            servingLabel: "1 roll / 8 pieces (235 g)",
            calories: 380, proteinG: 18, carbsG: 40, fatG: 14, fiberG: 2
        ),
        CommonFood(
            id: "sushi-california-roll", name: "California roll",
            aliases: ["california roll", "crab roll", "sushi"],
            servingLabel: "1 roll / 8 pieces (220 g)",
            calories: 255, proteinG: 9, carbsG: 38, fatG: 7, fiberG: 3
        ),
        CommonFood(
            id: "seaweed-salad", name: "Seaweed salad",
            aliases: ["seaweed salad", "wakame salad"],
            servingLabel: "½ cup dressed (70 g)",
            calories: 50, proteinG: 1, carbsG: 7, fatG: 2, fiberG: 1
        ),
        CommonFood(
            id: "zucchini-noodles-marinara", name: "Zucchini noodles & marinara",
            aliases: ["zucchini noodles marinara", "zoodles marinara", "zucchini pasta"],
            servingLabel: "1 cup noodles + ½ cup sauce (280 g)",
            calories: 95, proteinG: 5, carbsG: 18, fatG: 1, fiberG: 4
        ),
        CommonFood(
            id: "quesadilla", name: "Quesadilla",
            aliases: ["quesadilla", "cheese quesadilla"],
            servingLabel: "1 medium (170 g)",
            calories: 360, proteinG: 18, carbsG: 36, fatG: 16, fiberG: 2
        ),
        CommonFood(
            id: "fries", name: "French fries",
            // "chips" intentionally omitted — it belongs to potato-chips (US English);
            // leaving it here created an ambiguous bare-"chips" tie resolved to fries.
            aliases: ["fries", "french fries"],
            servingLabel: "Medium serving (117 g)",
            calories: 365, proteinG: 4, carbsG: 48, fatG: 17, fiberG: 4
        ),
    ]

    // MARK: - Snacks & Sweets

    private static let snacksAndSweets: [CommonFood] = [
        CommonFood(
            id: "potato-chips", name: "Potato chips",
            aliases: ["potato chips", "chips", "crisps"],
            servingLabel: "1 oz (28 g, ~15 chips)",
            calories: 152, proteinG: 2, carbsG: 15, fatG: 10, fiberG: 1
        ),
        CommonFood(
            id: "tortilla-chips", name: "Tortilla chips",
            aliases: ["tortilla chips", "nachos", "corn chips"],
            servingLabel: "1 oz (28 g, ~10 chips)",
            calories: 138, proteinG: 2, carbsG: 18, fatG: 7, fiberG: 2
        ),
        CommonFood(
            id: "popcorn", name: "Popcorn",
            aliases: ["popcorn", "popped corn"],
            servingLabel: "3 cups air-popped (24 g)",
            calories: 93, proteinG: 3, carbsG: 19, fatG: 1, fiberG: 4
        ),
        CommonFood(
            id: "pretzels", name: "Pretzels",
            aliases: ["pretzels", "pretzel"],
            servingLabel: "1 oz (28 g)",
            calories: 108, proteinG: 3, carbsG: 23, fatG: 1, fiberG: 1
        ),
        CommonFood(
            id: "crackers", name: "Crackers",
            aliases: ["crackers", "saltines", "cracker"],
            servingLabel: "5 crackers (15 g)",
            calories: 65, proteinG: 1, carbsG: 11, fatG: 2, fiberG: 0
        ),
        CommonFood(
            id: "chocolate-bar", name: "Chocolate bar",
            aliases: ["chocolate", "chocolate bar", "candy bar", "milk chocolate"],
            servingLabel: "1 bar (43 g)",
            calories: 235, proteinG: 3, carbsG: 26, fatG: 13, fiberG: 1
        ),
        CommonFood(
            id: "cookie", name: "Cookie",
            aliases: ["cookie", "cookies", "chocolate chip cookie"],
            servingLabel: "1 medium (30 g)",
            calories: 148, proteinG: 2, carbsG: 20, fatG: 7, fiberG: 1
        ),
        CommonFood(
            id: "brownie", name: "Brownie",
            aliases: ["brownie", "brownies"],
            servingLabel: "1 piece (56 g)",
            calories: 227, proteinG: 3, carbsG: 36, fatG: 9, fiberG: 1
        ),
        CommonFood(
            id: "donut", name: "Donut",
            aliases: ["donut", "doughnut", "glazed donut"],
            servingLabel: "1 glazed (60 g)",
            calories: 240, proteinG: 4, carbsG: 27, fatG: 14, fiberG: 1
        ),
        CommonFood(
            id: "muffin", name: "Muffin",
            aliases: ["muffin", "blueberry muffin"],
            servingLabel: "1 medium (113 g)",
            calories: 380, proteinG: 6, carbsG: 53, fatG: 16, fiberG: 2
        ),
        CommonFood(
            id: "ice-cream", name: "Ice cream",
            aliases: ["ice cream", "icecream", "vanilla ice cream"],
            servingLabel: "½ cup (66 g)",
            calories: 137, proteinG: 2, carbsG: 16, fatG: 7, fiberG: 0
        ),
        CommonFood(
            id: "protein-bar", name: "Protein bar",
            aliases: ["protein bar", "energy bar", "cliff bar", "clif bar"],
            servingLabel: "1 bar (60 g)",
            calories: 220, proteinG: 20, carbsG: 23, fatG: 7, fiberG: 3
        ),
        CommonFood(
            id: "trail-mix", name: "Trail mix",
            aliases: ["trail mix", "gorp"],
            servingLabel: "¼ cup (38 g)",
            calories: 175, proteinG: 5, carbsG: 16, fatG: 11, fiberG: 2
        ),
        CommonFood(
            id: "dark-chocolate", name: "Dark chocolate",
            aliases: ["dark chocolate", "70% chocolate"],
            servingLabel: "1 oz (28 g)",
            calories: 170, proteinG: 2, carbsG: 13, fatG: 12, fiberG: 3
        ),
    ]

    // MARK: - Fast food & restaurant (curated, brand-official / USDA)
    //
    // These iconic chain items are not cleanly in the USDA DB, so they're
    // curated here from each brand's OFFICIAL published nutrition (or USDA
    // SR Legacy "Restaurant, Chinese, …" rows for the generic takeout
    // representatives). Curated entries shadow the USDA DB by alias — intended,
    // so a typed "big mac" resolves to the real Big Mac. Source URL noted per
    // entry; values verified to pass the 4·P + 4·C + 9·F ≈ kcal sanity check.

    private static let fastFood: [CommonFood] = [
        // — McDonald's — https://www.mcdonalds.com/us/en-us/about-our-food/nutrition-calculator.html
        // (values mirrored from fastfoodnutrition.org/mcdonalds/*)
        CommonFood(
            id: "ff-mcd-big-mac", name: "Big Mac",
            aliases: ["big mac", "bigmac", "mcdonalds big mac", "mcdonald's big mac"],
            servingLabel: "1 burger (215 g)",
            calories: 540, proteinG: 25, carbsG: 46, fatG: 28, fiberG: 3
        ),
        CommonFood(
            id: "ff-mcd-quarter-pounder", name: "Quarter Pounder with Cheese",
            aliases: ["quarter pounder", "quarter pounder with cheese", "qpc", "mcdonalds quarter pounder"],
            servingLabel: "1 burger (202 g)",
            calories: 540, proteinG: 31, carbsG: 42, fatG: 28, fiberG: 3
        ),
        CommonFood(
            id: "ff-mcd-mcnuggets-10", name: "Chicken McNuggets (10 pc)",
            aliases: ["chicken mcnuggets", "mcnuggets", "10 piece mcnuggets", "10 piece nuggets", "chicken nuggets mcdonalds"],
            servingLabel: "10 pieces (162 g)",
            calories: 440, proteinG: 24, carbsG: 26, fatG: 27, fiberG: 2
        ),
        CommonFood(
            id: "ff-mcd-fries-medium", name: "McDonald's medium fries",
            aliases: ["mcdonalds fries", "mcdonald's fries", "mcdonalds medium fries", "mcdonalds french fries", "world famous fries"],
            servingLabel: "Medium (111 g)",
            calories: 340, proteinG: 4, carbsG: 44, fatG: 16, fiberG: 4
        ),

        // — Burger King — https://www.bk.com/menu (Whopper Sandwich; medium onion rings)
        CommonFood(
            id: "ff-bk-whopper", name: "Whopper",
            aliases: ["whopper", "burger king whopper", "bk whopper"],
            servingLabel: "1 sandwich (270 g)",
            calories: 670, proteinG: 28, carbsG: 49, fatG: 40, fiberG: 2
        ),
        CommonFood(
            id: "ff-bk-onion-rings", name: "Onion rings (Burger King)",
            aliases: ["onion rings", "burger king onion rings", "bk onion rings"],
            servingLabel: "Medium (91 g)",
            calories: 360, proteinG: 4, carbsG: 48, fatG: 16, fiberG: 5
        ),

        // — Wendy's — https://www.wendys.com/menu (values via fastfoodnutrition.org/wendys/*)
        CommonFood(
            id: "ff-wendys-daves-single", name: "Dave's Single",
            aliases: ["daves single", "dave's single", "wendys daves single", "wendy's single"],
            servingLabel: "1 cheeseburger (284 g)",
            calories: 570, proteinG: 29, carbsG: 38, fatG: 34, fiberG: 2
        ),
        CommonFood(
            id: "ff-wendys-fries-medium", name: "Wendy's medium fries",
            aliases: ["wendys fries", "wendy's fries", "wendys medium fries", "natural cut fries"],
            servingLabel: "Medium (150 g)",
            calories: 350, proteinG: 5, carbsG: 47, fatG: 16, fiberG: 4
        ),
        CommonFood(
            id: "ff-wendys-frosty-small", name: "Frosty (small)",
            aliases: ["frosty", "wendys frosty", "wendy's frosty", "small frosty", "chocolate frosty"],
            servingLabel: "Small (227 g)",
            calories: 350, proteinG: 10, carbsG: 58, fatG: 9, fiberG: 0
        ),

        // — White Castle — https://www.whitecastle.com/menu (Original Slider)
        CommonFood(
            id: "ff-white-castle-slider", name: "White Castle slider",
            aliases: ["white castle slider", "slider", "white castle", "original slider"],
            servingLabel: "1 slider (58 g)",
            calories: 140, proteinG: 6, carbsG: 16, fatG: 7, fiberG: 1
        ),

        // — Panda Express — https://www.pandaexpress.com/nutritioninformation
        CommonFood(
            id: "ff-panda-orange-chicken", name: "Orange Chicken (Panda Express)",
            aliases: ["orange chicken", "panda express orange chicken", "panda orange chicken"],
            servingLabel: "1 serving (5.7 oz / 162 g)",
            calories: 370, proteinG: 19, carbsG: 38, fatG: 17, fiberG: 1
        ),
        CommonFood(
            id: "ff-panda-rangoon", name: "Cream Cheese Rangoon (Panda Express)",
            aliases: ["cream cheese rangoon", "crab rangoon", "rangoon", "cheese rangoon", "panda rangoon"],
            servingLabel: "3 pieces (78 g)",
            calories: 190, proteinG: 5, carbsG: 24, fatG: 8, fiberG: 2
        ),
        CommonFood(
            id: "ff-panda-chow-mein", name: "Chow Mein (Panda Express)",
            aliases: ["chow mein", "panda express chow mein", "panda chow mein"],
            servingLabel: "1 side (9.4 oz / 267 g)",
            calories: 510, proteinG: 13, carbsG: 80, fatG: 20, fiberG: 6
        ),

        // — Chick-fil-A — https://www.chick-fil-a.com/menu (values via fastfoodnutrition.org/chick-fil-a/*)
        CommonFood(
            id: "ff-cfa-chicken-sandwich", name: "Chick-fil-A Chicken Sandwich",
            aliases: ["chick fil a sandwich", "chick-fil-a chicken sandwich", "cfa sandwich", "chickfila sandwich"],
            servingLabel: "1 sandwich (183 g)",
            calories: 440, proteinG: 29, carbsG: 41, fatG: 17, fiberG: 1
        ),
        CommonFood(
            id: "ff-cfa-nuggets-8", name: "Chick-fil-A Nuggets (8 ct)",
            aliases: ["chick fil a nuggets", "chick-fil-a nuggets", "cfa nuggets", "chickfila nuggets", "8 count nuggets"],
            servingLabel: "8 count (113 g)",
            calories: 250, proteinG: 27, carbsG: 11, fatG: 11, fiberG: 0
        ),
        CommonFood(
            id: "ff-cfa-waffle-fries", name: "Chick-fil-A Waffle Fries",
            aliases: ["waffle fries", "chick fil a fries", "chick-fil-a waffle fries", "waffle potato fries"],
            servingLabel: "Medium (125 g)",
            calories: 420, proteinG: 5, carbsG: 45, fatG: 24, fiberG: 5
        ),

        // — Generic Chinese takeout — USDA FoodData Central SR Legacy
        //   "Restaurant, Chinese, …" rows (nutritionvalue.org mirrors the same data).
        //   Generic representatives, not any single restaurant's recipe.
        CommonFood(
            id: "ff-chinese-lo-mein", name: "Lo mein",
            // https://www.nutritionvalue.org/Restaurant,_without_meat,_vegetable_lo_mein,_Chinese_nutritional_value.html
            aliases: ["lo mein", "lomein", "vegetable lo mein", "chinese lo mein"],
            servingLabel: "1 cup (136 g)",
            calories: 165, proteinG: 7, carbsG: 28, fatG: 3, fiberG: 2
        ),
        CommonFood(
            id: "ff-chinese-wonton-soup", name: "Wonton soup",
            // https://www.nutritionvalue.org/Soup,_Chinese_restaurant,_wonton_nutritional_value.html
            aliases: ["wonton soup", "wanton soup", "won ton soup"],
            servingLabel: "1 cup (223 g)",
            calories: 71, proteinG: 5, carbsG: 12, fatG: 1, fiberG: 1
        ),
        CommonFood(
            id: "ff-chinese-fried-rice", name: "Vegetable fried rice",
            // https://www.nutritionvalue.org/Restaurant,_without_meat,_fried_rice,_Chinese_nutritional_value.html
            aliases: ["fried rice", "vegetable fried rice", "chinese fried rice", "veggie fried rice"],
            servingLabel: "1 cup (137 g)",
            calories: 238, proteinG: 6, carbsG: 45, fatG: 4, fiberG: 2
        ),
        CommonFood(
            id: "ff-chinese-beef-broccoli", name: "Beef and broccoli",
            // https://www.nutritionvalue.org/Beef_and_broccoli_27415110_nutritional_value.html
            aliases: ["beef and broccoli", "beef broccoli", "beef with broccoli", "beef & broccoli"],
            servingLabel: "1 cup (217 g)",
            calories: 347, proteinG: 23, carbsG: 11, fatG: 23, fiberG: 3
        ),
        CommonFood(
            id: "ff-chinese-general-tso", name: "General Tso's chicken",
            // https://www.nutritionvalue.org/Restaurant,_general_tso's_chicken,_Chinese_nutritional_value.html
            aliases: ["general tso", "general tso's chicken", "general tsos chicken", "general tao chicken"],
            servingLabel: "1 cup (163 g)",
            calories: 482, proteinG: 21, carbsG: 39, fatG: 27, fiberG: 1
        ),
    ]

    // MARK: - Lookup

    /// Returns the best match for `keyword` against name and aliases (case-insensitive).
    public static func find(_ keyword: String) -> CommonFood? {
        let q = keyword.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        // Prefer exact alias match, then substring
        return all.first { food in
            food.aliases.contains { $0.lowercased() == q }
        } ?? all.first { food in
            food.name.lowercased() == q
        } ?? all.first { food in
            food.aliases.contains { $0.lowercased().contains(q) || q.contains($0.lowercased()) }
        } ?? all.first { food in
            food.name.lowercased().contains(q)
        }
    }
}
