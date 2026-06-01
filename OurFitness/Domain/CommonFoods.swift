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

public struct CommonFood: Sendable, Equatable {
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
            aliases: ["sweet potato", "yam", "sweet potato"],
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
            aliases: ["fries", "french fries", "chips"],
            servingLabel: "Medium serving (117 g)",
            calories: 365, proteinG: 4, carbsG: 48, fatG: 17, fiberG: 4
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
