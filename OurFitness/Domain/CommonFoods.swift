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
        + snacksAndSweets + fastFood + condiments + deli + sushiExtended

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
        CommonFood(
            id: "corn-tortilla", name: "Corn tortilla",
            // USDA FDC #1100186
            aliases: ["corn tortilla", "corn taco shell", "taco shell"],
            servingLabel: "1 medium 6\" (28 g)",
            calories: 58, proteinG: 1, carbsG: 12, fatG: 1, fiberG: 1
        ),
        CommonFood(
            id: "udon-noodles", name: "Udon noodles",
            // USDA FDC #169884
            aliases: ["udon", "udon noodles", "thick udon"],
            servingLabel: "1 cup cooked (200 g)",
            calories: 210, proteinG: 7, carbsG: 42, fatG: 1, fiberG: 2
        ),
        CommonFood(
            id: "soba-noodles", name: "Soba noodles",
            // USDA FDC #169898
            aliases: ["soba", "soba noodles", "buckwheat noodles"],
            servingLabel: "1 cup cooked (115 g)",
            calories: 113, proteinG: 6, carbsG: 24, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "rice-noodles", name: "Rice noodles",
            // USDA FDC #168869
            aliases: ["rice noodles", "vermicelli", "glass noodles", "rice vermicelli", "bun noodles"],
            servingLabel: "1 cup cooked (176 g)",
            calories: 192, proteinG: 3, carbsG: 44, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "pita-bread", name: "Pita bread",
            // USDA FDC #168006
            aliases: ["pita", "pita bread", "flatbread", "pita pocket"],
            servingLabel: "1 large (60 g)",
            calories: 165, proteinG: 5, carbsG: 33, fatG: 1, fiberG: 2
        ),
        CommonFood(
            id: "bagel-plain", name: "Bagel",
            // USDA FDC #172734
            aliases: ["bagel", "plain bagel", "everything bagel", "sesame bagel", "onion bagel"],
            servingLabel: "1 medium (98 g)",
            calories: 270, proteinG: 10, carbsG: 53, fatG: 2, fiberG: 2
        ),
        CommonFood(
            id: "english-muffin", name: "English muffin",
            // USDA FDC #173275
            aliases: ["english muffin", "english muffins"],
            servingLabel: "1 muffin (57 g)",
            calories: 134, proteinG: 4, carbsG: 25, fatG: 1, fiberG: 2
        ),
        CommonFood(
            id: "cornbread", name: "Cornbread",
            // USDA FDC #172678
            aliases: ["cornbread", "corn bread", "corn muffin"],
            servingLabel: "1 piece (60 g)",
            calories: 188, proteinG: 4, carbsG: 28, fatG: 7, fiberG: 1
        ),
        CommonFood(
            id: "arepa", name: "Arepa",
            aliases: ["arepa", "arepas", "colombian arepa", "venezuelan arepa"],
            servingLabel: "1 medium plain (100 g)",
            calories: 224, proteinG: 5, carbsG: 38, fatG: 6, fiberG: 3
        ),
        CommonFood(
            id: "pupusa", name: "Pupusa",
            aliases: ["pupusa", "pupusas", "salvadoran pupusa"],
            servingLabel: "1 pupusa with cheese (100 g)",
            calories: 218, proteinG: 6, carbsG: 32, fatG: 7, fiberG: 2
        ),
        CommonFood(
            id: "rice-cakes", name: "Rice cakes",
            // USDA FDC #172879
            aliases: ["rice cakes", "rice cake", "plain rice cakes"],
            servingLabel: "2 cakes (18 g)",
            calories: 70, proteinG: 1, carbsG: 15, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "chapati-roti", name: "Chapati / Roti",
            aliases: ["chapati", "roti", "chapatti", "whole wheat roti"],
            servingLabel: "1 medium (45 g)",
            calories: 120, proteinG: 4, carbsG: 22, fatG: 2, fiberG: 3
        ),
        CommonFood(
            id: "sourdough-bread", name: "Sourdough bread",
            // USDA FDC #172686
            aliases: ["sourdough", "sourdough bread", "sourdough toast", "slice of sourdough"],
            servingLabel: "1 slice (36 g)",
            calories: 88, proteinG: 3, carbsG: 18, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "farro", name: "Farro",
            // USDA FDC #169721
            aliases: ["farro", "emmer wheat", "spelt"],
            servingLabel: "1 cup cooked (200 g)",
            calories: 220, proteinG: 8, carbsG: 46, fatG: 2, fiberG: 4
        ),
        CommonFood(
            id: "barley", name: "Barley",
            // USDA FDC #170283
            aliases: ["barley", "pearl barley", "barley grain"],
            servingLabel: "1 cup cooked (157 g)",
            calories: 193, proteinG: 4, carbsG: 44, fatG: 1, fiberG: 6
        ),
        CommonFood(
            id: "bulgur-wheat", name: "Bulgur wheat",
            // USDA FDC #169722
            aliases: ["bulgur", "bulgur wheat", "cracked wheat"],
            servingLabel: "1 cup cooked (182 g)",
            calories: 151, proteinG: 6, carbsG: 34, fatG: 0, fiberG: 8
        ),
        CommonFood(
            id: "polenta", name: "Polenta",
            // USDA FDC #170289 (cornmeal mush)
            aliases: ["polenta", "grits", "cornmeal mush", "corn porridge"],
            servingLabel: "1 cup cooked (240 g)",
            calories: 145, proteinG: 3, carbsG: 31, fatG: 1, fiberG: 2
        ),
        CommonFood(
            id: "puff-pastry", name: "Puff pastry",
            aliases: ["puff pastry", "pastry dough", "croissant dough"],
            servingLabel: "1 sheet (50 g)",
            calories: 207, proteinG: 3, carbsG: 18, fatG: 14, fiberG: 1
        ),
        CommonFood(
            id: "couscous", name: "Couscous",
            // USDA FDC #169720
            aliases: ["couscous", "moroccan couscous", "semolina couscous", "israeli couscous", "pearl couscous"],
            servingLabel: "1 cup cooked (157 g)",
            calories: 176, proteinG: 6, carbsG: 36, fatG: 0, fiberG: 2
        ),
        CommonFood(
            id: "sticky-rice", name: "Sticky rice",
            aliases: ["sticky rice", "glutinous rice", "sweet rice", "malagkit", "thai sticky rice", "mochigome"],
            servingLabel: "1 cup cooked (186 g)",
            calories: 169, proteinG: 4, carbsG: 37, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "paratha", name: "Paratha",
            aliases: ["paratha", "plain paratha", "indian paratha", "layered flatbread"],
            servingLabel: "1 piece (80 g)",
            calories: 200, proteinG: 4, carbsG: 26, fatG: 9, fiberG: 2
        ),
        CommonFood(
            id: "aloo-paratha", name: "Aloo paratha",
            aliases: ["aloo paratha", "stuffed paratha", "potato paratha", "aloo ka paratha", "potato stuffed flatbread"],
            servingLabel: "1 piece (120 g)",
            calories: 280, proteinG: 6, carbsG: 36, fatG: 12, fiberG: 3
        ),
        CommonFood(
            id: "pan-de-bono", name: "Pan de bono",
            aliases: ["pan de bono", "colombian cheese bread", "pan de queso colombiano", "bono bread"],
            servingLabel: "2 pieces (80 g)",
            calories: 240, proteinG: 7, carbsG: 34, fatG: 9, fiberG: 1
        ),
        CommonFood(
            id: "pao-de-queijo", name: "Pão de queijo",
            aliases: ["pao de queijo", "pão de queijo", "brazilian cheese bread", "cheese bread brazil", "tapioca cheese bread"],
            servingLabel: "3 pieces (60 g)",
            calories: 190, proteinG: 5, carbsG: 26, fatG: 8, fiberG: 0
        ),

        // — Breakfast cereals — values from box nutrition labels
        CommonFood(
            id: "cereal-cheerios", name: "Cheerios",
            aliases: ["cheerios", "plain cheerios", "original cheerios"],
            servingLabel: "1 cup (28 g) dry",
            calories: 100, proteinG: 3, carbsG: 20, fatG: 2, fiberG: 3
        ),
        CommonFood(
            id: "cereal-honey-nut-cheerios", name: "Honey Nut Cheerios",
            aliases: ["honey nut cheerios", "honey cheerios", "hn cheerios"],
            servingLabel: "¾ cup (28 g) dry",
            calories: 110, proteinG: 2, carbsG: 22, fatG: 2, fiberG: 2
        ),
        CommonFood(
            id: "cereal-frosted-flakes", name: "Frosted Flakes",
            aliases: ["frosted flakes", "kelloggs frosted flakes", "tony the tiger cereal"],
            servingLabel: "¾ cup (30 g) dry",
            calories: 130, proteinG: 1, carbsG: 30, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "cereal-corn-flakes", name: "Corn Flakes",
            aliases: ["corn flakes", "kelloggs corn flakes", "cornflakes"],
            servingLabel: "1 cup (28 g) dry",
            calories: 100, proteinG: 2, carbsG: 24, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "cereal-special-k", name: "Special K",
            aliases: ["special k", "special k cereal", "kelloggs special k"],
            servingLabel: "1 cup (31 g) dry",
            calories: 120, proteinG: 6, carbsG: 22, fatG: 1, fiberG: 1
        ),
        CommonFood(
            id: "cereal-cinnamon-toast-crunch", name: "Cinnamon Toast Crunch",
            aliases: ["cinnamon toast crunch", "ctc cereal", "cinnamon crunch"],
            servingLabel: "¾ cup (31 g) dry",
            calories: 130, proteinG: 2, carbsG: 25, fatG: 3, fiberG: 1
        ),
        CommonFood(
            id: "cereal-lucky-charms", name: "Lucky Charms",
            aliases: ["lucky charms", "lucky charms cereal"],
            servingLabel: "¾ cup (27 g) dry",
            calories: 110, proteinG: 2, carbsG: 22, fatG: 1, fiberG: 2
        ),
        CommonFood(
            id: "cereal-frosted-mini-wheats", name: "Frosted Mini-Wheats",
            aliases: ["frosted mini wheats", "mini wheats", "mini-wheats"],
            servingLabel: "24 biscuits (59 g) dry",
            calories: 200, proteinG: 5, carbsG: 47, fatG: 1, fiberG: 6
        ),
        CommonFood(
            id: "cereal-raisin-bran", name: "Raisin Bran",
            aliases: ["raisin bran", "kelloggs raisin bran", "raisin bran cereal"],
            servingLabel: "1 cup (59 g) dry",
            calories: 190, proteinG: 5, carbsG: 46, fatG: 1, fiberG: 7
        ),
        CommonFood(
            id: "cereal-capn-crunch", name: "Cap'n Crunch",
            aliases: ["cap n crunch", "captain crunch", "capn crunch", "crunch berries"],
            servingLabel: "¾ cup (27 g) dry",
            calories: 110, proteinG: 1, carbsG: 23, fatG: 2, fiberG: 1
        ),
        CommonFood(
            id: "cereal-froot-loops", name: "Froot Loops",
            aliases: ["froot loops", "fruit loops", "kelloggs froot loops"],
            servingLabel: "1 cup (29 g) dry",
            calories: 110, proteinG: 1, carbsG: 25, fatG: 1, fiberG: 3
        ),
        CommonFood(
            id: "eggo-waffle", name: "Eggo frozen waffles",
            // Kellogg's Eggo Homestyle waffles label
            aliases: ["eggo", "eggo waffle", "eggo waffles", "frozen waffle", "toaster waffle", "leggo my eggo"],
            servingLabel: "2 waffles (70 g)",
            calories: 180, proteinG: 4, carbsG: 30, fatG: 5, fiberG: 1
        ),
        CommonFood(
            id: "instant-oatmeal-packet", name: "Instant oatmeal packet",
            // Quaker Original instant oatmeal
            aliases: ["instant oatmeal", "quaker oatmeal", "oatmeal packet", "maple brown sugar oatmeal", "oatmeal instant"],
            servingLabel: "1 packet (28 g dry)",
            calories: 100, proteinG: 4, carbsG: 19, fatG: 2, fiberG: 3
        ),
        CommonFood(
            id: "arroz-con-coco", name: "Arroz con coco",
            aliases: ["arroz con coco", "colombian coconut rice", "coconut rice caribbean colombian", "arroz de coco titote"],
            servingLabel: "1 cup (180 g)",
            calories: 330, proteinG: 5, carbsG: 50, fatG: 12, fiberG: 2
        ),
        CommonFood(
            id: "mazamorra-antioquena", name: "Mazamorra antioqueña",
            aliases: ["mazamorra antioquena", "colombian corn milk pudding", "mazamorra paisa", "hominy milk dessert colombian"],
            servingLabel: "1 bowl (250 g)",
            calories: 200, proteinG: 7, carbsG: 35, fatG: 4, fiberG: 2
        ),
        CommonFood(
            id: "bunuelo-colombiano", name: "Buñuelo colombiano",
            aliases: ["bunuelo colombiano", "colombian cheese fritter", "bunuelo de navidad", "fried cheese dough ball colombian"],
            servingLabel: "1 buñuelo (50 g)",
            calories: 190, proteinG: 5, carbsG: 18, fatG: 11, fiberG: 1
        ),
        CommonFood(
            id: "almojabana", name: "Almojábana",
            aliases: ["almojabana", "colombian cheese bread roll", "almojabanas", "cheese cornmeal roll colombian"],
            servingLabel: "1 roll (70 g)",
            calories: 210, proteinG: 7, carbsG: 25, fatG: 9, fiberG: 1
        ),
        CommonFood(
            id: "pandeyuca", name: "Pandeyuca",
            aliases: ["pandeyuca", "colombian cassava cheese bread", "pan de yuca colombiano", "yuca starch cheese roll"],
            servingLabel: "1 roll (45 g)",
            calories: 150, proteinG: 4, carbsG: 16, fatG: 7, fiberG: 1
        ),
        CommonFood(
            id: "roscon-bogotano", name: "Roscón bogotano",
            aliases: ["roscon bogotano", "colombian guava pastry", "roscon de arequipe", "guava filled bread ring colombian"],
            servingLabel: "1 roscón (110 g)",
            calories: 340, proteinG: 7, carbsG: 56, fatG: 10, fiberG: 2
        ),
        CommonFood(
            id: "ensaymada", name: "Ensaymada",
            aliases: ["filipino sweet bread", "ensaymada cheese", "buttery brioche roll filipino", "sugar cheese pastry"],
            servingLabel: "1 piece (90 g)",
            calories: 330, proteinG: 6, carbsG: 40, fatG: 16, fiberG: 1
        ),
        CommonFood(
            id: "pandesal", name: "Pandesal",
            aliases: ["filipino bread rolls", "pan de sal", "breakfast salt bread", "pinoy dinner rolls"],
            servingLabel: "2 pieces (70 g)",
            calories: 150, proteinG: 4, carbsG: 28, fatG: 2, fiberG: 1
        ),
        CommonFood(
            id: "spanish-bread", name: "Spanish bread",
            aliases: ["filipino spanish bread", "sweet butter roll filipino", "senorita bread", "breadcrumb filled roll"],
            servingLabel: "1 piece (60 g)",
            calories: 220, proteinG: 4, carbsG: 32, fatG: 8, fiberG: 1
        ),
        CommonFood(
            id: "instant-grits", name: "Grits (instant)",
            // Quaker official
            aliases: ["instant grits", "quaker grits packet", "cooked grits"],
            servingLabel: "1 packet prepared (28 g dry)",
            calories: 100, proteinG: 2, carbsG: 22, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "cream-of-wheat", name: "Cream of Wheat (instant)",
            // Cream of Wheat official
            aliases: ["cream of wheat", "instant farina", "cream of wheat packet"],
            servingLabel: "1 packet prepared (33 g)",
            calories: 130, proteinG: 4, carbsG: 28, fatG: 0, fiberG: 1
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
        CommonFood(
            id: "bacon", name: "Bacon",
            // USDA FDC #168318 (pan-fried, 3 strips / 30 g cooked)
            aliases: ["bacon", "crispy bacon", "streaky bacon", "back bacon"],
            servingLabel: "3 strips cooked (30 g)",
            calories: 130, proteinG: 9, carbsG: 0, fatG: 11, fiberG: 0
        ),
        CommonFood(
            id: "pulled-pork", name: "Pulled pork",
            aliases: ["pulled pork", "bbq pulled pork", "slow cooker pork"],
            servingLabel: "3 oz (85 g)",
            calories: 200, proteinG: 22, carbsG: 3, fatG: 11, fiberG: 0
        ),
        CommonFood(
            id: "bbq-ribs", name: "BBQ ribs",
            // USDA FDC #167958
            aliases: ["ribs", "bbq ribs", "baby back ribs", "pork ribs", "spare ribs"],
            servingLabel: "3 oz cooked (85 g)",
            calories: 292, proteinG: 20, carbsG: 8, fatG: 20, fiberG: 0
        ),
        CommonFood(
            id: "lamb-chop", name: "Lamb chop",
            // USDA FDC #174049
            aliases: ["lamb chop", "lamb", "rack of lamb", "grilled lamb"],
            servingLabel: "3 oz cooked (85 g)",
            calories: 250, proteinG: 21, carbsG: 0, fatG: 18, fiberG: 0
        ),
        CommonFood(
            id: "duck-breast", name: "Duck breast",
            // USDA FDC #171478
            aliases: ["duck", "duck breast", "roast duck", "peking duck"],
            servingLabel: "3 oz cooked (85 g)",
            calories: 172, proteinG: 20, carbsG: 0, fatG: 10, fiberG: 0
        ),
        CommonFood(
            id: "crab", name: "Crab",
            // USDA FDC #174202
            aliases: ["crab", "crab legs", "snow crab", "dungeness crab", "king crab"],
            servingLabel: "3 oz cooked (85 g)",
            calories: 87, proteinG: 17, carbsG: 0, fatG: 2, fiberG: 0
        ),
        CommonFood(
            id: "lobster", name: "Lobster",
            // USDA FDC #175183
            aliases: ["lobster", "lobster tail", "lobster meat"],
            servingLabel: "3 oz cooked (85 g)",
            calories: 83, proteinG: 17, carbsG: 1, fatG: 1, fiberG: 0
        ),
        CommonFood(
            id: "scallops", name: "Scallops",
            // USDA FDC #175183
            aliases: ["scallop", "scallops", "pan seared scallops", "sea scallops"],
            servingLabel: "3 oz cooked (85 g)",
            calories: 95, proteinG: 18, carbsG: 5, fatG: 1, fiberG: 0
        ),
        CommonFood(
            id: "mussels", name: "Mussels",
            // USDA FDC #174184
            aliases: ["mussels", "mussel", "steamed mussels"],
            servingLabel: "3 oz cooked (85 g)",
            calories: 146, proteinG: 20, carbsG: 6, fatG: 4, fiberG: 0
        ),
        CommonFood(
            id: "sardines", name: "Sardines (canned)",
            // USDA FDC #175139
            aliases: ["sardines", "canned sardines", "sardine"],
            servingLabel: "1 can drained (92 g)",
            calories: 191, proteinG: 23, carbsG: 0, fatG: 11, fiberG: 0
        ),
        CommonFood(
            id: "beef-jerky", name: "Beef jerky",
            // USDA FDC #174440
            aliases: ["beef jerky", "jerky", "meat jerky"],
            servingLabel: "1 oz (28 g)",
            calories: 116, proteinG: 10, carbsG: 4, fatG: 7, fiberG: 0
        ),
        CommonFood(
            id: "pastrami", name: "Pastrami",
            // USDA FDC #172961
            aliases: ["pastrami", "deli pastrami"],
            servingLabel: "2 oz deli (57 g)",
            calories: 80, proteinG: 10, carbsG: 2, fatG: 4, fiberG: 0
        ),
        CommonFood(
            id: "seitan", name: "Seitan",
            aliases: ["seitan", "wheat gluten", "vital wheat gluten"],
            servingLabel: "3 oz (85 g)",
            calories: 104, proteinG: 21, carbsG: 4, fatG: 1, fiberG: 0
        ),
        CommonFood(
            id: "tilapia", name: "Tilapia",
            // USDA FDC #175174
            aliases: ["tilapia", "baked tilapia"],
            servingLabel: "4 oz cooked (113 g)",
            calories: 145, proteinG: 30, carbsG: 0, fatG: 3, fiberG: 0
        ),
        CommonFood(
            id: "cod", name: "Cod",
            // USDA FDC #175160
            aliases: ["cod", "atlantic cod", "baked cod"],
            servingLabel: "4 oz cooked (113 g)",
            calories: 119, proteinG: 26, carbsG: 0, fatG: 1, fiberG: 0
        ),
        CommonFood(
            id: "halibut", name: "Halibut",
            // USDA FDC #175161
            aliases: ["halibut", "grilled halibut"],
            servingLabel: "4 oz cooked (113 g)",
            calories: 159, proteinG: 30, carbsG: 0, fatG: 3, fiberG: 0
        ),
        CommonFood(
            id: "mahi-mahi", name: "Mahi-mahi",
            // USDA FDC #175147
            aliases: ["mahi mahi", "mahi-mahi", "dorado", "dolphinfish"],
            servingLabel: "4 oz cooked (113 g)",
            calories: 124, proteinG: 27, carbsG: 0, fatG: 1, fiberG: 0
        ),
        CommonFood(
            id: "oysters", name: "Oysters",
            // USDA FDC #175168
            aliases: ["oysters", "oyster", "raw oysters", "steamed oysters"],
            servingLabel: "3 oz (85 g, ~6 medium)",
            calories: 69, proteinG: 8, carbsG: 4, fatG: 2, fiberG: 0
        ),
        CommonFood(
            id: "clams-steamed", name: "Clams",
            // USDA FDC #175159
            aliases: ["clams", "clam", "steamed clams", "littleneck clams"],
            servingLabel: "3 oz (85 g)",
            calories: 63, proteinG: 11, carbsG: 2, fatG: 1, fiberG: 0
        ),
        CommonFood(
            id: "beyond-burger", name: "Beyond Burger",
            // Beyond Meat official: 1 patty (113 g)
            aliases: ["beyond burger", "beyond meat", "plant based burger", "impossible burger", "veggie burger"],
            servingLabel: "1 patty (113 g)",
            calories: 250, proteinG: 20, carbsG: 3, fatG: 18, fiberG: 2
        ),
        CommonFood(
            id: "lamb-gyro-meat", name: "Gyro meat (lamb/beef)",
            aliases: ["gyro meat", "doner meat", "doner kebab meat", "shawarma meat"],
            servingLabel: "3 oz (85 g)",
            calories: 216, proteinG: 20, carbsG: 1, fatG: 14, fiberG: 0
        ),
        CommonFood(
            id: "chicharron-colombiano", name: "Chicharrón colombiano",
            aliases: ["chicharron colombiano", "colombian fried pork belly", "chicharron paisa", "crispy pork belly colombian"],
            servingLabel: "1 piece (90 g)",
            calories: 420, proteinG: 22, carbsG: 0, fatG: 37, fiberG: 0
        ),
        CommonFood(
            id: "tyson-chicken-nuggets", name: "Frozen chicken nuggets (Tyson, 5)",
            // Tyson official
            aliases: ["tyson chicken nuggets", "frozen chicken nuggets", "breaded chicken nuggets"],
            servingLabel: "5 nuggets (85 g)",
            calories: 270, proteinG: 13, carbsG: 15, fatG: 17, fiberG: 1
        ),
        CommonFood(
            id: "fish-sticks-frozen", name: "Fish sticks (6)",
            // Gorton's official
            aliases: ["fish sticks", "frozen fish sticks", "breaded fish sticks", "gorton's fish sticks"],
            servingLabel: "6 sticks (114 g)",
            calories: 290, proteinG: 13, carbsG: 20, fatG: 16, fiberG: 1
        ),
        CommonFood(
            id: "vienna-sausages-can", name: "Vienna sausages (can)",
            // Libby's official
            aliases: ["vienna sausages", "canned vienna sausage", "libby's vienna sausages"],
            servingLabel: "1 can (130 g)",
            calories: 230, proteinG: 9, carbsG: 2, fatG: 21, fiberG: 0
        ),
        CommonFood(
            id: "jimmy-dean-sausage-links", name: "Jimmy Dean breakfast sausage links (2)",
            // Jimmy Dean official
            aliases: ["jimmy dean sausage links", "breakfast sausage links", "pork breakfast links"],
            servingLabel: "2 links (45 g)",
            calories: 170, proteinG: 7, carbsG: 1, fatG: 15, fiberG: 0
        ),
        CommonFood(
            id: "bologna", name: "Bologna",
            // USDA FDC #174625
            aliases: ["beef bologna", "baloney slices", "bologna deli meat", "pork bologna"],
            servingLabel: "1 oz slice (28 g)",
            calories: 88, proteinG: 3, carbsG: 1, fatG: 8, fiberG: 0
        ),
        CommonFood(
            id: "mortadella", name: "Mortadella",
            // USDA FDC #172846
            aliases: ["italian mortadella", "mortadella deli", "bologna with pistachios"],
            servingLabel: "2 oz (57 g)",
            calories: 200, proteinG: 8, carbsG: 2, fatG: 18, fiberG: 0
        ),
        CommonFood(
            id: "capicola", name: "Capicola",
            // Boar's Head official
            aliases: ["capocollo deli", "hot capicola", "coppa cured pork", "gabagool"],
            servingLabel: "1 oz (28 g)",
            calories: 60, proteinG: 8, carbsG: 0, fatG: 3, fiberG: 0
        ),
        CommonFood(
            id: "prosciutto", name: "Prosciutto",
            // USDA FDC #168334
            aliases: ["prosciutto di parma", "italian dry cured ham", "prosciutto crudo"],
            servingLabel: "1 oz (28 g)",
            calories: 70, proteinG: 8, carbsG: 0, fatG: 4, fiberG: 0
        ),
        CommonFood(
            id: "roast-turkey-breast-deli", name: "Roast turkey breast (deli)",
            // Boar's Head official
            aliases: ["oven roasted turkey breast", "roasted deli turkey", "low sodium turkey breast"],
            servingLabel: "2 oz (57 g)",
            calories: 50, proteinG: 10, carbsG: 1, fatG: 1, fiberG: 0
        ),
        CommonFood(
            id: "honey-ham-deli", name: "Honey ham (deli)",
            // Boar's Head official
            aliases: ["honey baked ham deli", "sweet sliced ham", "honey glazed deli ham"],
            servingLabel: "2 oz (57 g)",
            calories: 70, proteinG: 10, carbsG: 3, fatG: 2, fiberG: 0
        ),
        CommonFood(
            id: "genoa-salami", name: "Genoa salami",
            // USDA FDC #172847
            aliases: ["genoa hard salami", "italian dry salami", "genoa deli salami"],
            servingLabel: "1 oz (28 g)",
            calories: 110, proteinG: 6, carbsG: 1, fatG: 9, fiberG: 0
        ),
        CommonFood(
            id: "liverwurst", name: "Liverwurst",
            // USDA FDC #167537
            aliases: ["braunschweiger spread", "liver sausage", "pork liverwurst"],
            servingLabel: "1 oz (28 g)",
            calories: 92, proteinG: 4, carbsG: 1, fatG: 8, fiberG: 0
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
        CommonFood(
            id: "cream-cheese", name: "Cream cheese",
            // USDA FDC #172179
            aliases: ["cream cheese", "philadelphia cream cheese"],
            servingLabel: "2 tbsp (29 g)",
            calories: 99, proteinG: 2, carbsG: 1, fatG: 10, fiberG: 0
        ),
        CommonFood(
            id: "butter", name: "Butter",
            // USDA FDC #173430
            aliases: ["butter", "salted butter", "unsalted butter"],
            servingLabel: "1 tbsp (14 g)",
            calories: 102, proteinG: 0, carbsG: 0, fatG: 12, fiberG: 0
        ),
        CommonFood(
            id: "mozzarella-fresh", name: "Fresh mozzarella",
            // USDA FDC #171241
            aliases: ["mozzarella", "fresh mozzarella", "buffalo mozzarella"],
            servingLabel: "1 oz (28 g)",
            calories: 85, proteinG: 6, carbsG: 1, fatG: 6, fiberG: 0
        ),
        CommonFood(
            id: "parmesan", name: "Parmesan cheese",
            // USDA FDC #171244
            aliases: ["parmesan", "parmigiano", "grated parmesan", "parmesan cheese"],
            servingLabel: "1 oz (28 g)",
            calories: 111, proteinG: 10, carbsG: 1, fatG: 7, fiberG: 0
        ),
        CommonFood(
            id: "ricotta", name: "Ricotta cheese",
            // USDA FDC #171271
            aliases: ["ricotta", "ricotta cheese", "whole milk ricotta"],
            servingLabel: "½ cup (124 g)",
            calories: 216, proteinG: 14, carbsG: 4, fatG: 16, fiberG: 0
        ),
        CommonFood(
            id: "swiss-cheese", name: "Swiss cheese",
            // USDA FDC #171262
            aliases: ["swiss cheese", "swiss", "emmental"],
            servingLabel: "1 oz (28 g)",
            calories: 111, proteinG: 8, carbsG: 2, fatG: 9, fiberG: 0
        ),
        CommonFood(
            id: "brie", name: "Brie",
            // USDA FDC #171245
            aliases: ["brie", "brie cheese", "camembert"],
            servingLabel: "1 oz (28 g)",
            calories: 95, proteinG: 6, carbsG: 0, fatG: 8, fiberG: 0
        ),
        CommonFood(
            id: "heavy-cream", name: "Heavy cream",
            // USDA FDC #170859
            aliases: ["heavy cream", "heavy whipping cream", "double cream", "whipping cream"],
            servingLabel: "2 tbsp (30 ml)",
            calories: 101, proteinG: 1, carbsG: 1, fatG: 11, fiberG: 0
        ),
        CommonFood(
            id: "half-and-half", name: "Half and half",
            // USDA FDC #170860
            aliases: ["half and half", "half & half", "creamer"],
            servingLabel: "2 tbsp (30 ml)",
            calories: 39, proteinG: 1, carbsG: 1, fatG: 3, fiberG: 0
        ),
        CommonFood(
            id: "yoplait-yogurt-cup", name: "Yoplait yogurt cup",
            // Yoplait official
            aliases: ["yoplait original", "yoplait strawberry yogurt", "yoplait cup"],
            servingLabel: "1 cup (170 g)",
            calories: 150, proteinG: 5, carbsG: 25, fatG: 2, fiberG: 0
        ),
        CommonFood(
            id: "chobani-flip-yogurt", name: "Chobani Flip yogurt",
            // Chobani official
            aliases: ["chobani flip", "flip yogurt cup", "chobani greek flip"],
            servingLabel: "1 cup (149 g)",
            calories: 220, proteinG: 12, carbsG: 32, fatG: 5, fiberG: 1
        ),
        CommonFood(
            id: "kraft-american-single", name: "Kraft American single",
            // Kraft official
            aliases: ["kraft american single", "american cheese slice", "kraft cheese single", "processed cheese slice"],
            servingLabel: "1 slice (21 g)",
            calories: 60, proteinG: 3, carbsG: 2, fatG: 4, fiberG: 0
        ),
        CommonFood(
            id: "provolone", name: "Provolone",
            // USDA FDC #173430
            aliases: ["provolone cheese slice", "sharp provolone", "aged provolone"],
            servingLabel: "1 oz slice (28 g)",
            calories: 100, proteinG: 7, carbsG: 1, fatG: 8, fiberG: 0
        ),
        CommonFood(
            id: "pepper-jack", name: "Pepper jack cheese",
            // Tillamook official
            aliases: ["pepper jack slice", "monterey pepper jack", "spicy jack cheese"],
            servingLabel: "1 oz slice (28 g)",
            calories: 110, proteinG: 6, carbsG: 1, fatG: 9, fiberG: 0
        ),
        CommonFood(
            id: "muenster", name: "Muenster cheese",
            // USDA FDC #173427
            aliases: ["muenster slice", "munster cheese", "deli muenster"],
            servingLabel: "1 oz slice (28 g)",
            calories: 100, proteinG: 7, carbsG: 0, fatG: 8, fiberG: 0
        ),
        CommonFood(
            id: "gouda-slice", name: "Gouda cheese slice",
            // USDA FDC #173420
            aliases: ["smoked gouda slice", "gouda deli cheese", "aged gouda"],
            servingLabel: "1 oz slice (28 g)",
            calories: 101, proteinG: 7, carbsG: 1, fatG: 8, fiberG: 0
        ),
        CommonFood(
            id: "havarti", name: "Havarti cheese",
            // Boar's Head official
            aliases: ["dill havarti", "creamy havarti slice", "danish havarti"],
            servingLabel: "1 oz slice (28 g)",
            calories: 105, proteinG: 6, carbsG: 0, fatG: 9, fiberG: 0
        ),
        CommonFood(
            id: "american-cheese-slice", name: "American cheese slice",
            // Kraft Singles official
            aliases: ["american cheese single", "processed american slice", "yellow american cheese"],
            servingLabel: "1 slice (21 g)",
            calories: 60, proteinG: 3, carbsG: 2, fatG: 4, fiberG: 0
        ),
        CommonFood(
            id: "colby-jack", name: "Colby jack cheese",
            // Tillamook official
            aliases: ["colby jack slice", "co jack cheese", "marbled colby monterey"],
            servingLabel: "1 oz (28 g)",
            calories: 110, proteinG: 7, carbsG: 1, fatG: 9, fiberG: 0
        ),
        CommonFood(
            id: "goat-cheese", name: "Goat cheese",
            aliases: ["goat cheese", "chevre", "soft goat cheese"],
            servingLabel: "1 oz (28 g)",
            calories: 75, proteinG: 5, carbsG: 0, fatG: 6, fiberG: 0
        ),
        CommonFood(
            id: "halloumi", name: "Halloumi",
            aliases: ["halloumi", "grilling cheese", "halloumi cheese"],
            servingLabel: "1 oz (28 g)",
            calories: 90, proteinG: 6, carbsG: 1, fatG: 7, fiberG: 0
        ),
        CommonFood(
            id: "queso-fresco", name: "Queso fresco",
            aliases: ["queso fresco", "fresh mexican cheese", "queso blanco fresco"],
            servingLabel: "1 oz (28 g)",
            calories: 80, proteinG: 5, carbsG: 1, fatG: 6, fiberG: 0
        ),
        CommonFood(
            id: "cotija-cheese", name: "Cotija cheese",
            aliases: ["cotija", "cotija cheese", "mexican grating cheese"],
            servingLabel: "1 oz (28 g)",
            calories: 100, proteinG: 6, carbsG: 1, fatG: 8, fiberG: 0
        ),
        CommonFood(
            id: "blue-cheese-crumbles", name: "Blue cheese crumbles",
            aliases: ["blue cheese crumbles", "gorgonzola", "crumbled blue cheese"],
            servingLabel: "1 oz (28 g)",
            calories: 100, proteinG: 6, carbsG: 1, fatG: 8, fiberG: 0
        ),
        CommonFood(
            id: "manchego", name: "Manchego cheese",
            aliases: ["manchego", "manchego cheese", "spanish sheep cheese"],
            servingLabel: "1 oz (28 g)",
            calories: 110, proteinG: 7, carbsG: 0, fatG: 9, fiberG: 0
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
        CommonFood(
            id: "kale", name: "Kale",
            // USDA FDC #323505
            aliases: ["kale", "curly kale", "kale chips", "lacinato kale"],
            servingLabel: "1 cup chopped raw (67 g)",
            calories: 33, proteinG: 2, carbsG: 6, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "bell-pepper-red", name: "Bell pepper",
            // USDA FDC #170108
            aliases: ["bell pepper", "red pepper", "green pepper", "yellow pepper", "capsicum", "bell peppers"],
            servingLabel: "1 medium (119 g)",
            calories: 37, proteinG: 1, carbsG: 7, fatG: 0, fiberG: 3
        ),
        CommonFood(
            id: "mushrooms-button", name: "Mushrooms",
            // USDA FDC #169251
            aliases: ["mushrooms", "mushroom", "button mushroom", "white mushroom", "portobello", "cremini", "shiitake"],
            servingLabel: "1 cup sliced raw (70 g)",
            calories: 15, proteinG: 2, carbsG: 2, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "corn-kernels", name: "Corn",
            // USDA FDC #170416
            aliases: ["corn", "sweet corn", "corn kernels", "corn on the cob", "corn off the cob"],
            servingLabel: "1 cup kernels (154 g)",
            calories: 132, proteinG: 5, carbsG: 29, fatG: 2, fiberG: 3
        ),
        CommonFood(
            id: "green-beans", name: "Green beans",
            // USDA FDC #170383
            aliases: ["green beans", "green bean", "string beans", "snap beans", "haricot verts"],
            servingLabel: "1 cup (100 g)",
            calories: 31, proteinG: 2, carbsG: 7, fatG: 0, fiberG: 3
        ),
        CommonFood(
            id: "cauliflower", name: "Cauliflower",
            // USDA FDC #169986
            aliases: ["cauliflower", "cauli", "cauliflower rice", "riced cauliflower"],
            servingLabel: "1 cup chopped (107 g)",
            calories: 27, proteinG: 2, carbsG: 5, fatG: 0, fiberG: 3
        ),
        CommonFood(
            id: "cabbage-green", name: "Cabbage",
            // USDA FDC #169975
            aliases: ["cabbage", "green cabbage", "red cabbage", "napa cabbage", "shredded cabbage"],
            servingLabel: "1 cup shredded (70 g)",
            calories: 17, proteinG: 1, carbsG: 4, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "carrots", name: "Carrots",
            // USDA FDC #170393
            aliases: ["carrots", "carrot", "baby carrots"],
            servingLabel: "1 medium (61 g)",
            calories: 25, proteinG: 1, carbsG: 6, fatG: 0, fiberG: 2
        ),
        CommonFood(
            id: "beets", name: "Beets",
            // USDA FDC #169145
            aliases: ["beets", "beet", "roasted beets", "pickled beets"],
            servingLabel: "1 cup sliced cooked (170 g)",
            calories: 75, proteinG: 3, carbsG: 17, fatG: 0, fiberG: 3
        ),
        CommonFood(
            id: "asparagus", name: "Asparagus",
            // USDA FDC #168389
            aliases: ["asparagus", "grilled asparagus", "asparagus spears"],
            servingLabel: "1 cup (134 g)",
            calories: 27, proteinG: 3, carbsG: 5, fatG: 0, fiberG: 3
        ),
        CommonFood(
            id: "bok-choy", name: "Bok choy",
            // USDA FDC #169239
            aliases: ["bok choy", "pak choi", "chinese cabbage", "baby bok choy"],
            servingLabel: "1 cup shredded raw (70 g)",
            calories: 9, proteinG: 1, carbsG: 2, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "snow-peas", name: "Snow peas",
            // USDA FDC #170429
            aliases: ["snow peas", "sugar snap peas", "snap peas", "mangetout"],
            servingLabel: "1 cup (98 g)",
            calories: 41, proteinG: 3, carbsG: 7, fatG: 0, fiberG: 3
        ),
        CommonFood(
            id: "jalapeño", name: "Jalapeño",
            // USDA FDC #168585
            aliases: ["jalapeño", "jalapeno", "jalapeño pepper", "hot pepper"],
            servingLabel: "1 medium (45 g)",
            calories: 4, proteinG: 0, carbsG: 1, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "garlic", name: "Garlic",
            // USDA FDC #169230
            aliases: ["garlic", "garlic clove", "garlic cloves", "minced garlic"],
            servingLabel: "3 cloves (9 g)",
            calories: 13, proteinG: 1, carbsG: 3, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "ginger", name: "Ginger",
            // USDA FDC #169231
            aliases: ["ginger", "fresh ginger", "ginger root"],
            servingLabel: "1 tbsp grated (6 g)",
            calories: 4, proteinG: 0, carbsG: 1, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "artichoke", name: "Artichoke",
            // USDA FDC #169205
            aliases: ["artichoke", "artichoke hearts", "globe artichoke"],
            servingLabel: "1 medium cooked (120 g)",
            calories: 60, proteinG: 4, carbsG: 13, fatG: 0, fiberG: 6
        ),
        CommonFood(
            id: "swiss-chard", name: "Swiss chard",
            // USDA FDC #169991
            aliases: ["swiss chard", "chard", "rainbow chard"],
            servingLabel: "1 cup chopped raw (36 g)",
            calories: 7, proteinG: 1, carbsG: 1, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "butternut-squash", name: "Butternut squash",
            // USDA FDC #169310
            aliases: ["butternut squash", "squash", "roasted butternut squash", "winter squash"],
            servingLabel: "1 cup cubed (140 g)",
            calories: 63, proteinG: 1, carbsG: 16, fatG: 0, fiberG: 3
        ),
        CommonFood(
            id: "arugula", name: "Arugula",
            // USDA FDC #169387
            aliases: ["arugula", "rocket", "arugula salad"],
            servingLabel: "1 cup (20 g)",
            calories: 5, proteinG: 1, carbsG: 1, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "leeks", name: "Leeks",
            // USDA FDC #169246
            aliases: ["leek", "leeks"],
            servingLabel: "1 cup chopped (89 g)",
            calories: 54, proteinG: 1, carbsG: 13, fatG: 0, fiberG: 2
        ),
        CommonFood(
            id: "radish", name: "Radish",
            // USDA FDC #169276
            aliases: ["radish", "radishes", "daikon", "daikon radish"],
            servingLabel: "1 cup sliced (116 g)",
            calories: 19, proteinG: 1, carbsG: 4, fatG: 0, fiberG: 2
        ),
        CommonFood(
            id: "edamame-snack", name: "Edamame (in pod)",
            // USDA FDC #168411 — pod-on for snacking
            aliases: ["edamame in pod", "edamame snack", "edamame appetizer"],
            servingLabel: "1 cup in pod (155 g)",
            calories: 94, proteinG: 9, carbsG: 7, fatG: 4, fiberG: 4
        ),
        CommonFood(
            id: "okra", name: "Okra",
            aliases: ["okra", "ladies fingers", "bhindi"],
            servingLabel: "1 cup cooked (160 g)",
            calories: 35, proteinG: 3, carbsG: 7, fatG: 0, fiberG: 4
        ),
        CommonFood(
            id: "fennel-bulb", name: "Fennel",
            aliases: ["fennel", "fennel bulb", "anise bulb"],
            servingLabel: "1 cup sliced (87 g)",
            calories: 27, proteinG: 1, carbsG: 6, fatG: 0, fiberG: 3
        ),
        CommonFood(
            id: "parsnip", name: "Parsnip",
            aliases: ["parsnip", "parsnips"],
            servingLabel: "1 cup cooked (160 g)",
            calories: 111, proteinG: 2, carbsG: 27, fatG: 0, fiberG: 6
        ),
        CommonFood(
            id: "jicama", name: "Jicama",
            aliases: ["jicama", "yam bean", "mexican turnip"],
            servingLabel: "1 cup sliced (120 g)",
            calories: 46, proteinG: 1, carbsG: 11, fatG: 0, fiberG: 6
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
        CommonFood(
            id: "pineapple", name: "Pineapple",
            // USDA FDC #169124
            aliases: ["pineapple", "fresh pineapple", "pineapple chunks"],
            servingLabel: "1 cup diced (165 g)",
            calories: 82, proteinG: 1, carbsG: 21, fatG: 0, fiberG: 2
        ),
        CommonFood(
            id: "peach", name: "Peach",
            // USDA FDC #169928
            aliases: ["peach", "peaches", "fresh peach"],
            servingLabel: "1 medium (150 g)",
            calories: 59, proteinG: 1, carbsG: 14, fatG: 0, fiberG: 2
        ),
        CommonFood(
            id: "kiwi", name: "Kiwi",
            // USDA FDC #168153
            aliases: ["kiwi", "kiwifruit", "kiwi fruit", "green kiwi", "golden kiwi"],
            servingLabel: "2 medium (148 g)",
            calories: 92, proteinG: 2, carbsG: 22, fatG: 1, fiberG: 4
        ),
        CommonFood(
            id: "pear", name: "Pear",
            // USDA FDC #169118
            aliases: ["pear", "pears"],
            servingLabel: "1 medium (178 g)",
            calories: 101, proteinG: 1, carbsG: 27, fatG: 0, fiberG: 5
        ),
        CommonFood(
            id: "cantaloupe", name: "Cantaloupe",
            // USDA FDC #169092
            aliases: ["cantaloupe", "rockmelon", "honeydew", "melon"],
            servingLabel: "1 cup diced (160 g)",
            calories: 54, proteinG: 1, carbsG: 13, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "papaya", name: "Papaya",
            // USDA FDC #169926
            aliases: ["papaya", "paw paw", "papaw"],
            servingLabel: "1 cup cubed (145 g)",
            calories: 62, proteinG: 1, carbsG: 16, fatG: 0, fiberG: 2
        ),
        CommonFood(
            id: "guava", name: "Guava",
            // USDA FDC #173044
            aliases: ["guava", "guavas"],
            servingLabel: "1 medium (55 g)",
            calories: 37, proteinG: 1, carbsG: 8, fatG: 1, fiberG: 3
        ),
        CommonFood(
            id: "passion-fruit", name: "Passion fruit",
            // USDA FDC #167765
            aliases: ["passion fruit", "passionfruit", "maracuja"],
            servingLabel: "1 cup (236 g, pulp)",
            calories: 229, proteinG: 5, carbsG: 55, fatG: 2, fiberG: 24
        ),
        CommonFood(
            id: "coconut-fresh", name: "Coconut",
            // USDA FDC #169098
            aliases: ["coconut", "fresh coconut", "coconut meat", "shredded coconut"],
            servingLabel: "1 cup shredded (80 g)",
            calories: 283, proteinG: 3, carbsG: 12, fatG: 27, fiberG: 7
        ),
        CommonFood(
            id: "nectarine", name: "Nectarine",
            // USDA FDC #169928
            aliases: ["nectarine", "nectarines"],
            servingLabel: "1 medium (142 g)",
            calories: 62, proteinG: 2, carbsG: 15, fatG: 0, fiberG: 2
        ),
        CommonFood(
            id: "dried-mango", name: "Dried mango",
            // USDA FDC #168179
            aliases: ["dried mango", "mango strips", "dried fruit mango"],
            servingLabel: "1 oz (28 g)",
            calories: 80, proteinG: 0, carbsG: 20, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "fig", name: "Figs",
            // USDA FDC #169910
            aliases: ["figs", "fig", "fresh figs", "dried figs"],
            servingLabel: "2 medium fresh (100 g)",
            calories: 74, proteinG: 1, carbsG: 19, fatG: 0, fiberG: 3
        ),
        CommonFood(
            id: "tangerine", name: "Tangerine",
            // USDA FDC #169105
            aliases: ["tangerine", "mandarin", "clementine", "mandarin orange"],
            servingLabel: "1 medium (88 g)",
            calories: 47, proteinG: 1, carbsG: 12, fatG: 0, fiberG: 2
        ),
        CommonFood(
            id: "motts-applesauce-cup", name: "Applesauce cup (Mott's)",
            // Mott's official
            aliases: ["motts applesauce cup", "unsweetened applesauce cup", "mott's natural applesauce"],
            servingLabel: "1 cup (113 g)",
            calories: 50, proteinG: 0, carbsG: 13, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "fruit-cup-in-juice", name: "Fruit cup (in juice)",
            // Dole official
            aliases: ["fruit cup in juice", "diced peaches cup", "dole fruit cup", "mixed fruit cup"],
            servingLabel: "1 cup (113 g)",
            calories: 60, proteinG: 0, carbsG: 15, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "jackfruit", name: "Jackfruit",
            aliases: ["jackfruit", "fresh jackfruit", "jakfruit"],
            servingLabel: "1 cup sliced (165 g)",
            calories: 155, proteinG: 3, carbsG: 38, fatG: 1, fiberG: 3
        ),
        CommonFood(
            id: "persimmon", name: "Persimmon",
            aliases: ["persimmon", "fuyu persimmon", "sharon fruit"],
            servingLabel: "1 fruit (168 g)",
            calories: 118, proteinG: 1, carbsG: 31, fatG: 0, fiberG: 6
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
        CommonFood(
            id: "pinto-beans", name: "Pinto beans",
            // USDA FDC #175201
            aliases: ["pinto beans", "pinto bean", "refried pinto beans"],
            servingLabel: "1 cup cooked (171 g)",
            calories: 245, proteinG: 15, carbsG: 45, fatG: 1, fiberG: 15
        ),
        CommonFood(
            id: "kidney-beans", name: "Kidney beans",
            // USDA FDC #175195
            aliases: ["kidney beans", "red kidney beans", "dark red kidney beans"],
            servingLabel: "1 cup cooked (177 g)",
            calories: 225, proteinG: 15, carbsG: 40, fatG: 1, fiberG: 11
        ),
        CommonFood(
            id: "edamame", name: "Edamame",
            // USDA FDC #168411
            aliases: ["edamame", "soybean", "soybeans", "edamame beans"],
            servingLabel: "1 cup shelled (155 g)",
            calories: 188, proteinG: 18, carbsG: 14, fatG: 8, fiberG: 8
        ),
        CommonFood(
            id: "tofu-firm", name: "Tofu (firm)",
            // USDA FDC #172476
            aliases: ["tofu", "firm tofu", "silken tofu", "extra firm tofu", "crispy tofu"],
            servingLabel: "½ cup (124 g)",
            calories: 181, proteinG: 22, carbsG: 5, fatG: 11, fiberG: 0
        ),
        CommonFood(
            id: "tempeh", name: "Tempeh",
            // USDA FDC #174272
            aliases: ["tempeh"],
            servingLabel: "3 oz (85 g)",
            calories: 162, proteinG: 15, carbsG: 11, fatG: 9, fiberG: 3
        ),
        CommonFood(
            id: "hummus", name: "Hummus",
            // USDA FDC #174275
            aliases: ["hummus", "humus", "chickpea dip"],
            servingLabel: "¼ cup (62 g)",
            calories: 109, proteinG: 5, carbsG: 12, fatG: 5, fiberG: 4
        ),
        CommonFood(
            id: "navy-beans", name: "Navy beans",
            // USDA FDC #175198
            aliases: ["navy beans", "white beans", "great northern beans", "cannellini beans"],
            servingLabel: "1 cup cooked (182 g)",
            calories: 255, proteinG: 15, carbsG: 47, fatG: 1, fiberG: 19
        ),
        CommonFood(
            id: "mung-beans", name: "Mung beans",
            // USDA FDC #175199 — used in Asian cooking, bean sprouts
            aliases: ["mung beans", "mung bean", "green mung bean", "bean sprouts"],
            servingLabel: "1 cup cooked (202 g)",
            calories: 212, proteinG: 14, carbsG: 39, fatG: 1, fiberG: 15
        ),
        CommonFood(
            id: "black-eyed-peas", name: "Black-eyed peas",
            // USDA FDC #175194
            aliases: ["black eyed peas", "black-eyed peas", "cowpeas"],
            servingLabel: "1 cup cooked (172 g)",
            calories: 200, proteinG: 13, carbsG: 36, fatG: 1, fiberG: 11
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
        CommonFood(
            id: "cashews", name: "Cashews",
            // USDA FDC #170162
            aliases: ["cashews", "cashew nuts"],
            servingLabel: "1 oz (28 g, ~18 nuts)",
            calories: 157, proteinG: 5, carbsG: 9, fatG: 12, fiberG: 1
        ),
        CommonFood(
            id: "pistachios", name: "Pistachios",
            // USDA FDC #170184
            aliases: ["pistachios", "pistachio nuts"],
            servingLabel: "1 oz shelled (28 g, ~49 nuts)",
            calories: 159, proteinG: 6, carbsG: 8, fatG: 13, fiberG: 3
        ),
        CommonFood(
            id: "macadamia-nuts", name: "Macadamia nuts",
            // USDA FDC #170178
            aliases: ["macadamia", "macadamia nuts"],
            servingLabel: "1 oz (28 g, ~12 nuts)",
            calories: 204, proteinG: 2, carbsG: 4, fatG: 21, fiberG: 2
        ),
        CommonFood(
            id: "pecans", name: "Pecans",
            // USDA FDC #170182
            aliases: ["pecans", "pecan nuts", "pecan"],
            servingLabel: "1 oz (28 g, ~20 halves)",
            calories: 196, proteinG: 3, carbsG: 4, fatG: 20, fiberG: 3
        ),
        CommonFood(
            id: "sunflower-seeds", name: "Sunflower seeds",
            // USDA FDC #170562
            aliases: ["sunflower seeds", "sunflower seed"],
            servingLabel: "1 oz (28 g)",
            calories: 165, proteinG: 5, carbsG: 6, fatG: 14, fiberG: 3
        ),
        CommonFood(
            id: "chia-seeds", name: "Chia seeds",
            // USDA FDC #170554
            aliases: ["chia seeds", "chia seed", "chia"],
            servingLabel: "2 tbsp (20 g)",
            calories: 97, proteinG: 3, carbsG: 8, fatG: 6, fiberG: 8
        ),
        CommonFood(
            id: "pumpkin-seeds", name: "Pumpkin seeds",
            // USDA FDC #170556 (pepitas, dry roasted)
            aliases: ["pumpkin seeds", "pepitas", "pumpkin seed"],
            servingLabel: "1 oz (28 g)",
            calories: 153, proteinG: 7, carbsG: 5, fatG: 13, fiberG: 1
        ),
        CommonFood(
            id: "flaxseeds", name: "Flaxseeds",
            // USDA FDC #169414
            aliases: ["flaxseeds", "flax seeds", "flax", "ground flax", "linseed"],
            servingLabel: "2 tbsp (14 g)",
            calories: 74, proteinG: 3, carbsG: 4, fatG: 6, fiberG: 4
        ),
        CommonFood(
            id: "hemp-seeds", name: "Hemp seeds",
            aliases: ["hemp seeds", "hemp hearts", "hemp seed"],
            servingLabel: "3 tbsp (30 g)",
            calories: 166, proteinG: 10, carbsG: 3, fatG: 14, fiberG: 1
        ),
        CommonFood(
            id: "almond-butter", name: "Almond butter",
            // USDA FDC #168588
            aliases: ["almond butter", "almond butter spread"],
            servingLabel: "2 tbsp (32 g)",
            calories: 196, proteinG: 7, carbsG: 6, fatG: 18, fiberG: 2
        ),
        CommonFood(
            id: "tahini", name: "Tahini",
            // USDA FDC #169567
            aliases: ["tahini", "sesame paste", "sesame butter"],
            servingLabel: "2 tbsp (30 g)",
            calories: 178, proteinG: 5, carbsG: 6, fatG: 16, fiberG: 3
        ),
        CommonFood(
            id: "olive-oil", name: "Olive oil",
            // USDA FDC #171413
            aliases: ["olive oil", "extra virgin olive oil", "evoo"],
            servingLabel: "1 tbsp (14 g)",
            calories: 119, proteinG: 0, carbsG: 0, fatG: 14, fiberG: 0
        ),
        CommonFood(
            id: "coconut-oil", name: "Coconut oil",
            // USDA FDC #172336
            aliases: ["coconut oil"],
            servingLabel: "1 tbsp (14 g)",
            calories: 121, proteinG: 0, carbsG: 0, fatG: 14, fiberG: 0
        ),
        CommonFood(
            id: "brazil-nuts", name: "Brazil nuts",
            // USDA FDC #170569
            aliases: ["brazil nuts", "brazil nut"],
            servingLabel: "1 oz (28 g, ~6 nuts)",
            calories: 187, proteinG: 4, carbsG: 3, fatG: 19, fiberG: 2
        ),
        CommonFood(
            id: "sesame-seeds", name: "Sesame seeds",
            // USDA FDC #170150
            aliases: ["sesame seeds", "sesame seed", "white sesame"],
            servingLabel: "1 tbsp (9 g)",
            calories: 52, proteinG: 2, carbsG: 2, fatG: 4, fiberG: 1
        ),
        CommonFood(
            id: "avocado-oil", name: "Avocado oil",
            aliases: ["avocado oil"],
            servingLabel: "1 tbsp (14 g)",
            calories: 124, proteinG: 0, carbsG: 0, fatG: 14, fiberG: 0
        ),
        CommonFood(
            id: "nutella", name: "Nutella",
            aliases: ["nutella", "hazelnut spread", "chocolate hazelnut spread"],
            servingLabel: "2 tbsp (37 g)",
            calories: 200, proteinG: 2, carbsG: 22, fatG: 12, fiberG: 1
        ),
        CommonFood(
            id: "cashew-butter", name: "Cashew butter",
            aliases: ["cashew butter"],
            servingLabel: "2 tbsp (32 g)",
            calories: 190, proteinG: 6, carbsG: 9, fatG: 16, fiberG: 1
        ),
        CommonFood(
            id: "sunflower-seed-butter", name: "Sunflower seed butter",
            aliases: ["sunflower seed butter", "sunbutter", "sunflower butter"],
            servingLabel: "2 tbsp (32 g)",
            calories: 200, proteinG: 6, carbsG: 8, fatG: 17, fiberG: 2
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
        CommonFood(
            id: "bubble-tea-taro", name: "Taro milk tea",
            aliases: ["taro milk tea", "taro boba", "taro tea", "taro bubble tea", "taro latte"],
            servingLabel: "16 oz with tapioca pearls",
            calories: 340, proteinG: 3, carbsG: 65, fatG: 7, fiberG: 1
        ),
        CommonFood(
            id: "bubble-tea-matcha", name: "Matcha milk tea",
            aliases: ["matcha milk tea", "matcha boba", "matcha tea boba", "matcha bubble tea", "matcha latte boba"],
            servingLabel: "16 oz with tapioca pearls",
            calories: 300, proteinG: 4, carbsG: 58, fatG: 6, fiberG: 0
        ),
        CommonFood(
            id: "bubble-tea-brown-sugar", name: "Brown sugar milk tea",
            aliases: ["brown sugar milk tea", "brown sugar boba", "tiger milk tea", "tiger tea", "tiger boba", "brown sugar bubble tea"],
            servingLabel: "16 oz with tapioca pearls",
            calories: 420, proteinG: 3, carbsG: 80, fatG: 8, fiberG: 0
        ),
        CommonFood(
            id: "bubble-tea-fruit", name: "Fruit tea (boba)",
            aliases: ["fruit tea", "fruit boba", "mango fruit tea", "passion fruit tea", "strawberry fruit tea", "passion fruit boba", "lychee boba"],
            servingLabel: "16 oz with tapioca pearls",
            calories: 220, proteinG: 1, carbsG: 52, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "matcha-latte", name: "Matcha latte",
            aliases: ["matcha latte", "matcha", "iced matcha", "matcha green tea latte"],
            servingLabel: "16 oz with oat/whole milk",
            calories: 200, proteinG: 6, carbsG: 28, fatG: 7, fiberG: 0
        ),
        CommonFood(
            id: "horchata", name: "Horchata",
            aliases: ["horchata", "agua de horchata", "rice horchata"],
            servingLabel: "8 oz (240 ml)",
            calories: 150, proteinG: 1, carbsG: 26, fatG: 5, fiberG: 0
        ),
        CommonFood(
            id: "agua-fresca", name: "Agua fresca",
            aliases: ["agua fresca", "agua de jamaica", "agua de tamarindo", "hibiscus tea", "jamaica drink"],
            servingLabel: "8 oz (240 ml)",
            calories: 60, proteinG: 0, carbsG: 16, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "coconut-water", name: "Coconut water",
            // USDA FDC #170102
            aliases: ["coconut water", "coconut juice", "fresh coconut water"],
            servingLabel: "8 oz (240 ml)",
            calories: 46, proteinG: 2, carbsG: 9, fatG: 0, fiberG: 3
        ),
        CommonFood(
            id: "cold-brew", name: "Cold brew coffee",
            aliases: ["cold brew", "cold brew coffee", "cold brew concentrate"],
            servingLabel: "16 oz unsweetened",
            calories: 10, proteinG: 1, carbsG: 2, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "chai-latte", name: "Chai latte",
            aliases: ["chai latte", "chai tea latte", "masala chai", "chai", "spiced tea latte"],
            servingLabel: "16 oz with whole milk",
            calories: 240, proteinG: 5, carbsG: 42, fatG: 6, fiberG: 0
        ),
        CommonFood(
            id: "kombucha", name: "Kombucha",
            aliases: ["kombucha", "raw kombucha"],
            servingLabel: "8 oz (240 ml)",
            calories: 60, proteinG: 0, carbsG: 14, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "sweet-tea", name: "Sweet tea",
            aliases: ["sweet tea", "southern sweet tea", "iced tea", "sweet iced tea"],
            servingLabel: "12 oz (360 ml)",
            calories: 130, proteinG: 0, carbsG: 34, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "lemonade", name: "Lemonade",
            // USDA FDC #172854
            aliases: ["lemonade", "fresh lemonade", "pink lemonade"],
            servingLabel: "12 oz (360 ml)",
            calories: 149, proteinG: 0, carbsG: 39, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "vietnamese-iced-coffee", name: "Vietnamese iced coffee",
            aliases: ["vietnamese iced coffee", "ca phe sua da", "cafe sua da", "vietnamese coffee"],
            servingLabel: "8 oz with condensed milk",
            calories: 140, proteinG: 3, carbsG: 27, fatG: 3, fiberG: 0
        ),
        CommonFood(
            id: "mango-lassi", name: "Mango lassi",
            aliases: ["mango lassi", "lassi", "mango yogurt drink"],
            servingLabel: "8 oz (240 ml)",
            calories: 160, proteinG: 5, carbsG: 30, fatG: 3, fiberG: 1
        ),
        CommonFood(
            id: "apple-juice", name: "Apple juice",
            // USDA FDC #168871
            aliases: ["apple juice", "apple cider", "cider"],
            servingLabel: "1 cup (248 ml)",
            calories: 114, proteinG: 0, carbsG: 28, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "hot-cocoa", name: "Hot chocolate",
            aliases: ["hot chocolate", "hot cocoa", "hot choc", "cocoa"],
            servingLabel: "8 oz made with whole milk",
            calories: 250, proteinG: 9, carbsG: 34, fatG: 9, fiberG: 2
        ),
        CommonFood(
            id: "sparkling-water", name: "Sparkling water",
            aliases: ["sparkling water", "fizzy water", "club soda", "mineral water", "perrier", "san pellegrino"],
            servingLabel: "12 oz",
            calories: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "ginger-ale", name: "Ginger ale",
            // USDA FDC #174052
            aliases: ["ginger ale", "ginger beer"],
            servingLabel: "12 oz can",
            calories: 125, proteinG: 0, carbsG: 32, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "cranberry-juice", name: "Cranberry juice",
            // USDA FDC #168872
            aliases: ["cranberry juice", "ocean spray", "cranberry cocktail"],
            servingLabel: "8 oz (240 ml)",
            calories: 116, proteinG: 1, carbsG: 31, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "grape-juice", name: "Grape juice",
            // USDA FDC #168873
            aliases: ["grape juice", "white grape juice"],
            servingLabel: "8 oz (240 ml)",
            calories: 154, proteinG: 1, carbsG: 38, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "kefir", name: "Kefir",
            // USDA FDC #170902
            aliases: ["kefir", "drinkable yogurt"],
            servingLabel: "1 cup (240 ml)",
            calories: 160, proteinG: 10, carbsG: 12, fatG: 7, fiberG: 0
        ),
        CommonFood(
            id: "bone-broth", name: "Bone broth",
            aliases: ["bone broth", "chicken bone broth", "beef bone broth", "collagen broth"],
            servingLabel: "1 cup (240 ml)",
            calories: 40, proteinG: 9, carbsG: 0, fatG: 1, fiberG: 0
        ),
        CommonFood(
            id: "rose-wine", name: "Rosé wine",
            // USDA FDC #174843
            aliases: ["rose wine", "rosé", "white wine", "prosecco", "champagne"],
            servingLabel: "5 oz glass (147 ml)",
            calories: 121, proteinG: 0, carbsG: 5, fatG: 0, fiberG: 0
        ),

        // — Energy & functional drinks —
        CommonFood(
            id: "celsius-drink", name: "Celsius energy drink",
            // Celsius official label (original sparkling)
            aliases: ["celsius", "celsius energy drink", "celsius sparkling"],
            servingLabel: "12 oz can",
            calories: 10, proteinG: 0, carbsG: 2, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "bang-energy", name: "Bang energy drink",
            aliases: ["bang energy", "bang drink", "bang"],
            servingLabel: "16 oz can",
            calories: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "prime-hydration", name: "Prime hydration drink",
            // Prime official label
            aliases: ["prime drink", "prime hydration", "prime"],
            servingLabel: "16.9 oz bottle",
            calories: 20, proteinG: 0, carbsG: 5, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "liquid-iv", name: "Liquid IV electrolyte packet",
            // Liquid I.V. official label (lemon lime)
            aliases: ["liquid iv", "liquid i.v.", "electrolyte packet", "hydration multiplier"],
            servingLabel: "1 packet mixed in 16 oz water",
            calories: 45, proteinG: 0, carbsG: 11, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "propel-water", name: "Propel fitness water",
            aliases: ["propel", "propel water", "propel electrolyte water"],
            servingLabel: "16.9 oz bottle",
            calories: 10, proteinG: 0, carbsG: 3, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "body-armor", name: "Body Armor sports drink",
            // Body Armor official label (fruit punch)
            aliases: ["bodyarmor", "body armor", "body armor sports drink"],
            servingLabel: "16 oz bottle",
            calories: 120, proteinG: 0, carbsG: 30, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "gatorade-zero", name: "Gatorade Zero",
            aliases: ["gatorade zero", "g zero", "gatorade zero sugar"],
            servingLabel: "20 oz bottle",
            calories: 10, proteinG: 0, carbsG: 2, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "arizona-iced-tea", name: "Arizona iced tea",
            // Arizona Beverages official: 23.5 oz can = 270 cal
            aliases: ["arizona iced tea", "arizona tea", "arizona green tea", "arizona sweet tea"],
            servingLabel: "23.5 oz can",
            calories: 270, proteinG: 0, carbsG: 73, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "snapple-iced-tea", name: "Snapple iced tea",
            // Snapple lemon tea, 16 oz bottle
            aliases: ["snapple", "snapple iced tea", "snapple lemon tea", "snapple peach tea"],
            servingLabel: "16 oz bottle",
            calories: 160, proteinG: 0, carbsG: 39, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "vitamin-water", name: "Vitaminwater",
            // Vitaminwater, generic 20 oz
            aliases: ["vitamin water", "vitaminwater", "vitamin water xxx", "vitamin water energy"],
            servingLabel: "20 oz bottle",
            calories: 120, proteinG: 0, carbsG: 32, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "gold-peak-sweet-tea", name: "Gold Peak sweet tea",
            // Gold Peak official: 18.5 oz bottle
            aliases: ["gold peak", "gold peak sweet tea", "gold peak tea"],
            servingLabel: "18.5 oz bottle",
            calories: 160, proteinG: 0, carbsG: 44, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "olipop-soda", name: "Olipop soda",
            // Olipop official: vintage cola, 12 oz
            aliases: ["olipop", "olipop soda", "olipop cola", "olipop prebiotic soda"],
            servingLabel: "12 oz can",
            calories: 35, proteinG: 0, carbsG: 13, fatG: 0, fiberG: 9
        ),
        CommonFood(
            id: "dunkin-iced-coffee", name: "Dunkin' iced coffee",
            // Dunkin' medium iced coffee with cream & sugar
            aliases: ["dunkin iced coffee", "dunkin coffee", "dunkin donuts iced coffee", "dd iced coffee"],
            servingLabel: "Medium (24 oz) with cream & sugar",
            calories: 260, proteinG: 3, carbsG: 51, fatG: 6, fiberG: 0
        ),
        CommonFood(
            id: "tinto-colombian-coffee", name: "Tinto (Colombian Black Coffee)",
            aliases: ["tinto colombiano", "colombian black coffee", "tinto cafe"],
            servingLabel: "1 cup (240 ml)",
            calories: 5, proteinG: 0, carbsG: 1, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "agua-de-panela", name: "Agua de Panela",
            aliases: ["agua de panela", "colombian cane sugar drink", "aguapanela"],
            servingLabel: "1 cup (240 ml)",
            calories: 70, proteinG: 0, carbsG: 18, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "chocolate-santafereno", name: "Chocolate Santafereño",
            aliases: ["chocolate santafereno", "colombian hot chocolate with cheese", "chocolate caliente colombiano"],
            servingLabel: "1 cup (240 ml)",
            calories: 190, proteinG: 6, carbsG: 22, fatG: 9, fiberG: 2
        ),
        CommonFood(
            id: "avena-colombiana", name: "Avena Colombiana (Oat Drink)",
            aliases: ["avena colombiana", "colombian oatmeal drink", "avena en agua"],
            servingLabel: "1 cup (240 ml)",
            calories: 150, proteinG: 5, carbsG: 27, fatG: 3, fiberG: 2
        ),
        CommonFood(
            id: "masato-colombiano", name: "Masato",
            aliases: ["masato colombiano", "colombian fermented rice drink", "masato de arroz"],
            servingLabel: "1 cup (240 ml)",
            calories: 130, proteinG: 2, carbsG: 30, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "champus-colombiano", name: "Champús",
            aliases: ["champus colombiano", "colombian corn fruit drink", "champus valluno"],
            servingLabel: "1 cup (240 ml)",
            calories: 160, proteinG: 1, carbsG: 40, fatG: 0, fiberG: 2
        ),
        CommonFood(
            id: "lulada-colombiana", name: "Lulada",
            aliases: ["lulada colombiana", "colombian lulo drink", "lulada del valle"],
            servingLabel: "1 glass (300 ml)",
            calories: 140, proteinG: 1, carbsG: 35, fatG: 0, fiberG: 2
        ),
        CommonFood(
            id: "salpicon-colombiano", name: "Salpicón Colombiano",
            aliases: ["salpicon colombiano", "colombian fruit punch drink", "salpicon de frutas"],
            servingLabel: "1 cup (240 ml)",
            calories: 130, proteinG: 1, carbsG: 33, fatG: 0, fiberG: 2
        ),
        CommonFood(
            id: "pony-malta", name: "Pony Malta",
            // Bavaria official
            aliases: ["pony malta", "colombian malt soda", "ponymalta bavaria"],
            servingLabel: "1 bottle (330 ml)",
            calories: 200, proteinG: 1, carbsG: 48, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "colombiana-soda", name: "Colombiana Soda",
            // Postobón official
            aliases: ["colombiana soda", "kola colombiana", "colombian cream soda"],
            servingLabel: "12 oz can (355 ml)",
            calories: 170, proteinG: 0, carbsG: 44, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "jugo-de-lulo", name: "Jugo de Lulo",
            aliases: ["jugo de lulo", "colombian lulo juice", "lulo naranjilla juice"],
            servingLabel: "1 cup (240 ml)",
            calories: 110, proteinG: 1, carbsG: 27, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "jugo-de-maracuya", name: "Jugo de Maracuyá",
            aliases: ["jugo de maracuya", "colombian passion fruit juice", "maracuya juice"],
            servingLabel: "1 cup (240 ml)",
            calories: 130, proteinG: 1, carbsG: 32, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "refajo-colombiano", name: "Refajo",
            // alcoholic; ethanol calories not in macros
            aliases: ["refajo colombiano", "colombiana and beer mix", "refajo bavaria"],
            servingLabel: "12 oz mix (355 ml)",
            calories: 150, proteinG: 1, carbsG: 22, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "calamansi-juice", name: "Calamansi juice",
            aliases: ["calamansi drink", "philippine lime juice", "kalamansi juice", "filipino citrus juice"],
            servingLabel: "12 oz (355 ml)",
            calories: 120, proteinG: 0, carbsG: 30, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "sagot-gulaman", name: "Sago't gulaman",
            aliases: ["sago gulaman drink", "gulaman at sago", "filipino jelly tapioca drink", "arnibal pearl drink"],
            servingLabel: "16 oz (475 ml)",
            calories: 200, proteinG: 0, carbsG: 50, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "buko-juice", name: "Fresh buko juice",
            aliases: ["young coconut water filipino", "fresh coconut juice", "buko water", "filipino coconut drink"],
            servingLabel: "12 oz (355 ml)",
            calories: 80, proteinG: 1, carbsG: 19, fatG: 0, fiberG: 2
        ),
        CommonFood(
            id: "gatorade-fruit-punch", name: "Gatorade fruit punch",
            // Gatorade official
            aliases: ["gatorade fruit punch", "fruit punch sports drink", "gatorade thirst quencher"],
            servingLabel: "20 fl oz bottle (591 ml)",
            calories: 140, proteinG: 0, carbsG: 36, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "powerade-mountain-berry", name: "Powerade Mountain Berry Blast",
            // Powerade official
            aliases: ["powerade mountain berry blast", "powerade blue", "powerade berry blast"],
            servingLabel: "20 fl oz bottle (591 ml)",
            calories: 130, proteinG: 0, carbsG: 35, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "naked-green-machine", name: "Naked Green Machine",
            // Naked Juice official
            aliases: ["naked green machine", "green machine smoothie", "naked juice green"],
            servingLabel: "15.2 fl oz bottle (450 ml)",
            calories: 270, proteinG: 4, carbsG: 63, fatG: 1, fiberG: 1
        ),
        CommonFood(
            id: "tropicana-orange-juice-bottle", name: "Tropicana orange juice (bottle)",
            // Tropicana official
            aliases: ["tropicana orange juice", "tropicana pure premium", "tropicana oj bottle"],
            servingLabel: "12 fl oz bottle (355 ml)",
            calories: 160, proteinG: 2, carbsG: 38, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "simply-lemonade", name: "Simply Lemonade",
            // Simply official
            aliases: ["simply lemonade bottle", "simply brand lemonade", "all natural lemonade"],
            servingLabel: "12 fl oz (355 ml)",
            calories: 160, proteinG: 0, carbsG: 42, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "yoo-hoo", name: "Yoo-hoo chocolate drink",
            // Yoo-hoo official
            aliases: ["yoo hoo chocolate", "yoohoo chocolate drink", "yoo-hoo bottle"],
            servingLabel: "15.5 fl oz bottle (459 ml)",
            calories: 210, proteinG: 2, carbsG: 44, fatG: 2, fiberG: 1
        ),
        CommonFood(
            id: "capri-sun-pouch", name: "Capri Sun pouch",
            // Capri Sun official
            aliases: ["capri sun fruit punch", "capri sun pouch", "caprisun juice drink"],
            servingLabel: "1 pouch (177 ml)",
            calories: 60, proteinG: 0, carbsG: 15, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "ensure-original-shake", name: "Ensure Original shake",
            // Ensure official
            aliases: ["ensure original shake", "ensure nutrition shake", "ensure vanilla shake"],
            servingLabel: "8 fl oz bottle (237 ml)",
            calories: 220, proteinG: 9, carbsG: 33, fatG: 6, fiberG: 1
        ),
        CommonFood(
            id: "muscle-milk-shake", name: "Muscle Milk protein shake",
            // Muscle Milk official
            aliases: ["muscle milk shake", "muscle milk protein drink", "muscle milk vanilla shake"],
            servingLabel: "14 fl oz bottle (414 ml)",
            calories: 170, proteinG: 25, carbsG: 9, fatG: 3, fiberG: 3
        ),
        CommonFood(
            id: "fairlife-core-power", name: "Fairlife Core Power shake",
            // Fairlife Core Power official
            aliases: ["fairlife core power", "core power protein shake", "fairlife protein milk"],
            servingLabel: "14 fl oz bottle (414 ml)",
            calories: 170, proteinG: 26, carbsG: 9, fatG: 4, fiberG: 0
        ),
        CommonFood(
            id: "red-bull", name: "Red Bull energy drink",
            // Red Bull official
            aliases: ["red bull can", "redbull energy drink", "red bull original"],
            servingLabel: "8.4 fl oz can (250 ml)",
            calories: 110, proteinG: 1, carbsG: 27, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "monster-energy", name: "Monster Energy",
            // Monster official
            aliases: ["monster energy drink", "monster green can", "monster original energy"],
            servingLabel: "16 fl oz can (473 ml)",
            calories: 210, proteinG: 0, carbsG: 54, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "v8-vegetable-juice", name: "V8 vegetable juice",
            // V8 official
            aliases: ["v8 original vegetable juice", "v8 tomato vegetable juice", "v eight juice"],
            servingLabel: "8 fl oz (240 ml)",
            calories: 45, proteinG: 2, carbsG: 10, fatG: 0, fiberG: 2
        ),
        CommonFood(
            id: "sweet-apple-cider", name: "Apple cider (sweet)",
            // USDA FDC #173951
            aliases: ["sweet apple cider", "fresh pressed apple cider", "fall apple cider"],
            servingLabel: "8 fl oz (240 ml)",
            calories: 120, proteinG: 0, carbsG: 28, fatG: 0, fiberG: 0
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
        CommonFood(
            id: "tomato-soup", name: "Tomato soup",
            // USDA FDC #172934 (cream of tomato, made with milk)
            aliases: ["tomato soup", "cream of tomato", "tomato bisque", "roasted tomato soup"],
            servingLabel: "1 cup (248 g, with milk)",
            calories: 161, proteinG: 6, carbsG: 22, fatG: 6, fiberG: 2
        ),
        CommonFood(
            id: "minestrone", name: "Minestrone soup",
            // USDA FDC #172949
            aliases: ["minestrone", "minestrone soup", "vegetable soup", "italian vegetable soup"],
            servingLabel: "1 cup (241 g)",
            calories: 82, proteinG: 4, carbsG: 13, fatG: 2, fiberG: 3
        ),
        CommonFood(
            id: "french-onion-soup", name: "French onion soup",
            // USDA FDC #173577 + crouton/cheese added
            aliases: ["french onion soup", "onion soup"],
            servingLabel: "1 cup with crouton + gruyère (248 g)",
            calories: 330, proteinG: 12, carbsG: 28, fatG: 18, fiberG: 2
        ),
        CommonFood(
            id: "broccoli-cheddar-soup", name: "Broccoli cheddar soup",
            // Panera Bread published nutrition (cup serving)
            aliases: ["broccoli cheddar soup", "broccoli cheese soup", "panera broccoli soup", "broccoli soup"],
            servingLabel: "1 cup (247 g)",
            calories: 290, proteinG: 11, carbsG: 18, fatG: 20, fiberG: 3
        ),
        CommonFood(
            id: "pho-beef", name: "Beef pho",
            // USDA SR Legacy restaurant estimates; medium bowl
            aliases: ["pho", "beef pho", "pho bo", "vietnamese pho", "pho noodle soup"],
            servingLabel: "1 bowl (~600 g, broth + rice noodles + beef)",
            calories: 450, proteinG: 30, carbsG: 47, fatG: 10, fiberG: 3
        ),
        CommonFood(
            id: "tom-yum-soup", name: "Tom yum soup",
            aliases: ["tom yum", "tom yum soup", "thai hot and sour soup"],
            servingLabel: "1 cup (240 g)",
            calories: 80, proteinG: 6, carbsG: 8, fatG: 3, fiberG: 1
        ),
        CommonFood(
            id: "lentil-soup", name: "Lentil soup",
            // USDA FDC #172940
            aliases: ["lentil soup", "red lentil soup", "lentil stew"],
            servingLabel: "1 cup (248 g)",
            calories: 130, proteinG: 9, carbsG: 20, fatG: 2, fiberG: 6
        ),
        CommonFood(
            id: "butternut-squash-soup", name: "Butternut squash soup",
            aliases: ["butternut squash soup", "squash soup", "pumpkin soup"],
            servingLabel: "1 cup (245 g)",
            calories: 130, proteinG: 3, carbsG: 20, fatG: 5, fiberG: 4
        ),
        CommonFood(
            id: "egg-drop-soup", name: "Egg drop soup",
            // USDA FDC #172959
            aliases: ["egg drop soup", "egg flower soup"],
            servingLabel: "1 cup (244 g)",
            calories: 73, proteinG: 8, carbsG: 3, fatG: 3, fiberG: 0
        ),
        CommonFood(
            id: "hot-sour-soup", name: "Hot and sour soup",
            // USDA SR Legacy "Restaurant, Chinese, hot and sour soup"
            aliases: ["hot and sour soup", "hot sour soup", "chinese hot sour soup"],
            servingLabel: "1 cup (244 g)",
            calories: 91, proteinG: 3, carbsG: 12, fatG: 3, fiberG: 1
        ),
        CommonFood(
            id: "chicken-tortilla-soup", name: "Chicken tortilla soup",
            aliases: ["chicken tortilla soup", "tortilla soup", "mexican chicken soup"],
            servingLabel: "1 cup (245 g)",
            calories: 150, proteinG: 12, carbsG: 16, fatG: 4, fiberG: 3
        ),
        CommonFood(
            id: "gumbo", name: "Gumbo",
            // USDA SR Legacy Louisiana-style gumbo estimate
            aliases: ["gumbo", "chicken gumbo", "shrimp gumbo", "cajun gumbo"],
            servingLabel: "1 cup (244 g)",
            calories: 166, proteinG: 15, carbsG: 12, fatG: 6, fiberG: 2
        ),
        CommonFood(
            id: "congee", name: "Congee",
            aliases: ["congee", "jook", "rice porridge", "rice soup", "kayu", "cháo"],
            servingLabel: "1 cup (250 g, plain)",
            calories: 70, proteinG: 2, carbsG: 15, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "ramen-broth", name: "Ramen broth",
            aliases: ["tonkotsu broth", "ramen broth", "miso broth ramen", "shoyu broth"],
            servingLabel: "1 cup (240 ml)",
            calories: 50, proteinG: 4, carbsG: 4, fatG: 2, fiberG: 0
        ),
        CommonFood(
            id: "gazpacho", name: "Gazpacho",
            // USDA FDC #172936
            aliases: ["gazpacho", "cold tomato soup"],
            servingLabel: "1 cup (244 g)",
            calories: 57, proteinG: 2, carbsG: 10, fatG: 2, fiberG: 1
        ),
        CommonFood(
            id: "caldo-de-costilla", name: "Caldo de costilla",
            aliases: ["caldo de costilla", "colombian rib broth", "beef rib soup colombian", "bogota rib broth"],
            servingLabel: "1 bowl (400 g)",
            calories: 250, proteinG: 22, carbsG: 18, fatG: 10, fiberG: 2
        ),
        CommonFood(
            id: "mondongo-colombiano", name: "Mondongo colombiano",
            aliases: ["mondongo colombiano", "colombian tripe soup", "sopa de mondongo", "menudo colombiano"],
            servingLabel: "1 bowl (400 g)",
            calories: 340, proteinG: 26, carbsG: 28, fatG: 14, fiberG: 5
        ),
        CommonFood(
            id: "sancocho-de-gallina", name: "Sancocho de gallina",
            aliases: ["sancocho de gallina", "colombian hen soup", "sancocho de pollo gallina", "hen and plantain soup"],
            servingLabel: "1 bowl (450 g)",
            calories: 420, proteinG: 30, carbsG: 38, fatG: 16, fiberG: 5
        ),
        CommonFood(
            id: "beef-nilaga", name: "Beef Nilaga",
            aliases: ["filipino boiled beef soup", "nilagang baka", "beef vegetable bone soup filipino", "nilaga beef"],
            servingLabel: "1 bowl (350 g)",
            calories: 280, proteinG: 24, carbsG: 14, fatG: 14, fiberG: 3
        ),
        CommonFood(
            id: "khao-soi", name: "Khao soi",
            aliases: ["khao soi", "northern thai curry noodles", "coconut curry noodle soup"],
            servingLabel: "1 bowl (450 g)",
            calories: 600, proteinG: 26, carbsG: 58, fatG: 30, fiberG: 4
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
        CommonFood(
            id: "caesar-salad", name: "Caesar salad",
            // USDA FDC #168436 (restaurant Caesar, 2 cups / 228 g)
            aliases: ["caesar salad", "caesar"],
            servingLabel: "2 cups with dressing + croutons (228 g)",
            calories: 350, proteinG: 7, carbsG: 22, fatG: 27, fiberG: 3
        ),
        CommonFood(
            id: "chicken-caesar-salad", name: "Chicken Caesar salad",
            aliases: ["chicken caesar salad", "caesar salad with chicken", "chicken caesar"],
            servingLabel: "2 cups salad + 4 oz grilled chicken (340 g)",
            calories: 530, proteinG: 43, carbsG: 22, fatG: 31, fiberG: 3
        ),
        CommonFood(
            id: "greek-salad", name: "Greek salad",
            // USDA SR Legacy "Salad, Greek" (FDC #168432)
            aliases: ["greek salad", "horiatiki"],
            servingLabel: "2 cups with feta + olives + dressing (300 g)",
            calories: 250, proteinG: 6, carbsG: 14, fatG: 20, fiberG: 4
        ),
        CommonFood(
            id: "cobb-salad", name: "Cobb salad",
            // USDA FDC #168434
            aliases: ["cobb salad"],
            servingLabel: "1 full salad with chicken, egg, bacon, avocado, blue cheese (400 g)",
            calories: 560, proteinG: 40, carbsG: 15, fatG: 40, fiberG: 5
        ),
        CommonFood(
            id: "pasta-salad", name: "Pasta salad",
            aliases: ["pasta salad", "cold pasta salad", "macaroni salad"],
            servingLabel: "1 cup (220 g)",
            calories: 300, proteinG: 8, carbsG: 40, fatG: 12, fiberG: 3
        ),
        CommonFood(
            id: "mac-and-cheese", name: "Mac and cheese",
            // USDA FDC #172898; Kraft Official (boxed prepared)
            aliases: ["mac and cheese", "mac & cheese", "macaroni and cheese", "kraft mac and cheese", "kraft mac", "blue box mac"],
            servingLabel: "1 cup prepared (200 g)",
            calories: 380, proteinG: 14, carbsG: 47, fatG: 15, fiberG: 2
        ),
        CommonFood(
            id: "spaghetti-bolognese", name: "Spaghetti bolognese",
            // USDA FDC #172900 "Spaghetti with meat sauce, homemade" (252 g = 338 cal)
            aliases: ["spaghetti bolognese", "meat sauce pasta", "spaghetti meat sauce", "bolognese", "spaghetti with meat sauce", "pasta bolognese"],
            servingLabel: "1 cup (252 g)",
            calories: 340, proteinG: 18, carbsG: 35, fatG: 12, fiberG: 3
        ),
        CommonFood(
            id: "fettuccine-alfredo", name: "Fettuccine Alfredo",
            // USDA FDC #172907 (restaurant-style)
            aliases: ["fettuccine alfredo", "pasta alfredo", "alfredo pasta", "alfredo"],
            servingLabel: "1 cup (220 g)",
            calories: 485, proteinG: 16, carbsG: 55, fatG: 24, fiberG: 3
        ),
        CommonFood(
            id: "lasagna-beef", name: "Lasagna with meat",
            // USDA FDC #172901 (homemade, 245 g serving)
            aliases: ["lasagna", "lasagne", "beef lasagna", "meat lasagna"],
            servingLabel: "1 serving (245 g)",
            calories: 385, proteinG: 22, carbsG: 38, fatG: 15, fiberG: 3
        ),
        CommonFood(
            id: "pad-thai", name: "Pad Thai",
            // USDA FDC #171037 "Restaurant, noodles, pad thai" (287 g = 397 cal)
            aliases: ["pad thai", "pad see ew", "thai noodles", "thai stir fry noodles"],
            servingLabel: "1 cup (280 g)",
            calories: 400, proteinG: 18, carbsG: 52, fatG: 14, fiberG: 3
        ),
        CommonFood(
            id: "ramen-bowl", name: "Ramen bowl",
            // USDA SR Legacy restaurant noodle bowl estimate; not instant ramen
            aliases: ["ramen bowl", "tonkotsu ramen", "shoyu ramen", "miso ramen", "fresh ramen", "restaurant ramen", "spicy ramen"],
            servingLabel: "1 bowl (~600 g, broth + noodles + chashu pork + egg)",
            calories: 500, proteinG: 25, carbsG: 60, fatG: 16, fiberG: 3
        ),
        CommonFood(
            id: "poke-bowl", name: "Poke bowl",
            aliases: ["poke bowl", "poke", "ahi poke bowl", "salmon poke bowl", "tuna poke bowl"],
            servingLabel: "1 bowl (350 g, salmon/tuna + rice + sauce)",
            calories: 500, proteinG: 30, carbsG: 55, fatG: 15, fiberG: 4
        ),
        CommonFood(
            id: "bibimbap", name: "Bibimbap",
            // USDA FDC #712068
            aliases: ["bibimbap", "korean rice bowl", "dolsot bibimbap"],
            servingLabel: "1 bowl (500 g)",
            calories: 490, proteinG: 23, carbsG: 68, fatG: 14, fiberG: 5
        ),
        CommonFood(
            id: "teriyaki-bowl", name: "Teriyaki chicken bowl",
            aliases: ["teriyaki bowl", "teriyaki chicken", "chicken teriyaki bowl", "chicken teriyaki rice"],
            servingLabel: "4 oz chicken + 1 cup rice + sauce (300 g)",
            calories: 430, proteinG: 32, carbsG: 52, fatG: 10, fiberG: 2
        ),
        CommonFood(
            id: "banh-mi", name: "Bánh mì",
            aliases: ["banh mi", "bánh mì", "vietnamese sandwich", "bahn mi"],
            servingLabel: "1 sandwich (220 g)",
            calories: 500, proteinG: 25, carbsG: 60, fatG: 18, fiberG: 3
        ),
        CommonFood(
            id: "falafel-wrap", name: "Falafel wrap",
            aliases: ["falafel wrap", "falafel", "falafel pita", "falafel sandwich"],
            servingLabel: "1 wrap with hummus + veggies (220 g)",
            calories: 440, proteinG: 14, carbsG: 55, fatG: 18, fiberG: 8
        ),
        CommonFood(
            id: "gyro", name: "Gyro",
            aliases: ["gyro", "gyros", "souvlaki wrap", "greek wrap"],
            servingLabel: "1 pita with tzatziki (300 g)",
            calories: 540, proteinG: 30, carbsG: 48, fatG: 22, fiberG: 3
        ),

        // — American comfort & classics
        CommonFood(
            id: "fried-chicken", name: "Fried chicken",
            // USDA FDC #168705 (fried chicken, breast, skin)
            aliases: ["fried chicken", "southern fried chicken", "crispy chicken"],
            servingLabel: "1 breast piece (180 g)",
            calories: 436, proteinG: 43, carbsG: 14, fatG: 22, fiberG: 1
        ),
        CommonFood(
            id: "chicken-and-waffles", name: "Chicken and waffles",
            aliases: ["chicken and waffles", "chicken n waffles", "chicken waffle"],
            servingLabel: "1 waffle + 1 piece fried chicken (~350 g)",
            calories: 700, proteinG: 38, carbsG: 65, fatG: 28, fiberG: 3
        ),
        CommonFood(
            id: "bbq-pulled-pork-sandwich", name: "BBQ pulled pork sandwich",
            aliases: ["pulled pork sandwich", "bbq pork sandwich", "pulled pork bun"],
            servingLabel: "1 sandwich with bun (280 g)",
            calories: 510, proteinG: 30, carbsG: 52, fatG: 17, fiberG: 2
        ),
        CommonFood(
            id: "beef-brisket", name: "Beef brisket",
            aliases: ["brisket", "beef brisket", "bbq brisket", "smoked brisket"],
            servingLabel: "3 oz cooked (85 g)",
            calories: 235, proteinG: 20, carbsG: 5, fatG: 15, fiberG: 0
        ),
        CommonFood(
            id: "jambalaya", name: "Jambalaya",
            // USDA SR Legacy restaurant Cajun estimate
            aliases: ["jambalaya", "cajun jambalaya", "creole jambalaya"],
            servingLabel: "1 cup (200 g)",
            calories: 300, proteinG: 18, carbsG: 32, fatG: 11, fiberG: 3
        ),
        CommonFood(
            id: "eggs-benedict", name: "Eggs Benedict",
            aliases: ["eggs benedict", "egg benedict"],
            servingLabel: "2 eggs on English muffin with hollandaise (250 g)",
            calories: 500, proteinG: 22, carbsG: 28, fatG: 33, fiberG: 2
        ),
        CommonFood(
            id: "biscuits-gravy", name: "Biscuits and gravy",
            aliases: ["biscuits and gravy", "biscuits gravy", "biscuit with gravy"],
            servingLabel: "2 biscuits + gravy (280 g)",
            calories: 530, proteinG: 14, carbsG: 57, fatG: 28, fiberG: 2
        ),
        CommonFood(
            id: "breakfast-burrito", name: "Breakfast burrito",
            aliases: ["breakfast burrito", "egg burrito", "breakfast wrap"],
            servingLabel: "1 burrito (eggs + cheese + sausage, 220 g)",
            calories: 480, proteinG: 22, carbsG: 38, fatG: 26, fiberG: 2
        ),
        CommonFood(
            id: "club-sandwich", name: "Club sandwich",
            aliases: ["club sandwich", "triple decker sandwich", "club"],
            servingLabel: "1 sandwich (300 g)",
            calories: 540, proteinG: 30, carbsG: 44, fatG: 25, fiberG: 4
        ),
        CommonFood(
            id: "blt-sandwich", name: "BLT sandwich",
            aliases: ["blt", "blt sandwich", "bacon lettuce tomato sandwich"],
            servingLabel: "1 sandwich (200 g)",
            calories: 380, proteinG: 18, carbsG: 34, fatG: 18, fiberG: 3
        ),
        CommonFood(
            id: "reuben-sandwich", name: "Reuben sandwich",
            aliases: ["reuben", "reuben sandwich"],
            servingLabel: "1 sandwich (300 g)",
            calories: 600, proteinG: 33, carbsG: 46, fatG: 30, fiberG: 3
        ),
        CommonFood(
            id: "chicken-pot-pie", name: "Chicken pot pie",
            // USDA FDC #168927
            aliases: ["chicken pot pie", "pot pie"],
            servingLabel: "1 individual pie (271 g)",
            calories: 484, proteinG: 17, carbsG: 43, fatG: 27, fiberG: 3
        ),
        CommonFood(
            id: "beef-stew", name: "Beef stew",
            // USDA FDC #172961
            aliases: ["beef stew", "pot roast", "braised beef", "beef and vegetables"],
            servingLabel: "1 cup (252 g)",
            calories: 220, proteinG: 16, carbsG: 15, fatG: 11, fiberG: 3
        ),
        CommonFood(
            id: "chili-con-carne", name: "Chili con carne",
            // USDA FDC #171937
            aliases: ["chili", "chili con carne", "beef chili", "texas chili"],
            servingLabel: "1 cup (253 g)",
            calories: 290, proteinG: 20, carbsG: 25, fatG: 12, fiberG: 8
        ),
        CommonFood(
            id: "meatloaf", name: "Meatloaf",
            // USDA FDC #168920
            aliases: ["meatloaf", "meat loaf"],
            servingLabel: "1 slice (87 g)",
            calories: 212, proteinG: 14, carbsG: 9, fatG: 13, fiberG: 1
        ),
        CommonFood(
            id: "potato-salad", name: "Potato salad",
            // USDA FDC #172962
            aliases: ["potato salad", "creamy potato salad"],
            servingLabel: "½ cup (125 g)",
            calories: 180, proteinG: 3, carbsG: 20, fatG: 10, fiberG: 2
        ),
        CommonFood(
            id: "coleslaw", name: "Coleslaw",
            // USDA FDC #172956
            aliases: ["coleslaw", "cole slaw", "creamy slaw"],
            servingLabel: "½ cup (60 g)",
            calories: 95, proteinG: 1, carbsG: 10, fatG: 6, fiberG: 1
        ),
        CommonFood(
            id: "baked-beans", name: "Baked beans",
            // USDA FDC #172940
            aliases: ["baked beans", "bbq baked beans", "boston baked beans"],
            servingLabel: "½ cup (127 g)",
            calories: 130, proteinG: 7, carbsG: 26, fatG: 0, fiberG: 7
        ),
        CommonFood(
            id: "cheesecake", name: "Cheesecake",
            // USDA FDC #168980
            aliases: ["cheesecake", "new york cheesecake"],
            servingLabel: "1 slice (80 g)",
            calories: 257, proteinG: 4, carbsG: 20, fatG: 18, fiberG: 0
        ),
        CommonFood(
            id: "apple-pie", name: "Apple pie",
            // USDA FDC #168924
            aliases: ["apple pie", "homemade apple pie"],
            servingLabel: "1 slice (117 g, ⅛ pie)",
            calories: 296, proteinG: 2, carbsG: 43, fatG: 14, fiberG: 2
        ),
        CommonFood(
            id: "banana-bread", name: "Banana bread",
            // USDA FDC #172778
            aliases: ["banana bread", "banana loaf"],
            servingLabel: "1 slice (57 g)",
            calories: 196, proteinG: 3, carbsG: 33, fatG: 6, fiberG: 1
        ),

        // — Indian
        CommonFood(
            id: "butter-chicken", name: "Butter chicken",
            aliases: ["butter chicken", "chicken makhani", "chicken tikka masala", "tikka masala"],
            servingLabel: "1 cup curry (240 g, no rice)",
            calories: 350, proteinG: 30, carbsG: 12, fatG: 22, fiberG: 2
        ),
        CommonFood(
            id: "biryani-chicken", name: "Chicken biryani",
            aliases: ["biryani", "chicken biryani", "lamb biryani", "biryani rice"],
            servingLabel: "1 cup (200 g)",
            calories: 320, proteinG: 18, carbsG: 42, fatG: 9, fiberG: 2
        ),
        CommonFood(
            id: "chana-masala", name: "Chana masala",
            aliases: ["chana masala", "chole", "chickpea curry", "chana curry"],
            servingLabel: "1 cup (200 g)",
            calories: 220, proteinG: 11, carbsG: 32, fatG: 7, fiberG: 9
        ),
        CommonFood(
            id: "dal-lentil", name: "Dal",
            aliases: ["dal", "daal", "lentil dal", "yellow dal", "masoor dal", "toor dal"],
            servingLabel: "1 cup (200 g)",
            calories: 190, proteinG: 12, carbsG: 28, fatG: 4, fiberG: 8
        ),
        CommonFood(
            id: "palak-paneer", name: "Palak paneer",
            aliases: ["palak paneer", "saag paneer", "spinach paneer"],
            servingLabel: "1 cup (200 g)",
            calories: 280, proteinG: 14, carbsG: 12, fatG: 20, fiberG: 4
        ),
        CommonFood(
            id: "samosa", name: "Samosa",
            aliases: ["samosa", "samosas", "fried samosa", "potato samosa"],
            servingLabel: "1 piece (60 g)",
            calories: 130, proteinG: 3, carbsG: 16, fatG: 7, fiberG: 2
        ),

        // — Chinese / Dim sum
        CommonFood(
            id: "gyoza-dumplings", name: "Dumplings / Gyoza",
            // USDA SR Legacy Chinese restaurant dumpling estimate
            aliases: ["dumplings", "gyoza", "potstickers", "pot stickers", "jiaozi", "steam dumplings", "fried dumplings"],
            servingLabel: "6 pieces (180 g, pan-fried)",
            calories: 330, proteinG: 16, carbsG: 36, fatG: 14, fiberG: 2
        ),
        CommonFood(
            id: "spring-rolls-fried", name: "Spring rolls (fried)",
            aliases: ["spring rolls", "fried spring rolls", "egg rolls", "egg roll"],
            servingLabel: "2 rolls (120 g)",
            calories: 260, proteinG: 8, carbsG: 28, fatG: 13, fiberG: 2
        ),
        CommonFood(
            id: "fresh-spring-rolls", name: "Fresh spring rolls",
            aliases: ["fresh spring rolls", "summer rolls", "vietnamese spring rolls", "rice paper rolls", "goi cuon"],
            servingLabel: "2 rolls (160 g)",
            calories: 160, proteinG: 8, carbsG: 24, fatG: 4, fiberG: 2
        ),
        CommonFood(
            id: "bao-bun", name: "Bao / Steamed bun",
            aliases: ["bao", "bao bun", "char siu bao", "steamed bun", "baozi", "pork bao"],
            servingLabel: "1 bun (80 g)",
            calories: 195, proteinG: 8, carbsG: 30, fatG: 5, fiberG: 1
        ),
        CommonFood(
            id: "kung-pao-chicken", name: "Kung pao chicken",
            // USDA SR Legacy "Restaurant, Chinese, kung pao chicken"
            aliases: ["kung pao chicken", "kung po chicken", "kung pao"],
            servingLabel: "1 cup (162 g)",
            calories: 410, proteinG: 27, carbsG: 22, fatG: 25, fiberG: 3
        ),
        CommonFood(
            id: "sweet-sour-chicken", name: "Sweet and sour chicken",
            aliases: ["sweet and sour chicken", "sweet sour chicken", "sweet and sour pork"],
            servingLabel: "1 cup (162 g)",
            calories: 380, proteinG: 22, carbsG: 40, fatG: 14, fiberG: 1
        ),
        CommonFood(
            id: "mapo-tofu", name: "Mapo tofu",
            aliases: ["mapo tofu", "mapo doufu"],
            servingLabel: "1 cup (200 g)",
            calories: 200, proteinG: 12, carbsG: 10, fatG: 12, fiberG: 2
        ),
        CommonFood(
            id: "char-siu", name: "Char siu (BBQ pork)",
            aliases: ["char siu", "char siew", "chinese bbq pork", "red bbq pork"],
            servingLabel: "3 oz (85 g)",
            calories: 214, proteinG: 23, carbsG: 10, fatG: 9, fiberG: 0
        ),
        CommonFood(
            id: "peking-duck", name: "Peking duck",
            aliases: ["peking duck", "beijing duck", "roast duck pancake"],
            servingLabel: "2 pancakes with duck + hoisin (120 g)",
            calories: 280, proteinG: 18, carbsG: 24, fatG: 12, fiberG: 1
        ),
        CommonFood(
            id: "sesame-chicken", name: "Sesame chicken",
            aliases: ["sesame chicken", "sesame tofu"],
            servingLabel: "1 cup (162 g)",
            calories: 420, proteinG: 24, carbsG: 38, fatG: 18, fiberG: 1
        ),

        // — Japanese
        CommonFood(
            id: "katsu-curry", name: "Katsu curry",
            aliases: ["katsu curry", "chicken katsu curry", "japanese curry", "katsu rice"],
            servingLabel: "1 plate (rice + chicken katsu + curry, ~400 g)",
            calories: 650, proteinG: 30, carbsG: 75, fatG: 22, fiberG: 4
        ),
        CommonFood(
            id: "tonkatsu", name: "Tonkatsu",
            aliases: ["tonkatsu", "pork cutlet", "breaded pork cutlet", "tonkatsu pork"],
            servingLabel: "1 cutlet (180 g)",
            calories: 420, proteinG: 30, carbsG: 25, fatG: 22, fiberG: 1
        ),
        CommonFood(
            id: "tempura-shrimp", name: "Tempura",
            aliases: ["tempura", "shrimp tempura", "vegetable tempura", "tempura shrimp"],
            servingLabel: "4 pieces (100 g)",
            calories: 225, proteinG: 11, carbsG: 18, fatG: 12, fiberG: 1
        ),
        CommonFood(
            id: "onigiri", name: "Onigiri (rice ball)",
            aliases: ["onigiri", "rice ball", "japanese rice ball", "omusubi"],
            servingLabel: "1 rice ball (100 g)",
            calories: 180, proteinG: 4, carbsG: 35, fatG: 2, fiberG: 1
        ),

        // — Korean
        CommonFood(
            id: "korean-fried-chicken", name: "Korean fried chicken",
            aliases: ["korean fried chicken", "kfc korean", "crispy korean chicken", "yangnyeom chicken"],
            servingLabel: "4 pieces (~200 g)",
            calories: 480, proteinG: 32, carbsG: 30, fatG: 25, fiberG: 1
        ),
        CommonFood(
            id: "tteokbokki", name: "Tteokbokki",
            aliases: ["tteokbokki", "ddukbokki", "korean rice cakes", "spicy rice cakes"],
            servingLabel: "1 cup (200 g)",
            calories: 310, proteinG: 8, carbsG: 62, fatG: 4, fiberG: 2
        ),
        CommonFood(
            id: "japchae", name: "Japchae",
            aliases: ["japchae", "japchae noodles", "korean glass noodles", "stir fry glass noodles"],
            servingLabel: "1 cup (175 g)",
            calories: 290, proteinG: 9, carbsG: 50, fatG: 7, fiberG: 2
        ),
        CommonFood(
            id: "kimchi", name: "Kimchi",
            // USDA FDC #173438
            aliases: ["kimchi", "kimchee"],
            servingLabel: "½ cup (75 g)",
            calories: 23, proteinG: 2, carbsG: 4, fatG: 0, fiberG: 2
        ),
        CommonFood(
            id: "kimchi-fried-rice", name: "Kimchi fried rice",
            aliases: ["kimchi fried rice", "kimchi bokkeumbap"],
            servingLabel: "1 cup (200 g)",
            calories: 270, proteinG: 9, carbsG: 40, fatG: 8, fiberG: 2
        ),
        CommonFood(
            id: "galbi-bbq-ribs", name: "Galbi (Korean BBQ ribs)",
            aliases: ["galbi", "kalbi", "korean short ribs", "korean bbq ribs", "la galbi"],
            servingLabel: "3 oz cooked (85 g)",
            calories: 250, proteinG: 22, carbsG: 5, fatG: 15, fiberG: 0
        ),
        CommonFood(
            id: "bulgogi", name: "Bulgogi",
            aliases: ["bulgogi", "korean bbq beef", "marinated beef", "korean beef"],
            servingLabel: "3 oz (85 g)",
            calories: 200, proteinG: 22, carbsG: 6, fatG: 10, fiberG: 0
        ),

        // — Thai
        CommonFood(
            id: "green-curry", name: "Green curry",
            aliases: ["green curry", "thai green curry", "gaeng keow wan"],
            servingLabel: "1 cup curry with chicken (240 g, no rice)",
            calories: 300, proteinG: 22, carbsG: 12, fatG: 20, fiberG: 3
        ),
        CommonFood(
            id: "red-curry", name: "Red curry",
            aliases: ["red curry", "thai red curry", "gaeng daeng"],
            servingLabel: "1 cup curry with chicken (240 g, no rice)",
            calories: 310, proteinG: 22, carbsG: 14, fatG: 20, fiberG: 3
        ),
        CommonFood(
            id: "massaman-curry", name: "Massaman curry",
            aliases: ["massaman curry", "thai massaman", "panang curry"],
            servingLabel: "1 cup curry (240 g, no rice)",
            calories: 340, proteinG: 18, carbsG: 22, fatG: 22, fiberG: 4
        ),
        CommonFood(
            id: "tom-kha-soup", name: "Tom kha soup",
            aliases: ["tom kha", "tom kha soup", "coconut galangal soup", "tom kha gai"],
            servingLabel: "1 cup (240 g)",
            calories: 160, proteinG: 10, carbsG: 8, fatG: 10, fiberG: 1
        ),
        CommonFood(
            id: "mango-sticky-rice", name: "Mango sticky rice",
            aliases: ["mango sticky rice", "khao niao mamuang", "sticky rice mango"],
            servingLabel: "1 serving (200 g)",
            calories: 340, proteinG: 4, carbsG: 62, fatG: 9, fiberG: 3
        ),

        // — Middle Eastern
        CommonFood(
            id: "shawarma", name: "Shawarma",
            aliases: ["shawarma", "chicken shawarma", "beef shawarma", "lamb shawarma"],
            servingLabel: "1 wrap (280 g)",
            calories: 490, proteinG: 30, carbsG: 46, fatG: 18, fiberG: 4
        ),
        CommonFood(
            id: "tabbouleh", name: "Tabbouleh",
            aliases: ["tabbouleh", "tabouleh", "tabouli"],
            servingLabel: "½ cup (80 g)",
            calories: 80, proteinG: 2, carbsG: 10, fatG: 4, fiberG: 2
        ),
        CommonFood(
            id: "baba-ganoush", name: "Baba ganoush",
            aliases: ["baba ganoush", "baba ghanoush", "eggplant dip"],
            servingLabel: "¼ cup (60 g)",
            calories: 70, proteinG: 2, carbsG: 8, fatG: 4, fiberG: 3
        ),
        CommonFood(
            id: "dolmas", name: "Stuffed grape leaves",
            aliases: ["stuffed grape leaves", "dolmas", "dolmades", "grape leaves"],
            servingLabel: "4 pieces (80 g)",
            calories: 130, proteinG: 3, carbsG: 18, fatG: 6, fiberG: 2
        ),

        // — Mexican / Latino
        CommonFood(
            id: "enchiladas-chicken", name: "Chicken enchiladas",
            // USDA FDC #172951
            aliases: ["enchiladas", "chicken enchiladas", "beef enchiladas", "enchilada"],
            servingLabel: "2 enchiladas (240 g)",
            calories: 520, proteinG: 28, carbsG: 48, fatG: 22, fiberG: 6
        ),
        CommonFood(
            id: "tamales", name: "Tamales",
            // USDA FDC #172947
            aliases: ["tamale", "tamales", "corn tamales", "pork tamales"],
            servingLabel: "2 tamales (170 g)",
            calories: 380, proteinG: 14, carbsG: 44, fatG: 18, fiberG: 4
        ),
        CommonFood(
            id: "al-pastor-tacos", name: "Al pastor tacos",
            aliases: ["al pastor", "al pastor tacos", "tacos al pastor"],
            servingLabel: "2 street tacos (160 g)",
            calories: 320, proteinG: 18, carbsG: 30, fatG: 14, fiberG: 3
        ),
        CommonFood(
            id: "carnitas-tacos", name: "Carnitas tacos",
            aliases: ["carnitas tacos", "tacos de carnitas", "pork tacos"],
            servingLabel: "2 street tacos (160 g)",
            calories: 350, proteinG: 20, carbsG: 28, fatG: 18, fiberG: 3
        ),
        CommonFood(
            id: "carne-asada", name: "Carne asada",
            aliases: ["carne asada", "grilled carne asada", "carne asada tacos"],
            servingLabel: "3 oz (85 g)",
            calories: 190, proteinG: 22, carbsG: 1, fatG: 11, fiberG: 0
        ),
        CommonFood(
            id: "huevos-rancheros", name: "Huevos rancheros",
            aliases: ["huevos rancheros", "huevos"],
            servingLabel: "2 eggs with tortilla + salsa + beans (300 g)",
            calories: 450, proteinG: 22, carbsG: 40, fatG: 22, fiberG: 7
        ),
        CommonFood(
            id: "arroz-con-pollo", name: "Arroz con pollo",
            aliases: ["arroz con pollo", "chicken and rice latin", "pollo con arroz"],
            servingLabel: "1 cup (220 g)",
            calories: 320, proteinG: 22, carbsG: 35, fatG: 9, fiberG: 2
        ),
        CommonFood(
            id: "black-beans-rice", name: "Black beans and rice",
            aliases: ["black beans and rice", "rice and beans", "moros y cristianos", "moros", "gallo pinto"],
            servingLabel: "1 cup (200 g)",
            calories: 280, proteinG: 10, carbsG: 54, fatG: 1, fiberG: 8
        ),
        CommonFood(
            id: "cubano-sandwich", name: "Cuban sandwich",
            aliases: ["cubano", "cuban sandwich", "medianoche"],
            servingLabel: "1 sandwich (250 g)",
            calories: 520, proteinG: 30, carbsG: 46, fatG: 22, fiberG: 2
        ),
        CommonFood(
            id: "empanadas", name: "Empanadas",
            aliases: ["empanada", "empanadas", "beef empanada", "chicken empanada"],
            servingLabel: "2 pieces (140 g)",
            calories: 380, proteinG: 14, carbsG: 38, fatG: 20, fiberG: 2
        ),
        CommonFood(
            id: "tostones", name: "Tostones (fried plantains)",
            aliases: ["tostones", "fried plantains", "patacones", "green plantains"],
            servingLabel: "6 pieces (150 g)",
            calories: 218, proteinG: 2, carbsG: 48, fatG: 2, fiberG: 4
        ),
        CommonFood(
            id: "maduros", name: "Maduros (sweet plantains)",
            aliases: ["maduros", "sweet plantains", "platanos maduros", "fried sweet plantains"],
            servingLabel: "½ cup (100 g)",
            calories: 180, proteinG: 1, carbsG: 41, fatG: 3, fiberG: 3
        ),
        CommonFood(
            id: "elotes", name: "Elotes (Mexican street corn)",
            aliases: ["elotes", "street corn", "mexican corn", "elote"],
            servingLabel: "1 ear with toppings",
            calories: 290, proteinG: 7, carbsG: 40, fatG: 13, fiberG: 4
        ),
        CommonFood(
            id: "flautas", name: "Flautas / taquitos",
            aliases: ["flautas", "taquitos", "rolled tacos", "flautas de pollo"],
            servingLabel: "3 pieces (120 g)",
            calories: 350, proteinG: 16, carbsG: 36, fatG: 16, fiberG: 3
        ),
        CommonFood(
            id: "pozole", name: "Pozole",
            aliases: ["pozole", "posole", "red pozole", "pork pozole"],
            servingLabel: "1 cup (240 g)",
            calories: 190, proteinG: 15, carbsG: 22, fatG: 5, fiberG: 4
        ),
        CommonFood(
            id: "ceviche", name: "Ceviche",
            aliases: ["ceviche", "cebiche", "fish ceviche", "shrimp ceviche"],
            servingLabel: "½ cup (120 g)",
            calories: 100, proteinG: 14, carbsG: 8, fatG: 2, fiberG: 1
        ),
        CommonFood(
            id: "tres-leches", name: "Tres leches cake",
            aliases: ["tres leches", "tres leches cake", "three milk cake"],
            servingLabel: "1 slice (120 g)",
            calories: 360, proteinG: 7, carbsG: 50, fatG: 16, fiberG: 0
        ),
        CommonFood(
            id: "churros", name: "Churros",
            aliases: ["churros", "churro", "churros with chocolate"],
            servingLabel: "2 churros (60 g)",
            calories: 280, proteinG: 3, carbsG: 44, fatG: 10, fiberG: 1
        ),

        // — Filipino
        CommonFood(
            id: "chicken-adobo", name: "Chicken adobo",
            aliases: ["chicken adobo", "adobo", "pork adobo", "filipino adobo"],
            servingLabel: "1 serving (200 g)",
            calories: 380, proteinG: 28, carbsG: 5, fatG: 28, fiberG: 0
        ),
        CommonFood(
            id: "sinigang", name: "Sinigang",
            aliases: ["sinigang", "sinigang na baboy", "sour soup filipino", "pork sinigang"],
            servingLabel: "1 cup (240 g)",
            calories: 150, proteinG: 12, carbsG: 8, fatG: 8, fiberG: 2
        ),
        CommonFood(
            id: "lumpia", name: "Lumpia",
            aliases: ["lumpia", "lumpia shanghai", "filipino spring rolls", "fried lumpia"],
            servingLabel: "3 pieces (90 g)",
            calories: 200, proteinG: 10, carbsG: 18, fatG: 10, fiberG: 1
        ),
        CommonFood(
            id: "pancit-canton", name: "Pancit",
            aliases: ["pancit", "pancit canton", "filipino noodles", "pansit"],
            servingLabel: "1 cup (200 g)",
            calories: 310, proteinG: 15, carbsG: 40, fatG: 9, fiberG: 3
        ),
        CommonFood(
            id: "halo-halo", name: "Halo-halo",
            aliases: ["halo halo", "halo-halo", "filipino shaved ice", "haluhalo"],
            servingLabel: "1 serving (300 g)",
            calories: 340, proteinG: 5, carbsG: 65, fatG: 8, fiberG: 3
        ),
        CommonFood(
            id: "lechon-belly", name: "Lechon",
            aliases: ["lechon", "lechon kawali", "crispy pork belly", "roast pork belly"],
            servingLabel: "3 oz (85 g)",
            calories: 310, proteinG: 18, carbsG: 4, fatG: 25, fiberG: 0
        ),

        // — Italian classics
        CommonFood(
            id: "risotto", name: "Risotto",
            aliases: ["risotto", "mushroom risotto", "arborio risotto", "risotto al funghi"],
            servingLabel: "1 cup (200 g)",
            calories: 280, proteinG: 7, carbsG: 42, fatG: 10, fiberG: 2
        ),
        CommonFood(
            id: "bruschetta", name: "Bruschetta",
            aliases: ["bruschetta", "tomato bruschetta", "bruschetta al pomodoro"],
            servingLabel: "2 slices (80 g)",
            calories: 170, proteinG: 4, carbsG: 26, fatG: 6, fiberG: 2
        ),
        CommonFood(
            id: "caprese-salad", name: "Caprese salad",
            aliases: ["caprese", "caprese salad", "tomato mozzarella", "insalata caprese"],
            servingLabel: "1 serving (200 g, mozzarella + tomato + basil + oil)",
            calories: 280, proteinG: 12, carbsG: 8, fatG: 22, fiberG: 1
        ),
        CommonFood(
            id: "tiramisu", name: "Tiramisu",
            // USDA FDC #172969
            aliases: ["tiramisu", "tiramisù"],
            servingLabel: "1 slice (100 g)",
            calories: 310, proteinG: 6, carbsG: 35, fatG: 17, fiberG: 0
        ),
        CommonFood(
            id: "arancini", name: "Arancini",
            aliases: ["arancini", "rice balls", "sicilian arancini", "fried rice balls"],
            servingLabel: "2 pieces (120 g)",
            calories: 320, proteinG: 10, carbsG: 40, fatG: 14, fiberG: 2
        ),
        CommonFood(
            id: "gnocchi-dish", name: "Gnocchi with sauce",
            aliases: ["gnocchi with sauce", "gnocchi al pomodoro", "gnocchi dish"],
            servingLabel: "1 cup gnocchi + tomato sauce (250 g)",
            calories: 320, proteinG: 8, carbsG: 60, fatG: 6, fiberG: 4
        ),

        // — French / European
        CommonFood(
            id: "crepe", name: "Crêpe",
            aliases: ["crepe", "crêpe", "french crepe", "sweet crepe", "savory crepe"],
            servingLabel: "2 crêpes (100 g)",
            calories: 180, proteinG: 5, carbsG: 24, fatG: 7, fiberG: 1
        ),
        CommonFood(
            id: "quiche", name: "Quiche",
            aliases: ["quiche", "quiche lorraine", "egg tart savory"],
            servingLabel: "1 slice (150 g)",
            calories: 380, proteinG: 12, carbsG: 22, fatG: 28, fiberG: 1
        ),
        CommonFood(
            id: "creme-brulee", name: "Crème brûlée",
            // USDA FDC #172962
            aliases: ["creme brulee", "crème brûlée", "cream brulee"],
            servingLabel: "1 ramekin (120 g)",
            calories: 280, proteinG: 5, carbsG: 30, fatG: 16, fiberG: 0
        ),
        CommonFood(
            id: "pierogi", name: "Pierogi",
            aliases: ["pierogi", "perogies", "potato pierogi", "cheese pierogi", "vareniki"],
            servingLabel: "4 pieces (180 g)",
            calories: 340, proteinG: 10, carbsG: 52, fatG: 11, fiberG: 3
        ),

        // — Japanese extras
        CommonFood(
            id: "yakitori", name: "Yakitori",
            aliases: ["yakitori", "chicken skewers", "grilled chicken skewers", "teriyaki skewers"],
            servingLabel: "4 skewers (100 g)",
            calories: 180, proteinG: 22, carbsG: 6, fatG: 8, fiberG: 0
        ),
        CommonFood(
            id: "okonomiyaki", name: "Okonomiyaki",
            aliases: ["okonomiyaki", "japanese pancake", "savory pancake", "okonomiyaki japanese"],
            servingLabel: "1 pancake (200 g)",
            calories: 350, proteinG: 18, carbsG: 40, fatG: 13, fiberG: 3
        ),
        CommonFood(
            id: "natto", name: "Natto",
            // USDA FDC #168572
            aliases: ["natto", "fermented soybeans", "nattokinase"],
            servingLabel: "1 pack (50 g)",
            calories: 93, proteinG: 8, carbsG: 6, fatG: 5, fiberG: 3
        ),

        // — Ethiopian
        CommonFood(
            id: "injera", name: "Injera",
            aliases: ["injera", "ethiopian flatbread", "sour flatbread"],
            servingLabel: "1 piece (65 g)",
            calories: 150, proteinG: 4, carbsG: 28, fatG: 1, fiberG: 3
        ),
        CommonFood(
            id: "doro-wat", name: "Doro wat",
            aliases: ["doro wat", "doro wot", "ethiopian chicken stew", "ethiopian stew"],
            servingLabel: "½ cup (120 g)",
            calories: 250, proteinG: 22, carbsG: 8, fatG: 15, fiberG: 2
        ),

        // — Mediterranean / Spanish
        CommonFood(
            id: "paella", name: "Paella",
            aliases: ["paella", "seafood paella", "chicken paella", "arroz valenciana"],
            servingLabel: "1 cup (220 g)",
            calories: 380, proteinG: 22, carbsG: 50, fatG: 10, fiberG: 3
        ),
        CommonFood(
            id: "spanakopita", name: "Spanakopita",
            aliases: ["spanakopita", "spinach pie", "greek spinach pastry", "spinach feta pie"],
            servingLabel: "1 piece (85 g)",
            calories: 250, proteinG: 8, carbsG: 26, fatG: 13, fiberG: 2
        ),
        CommonFood(
            id: "moussaka", name: "Moussaka",
            aliases: ["moussaka", "greek moussaka", "eggplant moussaka"],
            servingLabel: "1 serving (250 g)",
            calories: 350, proteinG: 18, carbsG: 20, fatG: 22, fiberG: 4
        ),
        CommonFood(
            id: "avocado-toast", name: "Avocado toast",
            aliases: ["avocado toast", "avo toast"],
            servingLabel: "2 slices toast + ½ avocado (200 g)",
            calories: 320, proteinG: 8, carbsG: 34, fatG: 18, fiberG: 9
        ),

        // — Misc popular
        CommonFood(
            id: "mochi", name: "Mochi",
            aliases: ["mochi", "mochi ice cream", "japanese rice cake"],
            servingLabel: "2 pieces (60 g)",
            calories: 130, proteinG: 2, carbsG: 30, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "cannoli", name: "Cannoli",
            aliases: ["cannoli", "cannolo", "italian cannoli"],
            servingLabel: "2 mini cannoli (60 g)",
            calories: 240, proteinG: 5, carbsG: 26, fatG: 13, fiberG: 1
        ),
        CommonFood(
            id: "pumpkin-pie", name: "Pumpkin pie",
            // USDA FDC #172952
            aliases: ["pumpkin pie", "pumpkin tart"],
            servingLabel: "1 slice (109 g, ⅛ pie)",
            calories: 316, proteinG: 7, carbsG: 41, fatG: 14, fiberG: 3
        ),
        CommonFood(
            id: "egg-fried-rice", name: "Egg fried rice",
            aliases: ["egg fried rice", "chinese egg fried rice", "fried rice egg"],
            servingLabel: "1 cup (137 g)",
            calories: 250, proteinG: 8, carbsG: 44, fatG: 5, fiberG: 2
        ),
        CommonFood(
            id: "beef-bulgogi-bowl", name: "Bulgogi rice bowl",
            aliases: ["bulgogi bowl", "bulgogi rice bowl", "korean beef rice bowl"],
            servingLabel: "1 bowl (350 g)",
            calories: 520, proteinG: 30, carbsG: 62, fatG: 15, fiberG: 3
        ),
        CommonFood(
            id: "pho-chicken", name: "Chicken pho",
            aliases: ["chicken pho", "pho ga", "pho gà"],
            servingLabel: "1 bowl (600 g, broth + noodles + chicken)",
            calories: 380, proteinG: 26, carbsG: 47, fatG: 6, fiberG: 2
        ),

        // — Filipino (extended)
        CommonFood(
            id: "sisig", name: "Sisig",
            aliases: ["sisig", "sizzling sisig", "pork sisig", "chicken sisig", "tofu sisig"],
            servingLabel: "1 sizzling plate (200 g)",
            calories: 420, proteinG: 24, carbsG: 6, fatG: 34, fiberG: 0
        ),
        CommonFood(
            id: "kare-kare", name: "Kare-kare",
            aliases: ["kare kare", "kare-kare", "oxtail peanut stew", "peanut stew filipino"],
            servingLabel: "1 cup stew (240 g)",
            calories: 350, proteinG: 24, carbsG: 12, fatG: 24, fiberG: 3
        ),
        CommonFood(
            id: "arroz-caldo", name: "Arroz caldo",
            aliases: ["arroz caldo", "filipino rice porridge", "lugaw", "chicken porridge filipino", "tinolang lugaw"],
            servingLabel: "1 cup (250 g)",
            calories: 180, proteinG: 12, carbsG: 22, fatG: 4, fiberG: 1
        ),
        CommonFood(
            id: "tocino", name: "Tocino",
            aliases: ["tocino", "filipino tocino", "sweet pork breakfast", "chicken tocino", "pork tocino"],
            servingLabel: "3 oz grilled (85 g)",
            calories: 240, proteinG: 16, carbsG: 12, fatG: 14, fiberG: 0
        ),
        CommonFood(
            id: "longganisa", name: "Longganisa",
            aliases: ["longganisa", "longanisa", "filipino sausage", "garlic sausage filipino", "sweet sausage philippine"],
            servingLabel: "2 links grilled (80 g)",
            calories: 270, proteinG: 12, carbsG: 8, fatG: 22, fiberG: 0
        ),
        CommonFood(
            id: "palabok", name: "Palabok",
            aliases: ["palabok", "pancit palabok", "noodles with shrimp sauce", "filipino palabok"],
            servingLabel: "1 cup (200 g)",
            calories: 310, proteinG: 14, carbsG: 42, fatG: 10, fiberG: 2
        ),
        CommonFood(
            id: "bulalo", name: "Bulalo",
            aliases: ["bulalo", "beef bulalo", "beef marrow soup", "bulalo soup"],
            servingLabel: "1 cup broth with beef (240 g)",
            calories: 250, proteinG: 22, carbsG: 4, fatG: 16, fiberG: 1
        ),
        CommonFood(
            id: "tinola", name: "Tinola",
            aliases: ["tinola", "chicken tinola", "tinolang manok", "ginger chicken soup filipino"],
            servingLabel: "1 cup (240 g)",
            calories: 155, proteinG: 16, carbsG: 8, fatG: 7, fiberG: 2
        ),
        CommonFood(
            id: "giniling", name: "Giniling",
            aliases: ["giniling", "pork giniling", "beef giniling", "ground pork stew filipino", "picadillo filipino"],
            servingLabel: "1 cup (200 g)",
            calories: 290, proteinG: 18, carbsG: 18, fatG: 16, fiberG: 2
        ),
        CommonFood(
            id: "lomi", name: "Lomi",
            aliases: ["lomi", "lomi batangas", "lomi noodles", "thick noodle soup filipino"],
            servingLabel: "1 bowl (300 g)",
            calories: 320, proteinG: 16, carbsG: 40, fatG: 10, fiberG: 2
        ),

        // — Colombian (extended)
        CommonFood(
            id: "bandeja-paisa", name: "Bandeja paisa",
            aliases: ["bandeja paisa", "bandeja", "colombian platter", "paisa platter", "bandeja antioqueña"],
            servingLabel: "1 full plate (~600 g)",
            calories: 1050, proteinG: 52, carbsG: 92, fatG: 52, fiberG: 14
        ),
        CommonFood(
            id: "sancocho", name: "Sancocho",
            aliases: ["sancocho", "colombian sancocho", "chicken sancocho", "sancocho de pollo", "sancocho trifasico"],
            servingLabel: "1 cup (240 g)",
            calories: 190, proteinG: 14, carbsG: 20, fatG: 6, fiberG: 3
        ),
        CommonFood(
            id: "ajiaco", name: "Ajiaco",
            aliases: ["ajiaco", "ajiaco bogotano", "colombian chicken potato soup"],
            servingLabel: "1 cup (240 g)",
            calories: 210, proteinG: 16, carbsG: 22, fatG: 6, fiberG: 3
        ),
        CommonFood(
            id: "changua", name: "Changua",
            aliases: ["changua", "colombian milk soup", "egg milk soup", "colombian breakfast soup"],
            servingLabel: "1 cup (240 g)",
            calories: 130, proteinG: 9, carbsG: 8, fatG: 7, fiberG: 0
        ),

        // — Indian (extended)
        CommonFood(
            id: "tandoori-chicken", name: "Tandoori chicken",
            aliases: ["tandoori chicken", "tandoor chicken", "murgh tandoori", "tandoori murgh"],
            servingLabel: "3 oz cooked (85 g)",
            calories: 175, proteinG: 24, carbsG: 4, fatG: 6, fiberG: 0
        ),
        CommonFood(
            id: "aloo-gobi", name: "Aloo gobi",
            aliases: ["aloo gobi", "potato cauliflower curry", "aloo gobi sabzi"],
            servingLabel: "1 cup (200 g)",
            calories: 180, proteinG: 5, carbsG: 28, fatG: 7, fiberG: 5
        ),
        CommonFood(
            id: "rajma", name: "Rajma",
            aliases: ["rajma", "kidney bean curry", "rajma masala", "rajma chawal"],
            servingLabel: "1 cup (200 g)",
            calories: 250, proteinG: 13, carbsG: 40, fatG: 5, fiberG: 10
        ),
        CommonFood(
            id: "dosa", name: "Dosa",
            aliases: ["dosa", "plain dosa", "dosai", "rice lentil crepe", "crispy dosa"],
            servingLabel: "1 dosa (100 g)",
            calories: 162, proteinG: 4, carbsG: 26, fatG: 4, fiberG: 2
        ),
        CommonFood(
            id: "masala-dosa", name: "Masala dosa",
            aliases: ["masala dosa", "potato dosa", "stuffed dosa", "masala dosai"],
            servingLabel: "1 dosa with potato filling (250 g)",
            calories: 330, proteinG: 8, carbsG: 52, fatG: 10, fiberG: 4
        ),
        CommonFood(
            id: "idli", name: "Idli",
            aliases: ["idli", "idly", "steamed rice cake indian", "idli sambar"],
            servingLabel: "3 idli (150 g)",
            calories: 170, proteinG: 5, carbsG: 32, fatG: 1, fiberG: 2
        ),
        CommonFood(
            id: "chicken-korma", name: "Chicken korma",
            aliases: ["chicken korma", "korma", "mild chicken curry", "creamy korma"],
            servingLabel: "1 cup (240 g, no rice)",
            calories: 390, proteinG: 28, carbsG: 14, fatG: 26, fiberG: 2
        ),
        CommonFood(
            id: "chicken-vindaloo", name: "Chicken vindaloo",
            aliases: ["chicken vindaloo", "vindaloo", "goan vindaloo", "spicy goan curry", "pork vindaloo"],
            servingLabel: "1 cup (240 g, no rice)",
            calories: 340, proteinG: 28, carbsG: 12, fatG: 20, fiberG: 2
        ),
        CommonFood(
            id: "raita", name: "Raita",
            aliases: ["raita", "cucumber raita", "onion raita", "boondi raita", "yogurt cucumber dip indian"],
            servingLabel: "½ cup (113 g)",
            calories: 65, proteinG: 4, carbsG: 7, fatG: 2, fiberG: 0
        ),
        CommonFood(
            id: "gulab-jamun", name: "Gulab jamun",
            aliases: ["gulab jamun", "gulab jaman", "indian milk dumplings", "fried milk sweet"],
            servingLabel: "2 pieces (80 g)",
            calories: 200, proteinG: 3, carbsG: 34, fatG: 6, fiberG: 0
        ),
        CommonFood(
            id: "pav-bhaji", name: "Pav bhaji",
            aliases: ["pav bhaji", "pav bhaaji", "bhaji pav", "mumbai street food pav", "street food bhaji"],
            servingLabel: "1 serving with 2 pav (240 g)",
            calories: 360, proteinG: 10, carbsG: 54, fatG: 12, fiberG: 6
        ),

        // — Nigerian / West African
        CommonFood(
            id: "jollof-rice", name: "Jollof rice",
            aliases: ["jollof rice", "nigerian jollof", "ghanaian jollof", "west african jollof", "party jollof"],
            servingLabel: "1 cup (200 g)",
            calories: 330, proteinG: 7, carbsG: 60, fatG: 8, fiberG: 3
        ),
        CommonFood(
            id: "egusi-soup", name: "Egusi soup",
            aliases: ["egusi soup", "melon seed soup", "west african egusi", "egusi stew"],
            servingLabel: "½ cup (120 g)",
            calories: 290, proteinG: 16, carbsG: 8, fatG: 22, fiberG: 3
        ),
        CommonFood(
            id: "suya", name: "Suya",
            aliases: ["suya", "nigerian suya", "west african beef skewers", "spiced suya"],
            servingLabel: "3 oz skewers (85 g)",
            calories: 205, proteinG: 24, carbsG: 4, fatG: 10, fiberG: 1
        ),
        CommonFood(
            id: "moi-moi", name: "Moi moi",
            aliases: ["moi moi", "moin moin", "steamed bean pudding", "bean cake nigerian"],
            servingLabel: "1 piece (150 g)",
            calories: 170, proteinG: 10, carbsG: 18, fatG: 6, fiberG: 4
        ),
        CommonFood(
            id: "fufu", name: "Fufu",
            aliases: ["fufu", "pounded yam", "eba", "ugali", "banku", "sadza", "amala"],
            servingLabel: "1 cup (200 g)",
            calories: 330, proteinG: 2, carbsG: 80, fatG: 0, fiberG: 4
        ),
        CommonFood(
            id: "puff-puff-nigerian", name: "Puff puff",
            aliases: ["puff puff", "nigerian puff puff", "african fried dough balls"],
            servingLabel: "3 pieces (75 g)",
            calories: 260, proteinG: 4, carbsG: 32, fatG: 13, fiberG: 1
        ),

        // — Caribbean / Jamaican
        CommonFood(
            id: "jerk-chicken", name: "Jerk chicken",
            aliases: ["jerk chicken", "jamaican jerk chicken", "jerk pork", "jamaican jerk"],
            servingLabel: "3 oz cooked (85 g)",
            calories: 195, proteinG: 24, carbsG: 4, fatG: 9, fiberG: 0
        ),
        CommonFood(
            id: "curry-goat", name: "Curry goat",
            aliases: ["curry goat", "jamaican curry goat", "goat curry", "curried goat"],
            servingLabel: "1 cup (240 g)",
            calories: 300, proteinG: 26, carbsG: 8, fatG: 18, fiberG: 2
        ),
        CommonFood(
            id: "rice-and-peas-jamaican", name: "Rice and peas (Jamaican)",
            aliases: ["rice and peas", "jamaican rice and peas", "coconut rice with beans", "sunday rice jamaican"],
            servingLabel: "1 cup (200 g)",
            calories: 280, proteinG: 7, carbsG: 50, fatG: 6, fiberG: 5
        ),
        CommonFood(
            id: "ackee-saltfish", name: "Ackee and saltfish",
            aliases: ["ackee and saltfish", "ackee saltfish", "jamaican national dish", "ackee codfish"],
            servingLabel: "1 cup (200 g)",
            calories: 260, proteinG: 18, carbsG: 6, fatG: 18, fiberG: 2
        ),
        CommonFood(
            id: "doubles", name: "Doubles (Trinidad)",
            aliases: ["doubles", "trinidad doubles", "bara and channa", "trini doubles"],
            servingLabel: "2 doubles (180 g)",
            calories: 320, proteinG: 10, carbsG: 50, fatG: 9, fiberG: 6
        ),

        // — Brazilian
        CommonFood(
            id: "feijoada", name: "Feijoada",
            aliases: ["feijoada", "brazilian black bean stew", "feijoada completa"],
            servingLabel: "1 cup (240 g)",
            calories: 390, proteinG: 20, carbsG: 38, fatG: 16, fiberG: 8
        ),
        CommonFood(
            id: "brigadeiro", name: "Brigadeiro",
            aliases: ["brigadeiro", "brigadeiros", "chocolate truffle brazilian", "fudge ball brazilian"],
            servingLabel: "2 pieces (40 g)",
            calories: 150, proteinG: 2, carbsG: 22, fatG: 6, fiberG: 1
        ),
        CommonFood(
            id: "coxinha", name: "Coxinha",
            aliases: ["coxinha", "chicken croquette brazilian", "coxinha de frango"],
            servingLabel: "1 piece (80 g)",
            calories: 225, proteinG: 10, carbsG: 22, fatG: 12, fiberG: 1
        ),
        CommonFood(
            id: "moqueca", name: "Moqueca",
            aliases: ["moqueca", "moqueca de peixe", "brazilian fish stew", "bahian coconut fish stew"],
            servingLabel: "1 cup (240 g)",
            calories: 280, proteinG: 22, carbsG: 10, fatG: 18, fiberG: 2
        ),
        CommonFood(
            id: "churrasco", name: "Churrasco",
            aliases: ["churrasco", "brazilian bbq", "rodizio", "picanha", "churrasco steak"],
            servingLabel: "3 oz (85 g)",
            calories: 220, proteinG: 24, carbsG: 0, fatG: 13, fiberG: 0
        ),

        // — Peruvian
        CommonFood(
            id: "lomo-saltado", name: "Lomo saltado",
            aliases: ["lomo saltado", "peruvian stir fry", "beef stir fry peruvian", "lomito saltado"],
            servingLabel: "1 cup (220 g)",
            calories: 370, proteinG: 24, carbsG: 26, fatG: 18, fiberG: 3
        ),
        CommonFood(
            id: "aji-de-gallina", name: "Aji de gallina",
            aliases: ["aji de gallina", "peruvian creamy chicken", "yellow pepper chicken stew", "ajì de gallina"],
            servingLabel: "1 cup (240 g, no rice)",
            calories: 340, proteinG: 26, carbsG: 20, fatG: 18, fiberG: 2
        ),
        CommonFood(
            id: "causa", name: "Causa",
            aliases: ["causa", "causa limeña", "peruvian potato terrine", "causa rellena"],
            servingLabel: "1 serving (150 g)",
            calories: 280, proteinG: 12, carbsG: 36, fatG: 10, fiberG: 3
        ),
        CommonFood(
            id: "anticuchos", name: "Anticuchos",
            aliases: ["anticuchos", "beef heart skewers", "peruvian grilled skewers", "anticuchos de corazon"],
            servingLabel: "4 skewers (100 g)",
            calories: 200, proteinG: 22, carbsG: 6, fatG: 10, fiberG: 1
        ),

        // — Moroccan / North African
        CommonFood(
            id: "chicken-tagine", name: "Chicken tagine",
            aliases: ["chicken tagine", "moroccan tagine", "tagine", "lamb tagine", "moroccan stew"],
            servingLabel: "1 cup (240 g, no couscous)",
            calories: 310, proteinG: 28, carbsG: 18, fatG: 14, fiberG: 4
        ),
        CommonFood(
            id: "harira", name: "Harira",
            aliases: ["harira", "moroccan soup", "moroccan lentil tomato soup", "ramadan soup"],
            servingLabel: "1 cup (240 g)",
            calories: 145, proteinG: 9, carbsG: 22, fatG: 3, fiberG: 5
        ),
        CommonFood(
            id: "shakshuka", name: "Shakshuka",
            aliases: ["shakshuka", "shakshouka", "eggs in tomato sauce", "middle eastern baked eggs"],
            servingLabel: "2 eggs in sauce (280 g)",
            calories: 250, proteinG: 14, carbsG: 20, fatG: 12, fiberG: 4
        ),

        // — Vietnamese (extended)
        CommonFood(
            id: "bun-bo-hue", name: "Bún bò Huế",
            aliases: ["bun bo hue", "bun bo", "spicy beef noodle soup", "hue noodle soup", "vietnamese spicy noodle"],
            servingLabel: "1 bowl (~600 g)",
            calories: 430, proteinG: 28, carbsG: 50, fatG: 12, fiberG: 3
        ),
        CommonFood(
            id: "com-tam", name: "Cơm tấm",
            aliases: ["com tam", "broken rice", "vietnamese broken rice", "com tam saigon", "cơm tấm"],
            servingLabel: "1 plate (380 g, pork + egg + rice)",
            calories: 600, proteinG: 34, carbsG: 68, fatG: 20, fiberG: 3
        ),
        CommonFood(
            id: "banh-xeo", name: "Bánh xèo",
            aliases: ["banh xeo", "sizzling crepe vietnamese", "vietnamese sizzling crepe", "crispy rice crepe"],
            servingLabel: "1 half (150 g)",
            calories: 275, proteinG: 12, carbsG: 28, fatG: 14, fiberG: 2
        ),

        // — Taiwanese
        CommonFood(
            id: "lu-rou-fan", name: "Lu rou fan",
            aliases: ["lu rou fan", "braised pork rice", "minced pork rice bowl", "taiwanese braised pork", "taiwanese pork rice"],
            servingLabel: "1 bowl (300 g)",
            calories: 480, proteinG: 22, carbsG: 60, fatG: 16, fiberG: 2
        ),
        CommonFood(
            id: "taiwanese-beef-noodle", name: "Taiwanese beef noodle soup",
            aliases: ["taiwanese beef noodle soup", "beef noodle soup taiwan", "niu rou mian", "red braised beef noodle"],
            servingLabel: "1 bowl (~600 g)",
            calories: 520, proteinG: 30, carbsG: 62, fatG: 14, fiberG: 4
        ),
        CommonFood(
            id: "scallion-pancake", name: "Scallion pancake",
            aliases: ["scallion pancake", "cong you bing", "green onion pancake", "chinese scallion pancake", "taiwanese pancake"],
            servingLabel: "1 pancake (100 g)",
            calories: 270, proteinG: 5, carbsG: 34, fatG: 13, fiberG: 2
        ),
        CommonFood(
            id: "lechona-tolimense", name: "Lechona tolimense",
            aliases: ["lechona tolimense", "colombian roast pork rice", "lechona colombiana", "stuffed roast pig"],
            servingLabel: "1 cup (250 g)",
            calories: 458, proteinG: 30, carbsG: 35, fatG: 22, fiberG: 3
        ),
        CommonFood(
            id: "tamal-tolimense", name: "Tamal tolimense",
            aliases: ["tamal tolimense", "colombian corn tamal", "tamal del tolima", "banana leaf tamale colombian"],
            servingLabel: "1 tamal (300 g)",
            calories: 470, proteinG: 22, carbsG: 45, fatG: 22, fiberG: 5
        ),
        CommonFood(
            id: "tamal-santandereano", name: "Tamal santandereano",
            aliases: ["tamal santandereano", "tamal de santander", "colombian pork chickpea tamale", "tamal con garbanzo"],
            servingLabel: "1 tamal (320 g)",
            calories: 510, proteinG: 24, carbsG: 50, fatG: 24, fiberG: 6
        ),
        CommonFood(
            id: "sobrebarriga-en-salsa", name: "Sobrebarriga en salsa",
            aliases: ["sobrebarriga en salsa", "colombian flank steak stew", "sobrebarriga criolla", "braised flank steak colombian"],
            servingLabel: "1 serving (220 g)",
            calories: 360, proteinG: 32, carbsG: 8, fatG: 22, fiberG: 2
        ),
        CommonFood(
            id: "posta-negra-cartagenera", name: "Posta negra cartagenera",
            aliases: ["posta negra cartagenera", "cartagena black beef", "colombian black roast beef", "posta negra colombiana"],
            servingLabel: "1 serving (200 g)",
            calories: 330, proteinG: 34, carbsG: 14, fatG: 15, fiberG: 1
        ),
        CommonFood(
            id: "sudado-de-pollo", name: "Sudado de pollo",
            aliases: ["sudado de pollo", "colombian chicken stew", "pollo sudado", "stewed chicken colombian"],
            servingLabel: "1 bowl (350 g)",
            calories: 400, proteinG: 34, carbsG: 30, fatG: 16, fiberG: 4
        ),
        CommonFood(
            id: "frijoles-antioquenos", name: "Fríjoles antioqueños",
            aliases: ["frijoles antioquenos", "colombian red beans", "frijoles paisas", "paisa red bean stew"],
            servingLabel: "1 cup (250 g)",
            calories: 330, proteinG: 17, carbsG: 40, fatG: 11, fiberG: 12
        ),
        CommonFood(
            id: "calentado-paisa", name: "Calentado paisa",
            aliases: ["calentado paisa", "colombian rice and beans breakfast", "calentado colombiano", "reheated rice beans paisa"],
            servingLabel: "1 plate (300 g)",
            calories: 470, proteinG: 18, carbsG: 55, fatG: 19, fiberG: 9
        ),
        CommonFood(
            id: "huevos-pericos", name: "Huevos pericos",
            aliases: ["huevos pericos", "colombian scrambled eggs", "perico eggs", "eggs with tomato and onion colombian"],
            servingLabel: "2 eggs (160 g)",
            calories: 230, proteinG: 14, carbsG: 6, fatG: 17, fiberG: 1
        ),
        CommonFood(
            id: "arroz-atollado", name: "Arroz atollado",
            aliases: ["arroz atollado", "colombian soupy rice", "vallecaucano rice pork", "creamy pork rice colombian"],
            servingLabel: "1 plate (320 g)",
            calories: 480, proteinG: 24, carbsG: 52, fatG: 19, fiberG: 3
        ),
        CommonFood(
            id: "patacon-con-hogao", name: "Patacón con hogao",
            aliases: ["patacon con hogao", "fried plantain with tomato sauce", "patacon colombiano", "tostada de platano hogao"],
            servingLabel: "1 patacón (120 g)",
            calories: 290, proteinG: 3, carbsG: 44, fatG: 12, fiberG: 4
        ),
        CommonFood(
            id: "carne-en-polvo", name: "Carne en polvo",
            aliases: ["carne en polvo", "colombian powdered beef", "carne molida en polvo", "dried ground beef colombian"],
            servingLabel: "½ cup (90 g)",
            calories: 230, proteinG: 28, carbsG: 4, fatG: 11, fiberG: 1
        ),
        CommonFood(
            id: "perro-caliente-colombiano", name: "Perro caliente colombiano",
            aliases: ["perro caliente colombiano", "colombian hot dog", "perro caliente con papas", "loaded hot dog colombian"],
            servingLabel: "1 hot dog (220 g)",
            calories: 540, proteinG: 16, carbsG: 50, fatG: 31, fiberG: 3
        ),
        CommonFood(
            id: "salchipapa-colombiana", name: "Salchipapa",
            aliases: ["salchipapa colombiana", "colombian sausage and fries", "salchipapas", "papas con salchicha"],
            servingLabel: "1 plate (350 g)",
            calories: 720, proteinG: 22, carbsG: 65, fatG: 41, fiberG: 5
        ),
        CommonFood(
            id: "empanada-colombiana", name: "Empanada colombiana",
            aliases: ["empanada colombiana", "colombian corn empanada", "empanada de maiz", "fried corn empanada colombian"],
            servingLabel: "1 empanada (100 g)",
            calories: 280, proteinG: 8, carbsG: 30, fatG: 14, fiberG: 3
        ),
        CommonFood(
            id: "pancit-bihon", name: "Pancit Bihon",
            aliases: ["filipino rice noodle stir fry", "pancit bihon guisado", "pansit bihon", "filipino fried rice noodles"],
            servingLabel: "1 cup (180 g)",
            calories: 320, proteinG: 14, carbsG: 45, fatG: 9, fiberG: 3
        ),
        CommonFood(
            id: "pancit-malabon", name: "Pancit Malabon",
            aliases: ["filipino seafood noodles", "pansit malabon", "thick rice noodle seafood", "malabon noodles"],
            servingLabel: "1 plate (300 g)",
            calories: 420, proteinG: 22, carbsG: 52, fatG: 14, fiberG: 3
        ),
        CommonFood(
            id: "pinakbet", name: "Pinakbet",
            aliases: ["filipino vegetable stew", "pakbet", "ilocano vegetable dish", "sauteed vegetables shrimp paste"],
            servingLabel: "1 cup (200 g)",
            calories: 160, proteinG: 9, carbsG: 16, fatG: 8, fiberG: 5
        ),
        CommonFood(
            id: "dinuguan", name: "Dinuguan",
            aliases: ["filipino pork blood stew", "chocolate meat filipino", "dinuguang baboy", "pork blood pudding stew"],
            servingLabel: "1 cup (240 g)",
            calories: 310, proteinG: 22, carbsG: 8, fatG: 22, fiberG: 1
        ),
        CommonFood(
            id: "kaldereta-beef", name: "Beef Kaldereta",
            aliases: ["filipino beef stew tomato", "kalderetang baka", "caldereta beef", "beef liver sauce stew"],
            servingLabel: "1 cup (250 g)",
            calories: 420, proteinG: 28, carbsG: 14, fatG: 28, fiberG: 3
        ),
        CommonFood(
            id: "mechado", name: "Mechado",
            aliases: ["filipino beef tomato stew", "mitsado beef", "larded beef stew filipino", "mechadong baka"],
            servingLabel: "1 cup (250 g)",
            calories: 380, proteinG: 27, carbsG: 16, fatG: 22, fiberG: 2
        ),
        CommonFood(
            id: "pork-menudo", name: "Pork Menudo",
            aliases: ["filipino pork liver stew", "menudong baboy", "pork tomato liver stew", "ginisang menudo"],
            servingLabel: "1 cup (250 g)",
            calories: 360, proteinG: 24, carbsG: 18, fatG: 21, fiberG: 3
        ),
        CommonFood(
            id: "chicken-afritada", name: "Chicken Afritada",
            aliases: ["filipino chicken tomato stew", "afritadang manok", "chicken afritada filipino", "apritada chicken"],
            servingLabel: "1 cup (250 g)",
            calories: 330, proteinG: 26, carbsG: 18, fatG: 17, fiberG: 3
        ),
        CommonFood(
            id: "bicol-express", name: "Bicol Express",
            aliases: ["filipino pork coconut chili", "bicolano pork stew", "spicy pork coconut milk", "sinilihan"],
            servingLabel: "1 cup (220 g)",
            calories: 350, proteinG: 16, carbsG: 10, fatG: 28, fiberG: 3
        ),
        CommonFood(
            id: "laing", name: "Laing",
            aliases: ["taro leaves coconut milk", "filipino taro leaf stew", "laing bicol", "dried taro leaves coconut"],
            servingLabel: "1 cup (200 g)",
            calories: 230, proteinG: 6, carbsG: 12, fatG: 18, fiberG: 5
        ),
        CommonFood(
            id: "crispy-pata", name: "Crispy Pata",
            aliases: ["filipino crispy pork knuckle", "deep fried pork leg", "crispy pork hock", "krispy pata"],
            servingLabel: "1 serving (250 g)",
            calories: 560, proteinG: 42, carbsG: 2, fatG: 43, fiberG: 0
        ),
        CommonFood(
            id: "lechon-kawali", name: "Lechon Kawali",
            aliases: ["filipino crispy fried pork belly", "pan roasted pork belly", "letson kawali", "deep fried pork belly"],
            servingLabel: "1 serving (150 g)",
            calories: 480, proteinG: 30, carbsG: 0, fatG: 40, fiberG: 0
        ),
        CommonFood(
            id: "bistek-tagalog", name: "Bistek Tagalog",
            aliases: ["filipino beef steak onions", "bistek baka", "filipino soy citrus beef", "beefsteak tagalog"],
            servingLabel: "1 serving (200 g)",
            calories: 340, proteinG: 30, carbsG: 10, fatG: 20, fiberG: 1
        ),
        CommonFood(
            id: "chicken-inasal", name: "Chicken Inasal",
            aliases: ["filipino grilled chicken bacolod", "inasal na manok", "bacolod grilled chicken", "chicken inasal annatto"],
            servingLabel: "1 piece (200 g)",
            calories: 320, proteinG: 34, carbsG: 4, fatG: 19, fiberG: 0
        ),
        CommonFood(
            id: "pork-bbq-skewer-filipino", name: "Filipino Pork BBQ Skewer",
            aliases: ["filipino pork barbecue stick", "pinoy pork bbq", "grilled pork skewer filipino", "pork inihaw skewer"],
            servingLabel: "1 skewer (80 g)",
            calories: 200, proteinG: 18, carbsG: 10, fatG: 10, fiberG: 0
        ),
        CommonFood(
            id: "lumpiang-shanghai", name: "Lumpiang Shanghai",
            aliases: ["filipino fried meat spring rolls", "shanghai lumpia", "pork spring rolls filipino", "fried lumpia shanghai"],
            servingLabel: "3 pieces (120 g)",
            calories: 290, proteinG: 12, carbsG: 22, fatG: 17, fiberG: 1
        ),
        CommonFood(
            id: "tapsilog", name: "Tapsilog",
            aliases: ["filipino beef tapa egg rice", "tapa silog meal", "tapsilog breakfast", "cured beef garlic rice egg"],
            servingLabel: "1 plate (380 g)",
            calories: 650, proteinG: 32, carbsG: 72, fatG: 26, fiberG: 3
        ),
        CommonFood(
            id: "longsilog", name: "Longsilog",
            aliases: ["filipino longganisa egg rice", "longsilog breakfast", "longanisa silog meal", "sausage garlic rice egg"],
            servingLabel: "1 plate (380 g)",
            calories: 680, proteinG: 26, carbsG: 74, fatG: 32, fiberG: 3
        ),
        CommonFood(
            id: "tocilog", name: "Tocilog",
            aliases: ["filipino tocino egg rice", "tocilog breakfast", "sweet cured pork silog", "tosilog meal"],
            servingLabel: "1 plate (380 g)",
            calories: 660, proteinG: 25, carbsG: 80, fatG: 28, fiberG: 3
        ),
        CommonFood(
            id: "tortang-talong", name: "Tortang Talong",
            aliases: ["filipino eggplant omelette", "grilled eggplant egg", "torta talong", "eggplant frittata filipino"],
            servingLabel: "1 piece (150 g)",
            calories: 220, proteinG: 12, carbsG: 9, fatG: 16, fiberG: 4
        ),
        CommonFood(
            id: "ginisang-munggo", name: "Ginisang Munggo",
            aliases: ["filipino mung bean stew", "monggo guisado", "sauteed mung beans filipino", "munggo soup pork"],
            servingLabel: "1 cup (240 g)",
            calories: 240, proteinG: 16, carbsG: 26, fatG: 8, fiberG: 8
        ),
        CommonFood(
            id: "daing-na-bangus", name: "Daing na Bangus",
            aliases: ["filipino fried marinated milkfish", "bangus daing", "marinated milkfish fried", "daing bangus vinegar"],
            servingLabel: "1 fillet (200 g)",
            calories: 340, proteinG: 28, carbsG: 2, fatG: 25, fiberG: 0
        ),
        CommonFood(
            id: "pork-humba", name: "Pork Humba",
            aliases: ["filipino braised pork belly sweet", "humba baboy", "visayan braised pork", "humba pork black beans"],
            servingLabel: "1 cup (240 g)",
            calories: 430, proteinG: 26, carbsG: 16, fatG: 29, fiberG: 1
        ),
        CommonFood(
            id: "digiorno-pepperoni-pizza", name: "DiGiorno frozen pepperoni pizza",
            // DiGiorno official
            aliases: ["digiorno pepperoni pizza", "frozen pepperoni pizza slice", "digiorno rising crust", "quarter frozen pizza"],
            servingLabel: "⅛ pizza (132 g)",
            calories: 360, proteinG: 16, carbsG: 39, fatG: 16, fiberG: 2
        ),
        CommonFood(
            id: "frozen-mac-cheese", name: "Frozen mac & cheese",
            // Stouffer's official
            aliases: ["frozen mac and cheese", "stouffer's macaroni cheese", "microwave mac cheese"],
            servingLabel: "1 cup (227 g)",
            calories: 350, proteinG: 13, carbsG: 41, fatG: 15, fiberG: 2
        ),
        CommonFood(
            id: "corn-dog-frozen", name: "Corn dog (frozen)",
            // State Fair official
            aliases: ["frozen corn dog", "corndog on a stick", "state fair corn dog"],
            servingLabel: "1 corn dog (75 g)",
            calories: 180, proteinG: 6, carbsG: 23, fatG: 7, fiberG: 1
        ),
        CommonFood(
            id: "lunchables-turkey-cheddar", name: "Lunchables turkey & cheddar",
            // Oscar Mayer official
            aliases: ["lunchables turkey cheddar", "turkey cheddar lunchables", "lunchable cracker stackers"],
            servingLabel: "1 tray (101 g)",
            calories: 360, proteinG: 14, carbsG: 35, fatG: 18, fiberG: 1
        ),
        CommonFood(
            id: "velveeta-shells-cheese-cup", name: "Velveeta shells & cheese cup",
            // Velveeta official
            aliases: ["velveeta shells and cheese", "velveeta cup", "microwave shells cheese cup"],
            servingLabel: "1 cup (95 g)",
            calories: 360, proteinG: 9, carbsG: 47, fatG: 16, fiberG: 2
        ),
        CommonFood(
            id: "easy-mac-cup", name: "Easy Mac cup",
            // Kraft official
            aliases: ["easy mac cup", "kraft easy mac", "microwave mac cup"],
            servingLabel: "1 cup prepared (61 g dry)",
            calories: 220, proteinG: 6, carbsG: 40, fatG: 4, fiberG: 1
        ),
        CommonFood(
            id: "hormel-canned-chili", name: "Canned chili (Hormel)",
            // Hormel official
            aliases: ["hormel chili with beans", "canned chili with beans", "hormel chili can"],
            servingLabel: "1 cup (247 g)",
            calories: 260, proteinG: 16, carbsG: 30, fatG: 7, fiberG: 7
        ),
        CommonFood(
            id: "spaghettios", name: "SpaghettiOs",
            // Campbell's official
            aliases: ["spaghettios", "canned spaghetti o's", "franco american pasta rings"],
            servingLabel: "1 cup (252 g)",
            calories: 170, proteinG: 5, carbsG: 33, fatG: 2, fiberG: 3
        ),
        CommonFood(
            id: "chef-boyardee-beef-ravioli", name: "Chef Boyardee beef ravioli",
            // Chef Boyardee official
            aliases: ["chef boyardee ravioli", "canned beef ravioli", "chef boyardee beef ravioli"],
            servingLabel: "1 cup (244 g)",
            calories: 230, proteinG: 8, carbsG: 37, fatG: 6, fiberG: 3
        ),
        CommonFood(
            id: "jimmy-dean-breakfast-sandwich", name: "Jimmy Dean breakfast sandwich",
            // Jimmy Dean official
            aliases: ["jimmy dean breakfast sandwich", "sausage egg cheese croissant", "frozen breakfast sandwich"],
            servingLabel: "1 sandwich (128 g)",
            calories: 410, proteinG: 14, carbsG: 27, fatG: 27, fiberG: 1
        ),
        CommonFood(
            id: "cup-noodles-chicken", name: "Cup Noodles (chicken)",
            // Nissin official
            aliases: ["cup noodles chicken", "nissin cup noodles", "instant ramen cup", "cup of noodles"],
            servingLabel: "1 cup (64 g)",
            calories: 290, proteinG: 6, carbsG: 38, fatG: 12, fiberG: 2
        ),
        CommonFood(
            id: "chicken-parmesan", name: "Chicken parmesan",
            aliases: ["chicken parmesan", "chicken parm", "chicken parmigiana"],
            servingLabel: "1 serving (250 g)",
            calories: 430, proteinG: 36, carbsG: 24, fatG: 21, fiberG: 3
        ),
        CommonFood(
            id: "eggplant-parmesan", name: "Eggplant parmesan",
            aliases: ["eggplant parmesan", "eggplant parm", "melanzane parmigiana"],
            servingLabel: "1 serving (250 g)",
            calories: 350, proteinG: 15, carbsG: 28, fatG: 20, fiberG: 6
        ),
        CommonFood(
            id: "chicken-satay", name: "Chicken satay",
            aliases: ["chicken satay", "satay skewers", "grilled chicken skewers peanut"],
            servingLabel: "4 skewers (140 g)",
            calories: 280, proteinG: 30, carbsG: 8, fatG: 14, fiberG: 1
        ),
        CommonFood(
            id: "pad-see-ew", name: "Pad see ew",
            aliases: ["thai stir fried wide noodles", "see ew noodles"],
            servingLabel: "1 plate (400 g)",
            calories: 620, proteinG: 24, carbsG: 78, fatG: 24, fiberG: 4
        ),
        CommonFood(
            id: "larb", name: "Larb",
            aliases: ["larb", "laab", "thai minced meat salad", "larb gai"],
            servingLabel: "1 serving (200 g)",
            calories: 300, proteinG: 28, carbsG: 12, fatG: 15, fiberG: 2
        ),
        CommonFood(
            id: "nasi-goreng", name: "Nasi goreng",
            aliases: ["nasi goreng", "indonesian fried rice"],
            servingLabel: "1 plate (350 g)",
            calories: 540, proteinG: 18, carbsG: 72, fatG: 20, fiberG: 4
        ),
        CommonFood(
            id: "chicken-momos", name: "Chicken momos",
            aliases: ["nepali dumplings", "steamed momo", "chicken momos"],
            servingLabel: "6 pieces (180 g)",
            calories: 300, proteinG: 15, carbsG: 36, fatG: 11, fiberG: 2
        ),
        CommonFood(
            id: "vada-pav", name: "Vada pav",
            aliases: ["vada pav", "mumbai potato burger", "batata vada bun"],
            servingLabel: "1 piece (130 g)",
            calories: 290, proteinG: 7, carbsG: 42, fatG: 11, fiberG: 4
        ),
        CommonFood(
            id: "koshari", name: "Koshari",
            aliases: ["koshari", "koshary", "egyptian lentil rice pasta"],
            servingLabel: "1 bowl (400 g)",
            calories: 520, proteinG: 17, carbsG: 92, fatG: 10, fiberG: 11
        ),
        CommonFood(
            id: "poutine", name: "Poutine",
            aliases: ["poutine", "fries gravy cheese curds"],
            servingLabel: "1 serving (300 g)",
            calories: 740, proteinG: 18, carbsG: 74, fatG: 42, fiberG: 6
        ),
        CommonFood(
            id: "fish-and-chips", name: "Fish and chips",
            aliases: ["fish and chips", "battered fish and chips", "fish n chips"],
            servingLabel: "1 serving (340 g)",
            calories: 840, proteinG: 34, carbsG: 78, fatG: 44, fiberG: 6
        ),
        CommonFood(
            id: "pork-schnitzel", name: "Pork schnitzel",
            aliases: ["pork schnitzel"],
            servingLabel: "1 cutlet (170 g)",
            calories: 420, proteinG: 30, carbsG: 18, fatG: 25, fiberG: 1
        ),
        CommonFood(
            id: "deviled-eggs", name: "Deviled eggs",
            aliases: ["deviled eggs", "stuffed eggs"],
            servingLabel: "2 halves (60 g)",
            calories: 120, proteinG: 6, carbsG: 1, fatG: 10, fiberG: 0
        ),
        CommonFood(
            id: "fried-calamari", name: "Fried calamari",
            aliases: ["fried calamari", "squid rings appetizer"],
            servingLabel: "1 serving (140 g)",
            calories: 340, proteinG: 18, carbsG: 30, fatG: 16, fiberG: 1
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
        // — Frito-Lay branded chips — https://www.fritolay.com/products
        CommonFood(
            id: "cheetos-crunchy", name: "Cheetos Crunchy",
            aliases: ["cheetos", "cheetos crunchy", "crunchy cheetos"],
            servingLabel: "1 oz (28 g, ~21 pieces)",
            calories: 160, proteinG: 2, carbsG: 15, fatG: 10, fiberG: 0
        ),
        CommonFood(
            id: "cheetos-puffs", name: "Cheetos Puffs",
            aliases: ["cheetos puffs", "puffs cheetos"],
            servingLabel: "1 oz (28 g, ~13 pieces)",
            calories: 150, proteinG: 2, carbsG: 15, fatG: 9, fiberG: 0
        ),
        CommonFood(
            id: "lays-classic", name: "Lays Classic",
            aliases: ["lays", "lays classic", "lay's", "lays potato chips"],
            servingLabel: "1 oz (28 g, ~15 chips)",
            calories: 160, proteinG: 2, carbsG: 15, fatG: 10, fiberG: 1
        ),
        CommonFood(
            id: "lays-sour-cream", name: "Lays Sour Cream & Onion",
            aliases: ["lays sour cream", "sour cream and onion chips", "sour cream onion chips"],
            servingLabel: "1 oz (28 g, ~15 chips)",
            calories: 160, proteinG: 2, carbsG: 15, fatG: 10, fiberG: 1
        ),
        CommonFood(
            id: "doritos-nacho", name: "Doritos Nacho Cheese",
            aliases: ["doritos", "doritos nacho cheese", "nacho cheese doritos"],
            servingLabel: "1 oz (28 g, ~12 chips)",
            calories: 140, proteinG: 2, carbsG: 18, fatG: 7, fiberG: 1
        ),
        CommonFood(
            id: "sunchips-original", name: "Sun Chips Original",
            aliases: ["sun chips", "sunchips", "sunchips original"],
            servingLabel: "1 oz (28 g, ~14 chips)",
            calories: 140, proteinG: 2, carbsG: 19, fatG: 6, fiberG: 2
        ),
        CommonFood(
            id: "fritos-original", name: "Fritos Original",
            aliases: ["fritos", "fritos original", "corn chips fritos"],
            servingLabel: "1 oz (28 g, ~32 pieces)",
            calories: 160, proteinG: 2, carbsG: 15, fatG: 10, fiberG: 1
        ),
        // — Pringles — https://www.pringles.com/us (values from official US label)
        CommonFood(
            id: "pringles-original", name: "Pringles Original",
            aliases: ["pringles", "pringles original"],
            servingLabel: "15 crisps (28 g)",
            calories: 150, proteinG: 1, carbsG: 15, fatG: 9, fiberG: 1
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
        // — Branded candy — brand-official nutrition labels
        CommonFood(
            id: "starburst", name: "Starburst",
            // Mars official: starburst.com — 8 pieces (41 g)
            aliases: ["starburst", "starburst candy", "starburst original", "starburst fruit chews"],
            servingLabel: "8 pieces (41 g)",
            calories: 160, proteinG: 0, carbsG: 33, fatG: 3, fiberG: 0
        ),
        CommonFood(
            id: "skittles", name: "Skittles",
            // Mars/Wrigley official: skittles.com — USDA FDC #555742 (51 g single-serve)
            aliases: ["skittles", "skittles original", "fruit skittles", "skittles candy"],
            servingLabel: "1 pack (51 g)",
            calories: 200, proteinG: 0, carbsG: 44, fatG: 2, fiberG: 0
        ),
        CommonFood(
            id: "mnms-milk-chocolate", name: "M&Ms",
            // Mars official: mms.com — 1.69 oz standard bag (48 g)
            aliases: ["m&ms", "m&m's", "mms", "milk chocolate m&ms", "peanut m&ms", "chocolate candy m&ms"],
            servingLabel: "1 bag (48 g)",
            calories: 240, proteinG: 2, carbsG: 34, fatG: 10, fiberG: 1
        ),
        CommonFood(
            id: "reeses-pbc", name: "Reese's Peanut Butter Cups",
            // Hershey's official — 1 package, 2 cups (42 g)
            aliases: ["reeses", "reese's", "peanut butter cups", "reeses peanut butter cups", "reese's cups"],
            servingLabel: "2 cups (42 g)",
            calories: 220, proteinG: 5, carbsG: 22, fatG: 13, fiberG: 1
        ),
        CommonFood(
            id: "snickers", name: "Snickers",
            // Mars official: snickers.com — 1 bar (52.7 g)
            aliases: ["snickers", "snickers bar", "snickers candy bar"],
            servingLabel: "1 bar (52.7 g)",
            calories: 250, proteinG: 4, carbsG: 33, fatG: 12, fiberG: 1
        ),
        CommonFood(
            id: "kit-kat", name: "Kit Kat",
            // Hershey's official — 3 pieces / 2 wafer bars (42 g)
            aliases: ["kit kat", "kitkat", "kit kat bar", "wafer chocolate bar"],
            servingLabel: "1 package, 3 pieces (42 g)",
            calories: 210, proteinG: 3, carbsG: 27, fatG: 11, fiberG: 1
        ),
        CommonFood(
            id: "twix", name: "Twix",
            // Mars official: twix.com — 1 package, 2 bars (50 g)
            aliases: ["twix", "twix bar", "caramel cookie bar"],
            servingLabel: "2 bars (50 g)",
            calories: 250, proteinG: 2, carbsG: 34, fatG: 12, fiberG: 0
        ),
        CommonFood(
            id: "gummy-bears", name: "Gummy bears",
            // Haribo official: haribo.com — 17 pieces (51 g)
            aliases: ["gummy bears", "gummies", "gummy candy", "haribo", "haribo gold bears"],
            servingLabel: "17 pieces (51 g)",
            calories: 160, proteinG: 3, carbsG: 38, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "swedish-fish", name: "Swedish Fish",
            // Mondelez official — 19 pieces (40 g)
            aliases: ["swedish fish", "gummy fish", "swedish candy"],
            servingLabel: "19 pieces (40 g)",
            calories: 140, proteinG: 0, carbsG: 34, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "sour-patch-kids", name: "Sour Patch Kids",
            // Mondelez official — 16 pieces (42 g)
            aliases: ["sour patch kids", "sour patch", "sour gummies"],
            servingLabel: "16 pieces (42 g)",
            calories: 150, proteinG: 0, carbsG: 36, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "nerds", name: "Nerds",
            // Ferrara Candy official — 1 box / 46 g serving
            aliases: ["nerds", "nerds candy", "nerds rope", "nerds clusters"],
            servingLabel: "1 small box (46 g)",
            calories: 180, proteinG: 0, carbsG: 46, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "airheads", name: "Airheads",
            // Perfetti Van Melle official — 2 bars (30 g)
            aliases: ["airheads", "air heads", "airheads candy"],
            servingLabel: "2 bars (30 g)",
            calories: 110, proteinG: 0, carbsG: 25, fatG: 2, fiberG: 0
        ),
        CommonFood(
            id: "rice-krispie-treat", name: "Rice Krispie treat",
            // Kellogg's official — 1 original square (22 g)
            aliases: ["rice krispie treat", "rice crispy treat", "rice crispy square", "rice krispie square"],
            servingLabel: "1 treat (22 g)",
            calories: 90, proteinG: 1, carbsG: 17, fatG: 2, fiberG: 0
        ),
        CommonFood(
            id: "pop-tarts", name: "Pop-Tarts",
            // Kellogg's official — 1 pastry (52 g), frosted strawberry
            aliases: ["pop tarts", "pop-tarts", "toaster pastry"],
            servingLabel: "1 pastry (52 g)",
            calories: 200, proteinG: 2, carbsG: 37, fatG: 5, fiberG: 1
        ),
        CommonFood(
            id: "fruit-gummies", name: "Fruit snacks",
            // Welch's official — 1 pouch (25 g)
            aliases: ["fruit snacks", "fruit gummies", "welchs fruit snacks", "motts fruit snacks"],
            servingLabel: "1 pouch (25 g)",
            calories: 80, proteinG: 1, carbsG: 19, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "junior-mints", name: "Junior Mints",
            // Tootsie Roll official — 1 box (53 g)
            aliases: ["junior mints", "peppermint patty", "york peppermint pattie"],
            servingLabel: "1 box / 16 pieces (53 g)",
            calories: 190, proteinG: 1, carbsG: 40, fatG: 4, fiberG: 1
        ),
        CommonFood(
            id: "rice-crackers", name: "Rice crackers",
            // USDA FDC #172879
            aliases: ["rice crackers", "rice cracker", "japanese rice crackers", "sembei", "senbei"],
            servingLabel: "10 crackers (30 g)",
            calories: 120, proteinG: 2, carbsG: 25, fatG: 1, fiberG: 0
        ),
        CommonFood(
            id: "wasabi-peas", name: "Wasabi peas",
            aliases: ["wasabi peas", "hot peas", "spicy peas"],
            servingLabel: "1 oz (28 g)",
            calories: 130, proteinG: 4, carbsG: 17, fatG: 5, fiberG: 2
        ),
        CommonFood(
            id: "pork-rinds", name: "Pork rinds",
            // USDA FDC #168270
            aliases: ["pork rinds", "pork skins", "chicharrones", "chicharron"],
            servingLabel: "1 oz (28 g)",
            calories: 153, proteinG: 17, carbsG: 0, fatG: 9, fiberG: 0
        ),
        CommonFood(
            id: "slim-jim", name: "Beef stick",
            // Generic: Slim Jim / Jack Links-style beef stick
            aliases: ["beef stick", "slim jim", "meat stick", "jerky stick"],
            servingLabel: "1 stick (28 g)",
            calories: 110, proteinG: 6, carbsG: 2, fatG: 9, fiberG: 0
        ),
        CommonFood(
            id: "edamame-chips", name: "Edamame chips",
            aliases: ["edamame chips", "soy crisps", "edamame crisps"],
            servingLabel: "1 oz (28 g)",
            calories: 130, proteinG: 7, carbsG: 12, fatG: 6, fiberG: 4
        ),
        CommonFood(
            id: "fruit-roll-up", name: "Fruit Roll-Up",
            // General Mills official
            aliases: ["fruit roll up", "fruit roll-up", "fruit leather", "fruit by the foot"],
            servingLabel: "1 roll (14 g)",
            calories: 50, proteinG: 0, carbsG: 12, fatG: 1, fiberG: 0
        ),

        // — Crackers —
        CommonFood(
            id: "goldfish-crackers", name: "Goldfish crackers",
            // Pepperidge Farm official
            aliases: ["goldfish", "goldfish crackers", "pepperidge farm goldfish", "cheddar goldfish"],
            servingLabel: "55 pieces (30 g)",
            calories: 140, proteinG: 3, carbsG: 20, fatG: 5, fiberG: 1
        ),
        CommonFood(
            id: "ritz-crackers", name: "Ritz crackers",
            // Nabisco official
            aliases: ["ritz", "ritz crackers", "ritz cracker"],
            servingLabel: "5 crackers (16 g)",
            calories: 80, proteinG: 1, carbsG: 10, fatG: 4, fiberG: 0
        ),
        CommonFood(
            id: "triscuits", name: "Triscuits",
            aliases: ["triscuits", "triscuit", "whole wheat crackers triscuit"],
            servingLabel: "6 crackers (28 g)",
            calories: 120, proteinG: 3, carbsG: 20, fatG: 3, fiberG: 3
        ),
        CommonFood(
            id: "wheat-thins", name: "Wheat Thins",
            // Nabisco official
            aliases: ["wheat thins", "wheat thin crackers"],
            servingLabel: "16 crackers (29 g)",
            calories: 130, proteinG: 2, carbsG: 21, fatG: 5, fiberG: 1
        ),
        CommonFood(
            id: "saltine-crackers", name: "Saltine crackers",
            // USDA FDC #172023
            aliases: ["saltines", "saltine crackers", "saltine", "soda crackers", "premium saltines"],
            servingLabel: "5 crackers (14 g)",
            calories: 60, proteinG: 1, carbsG: 11, fatG: 1, fiberG: 0
        ),
        CommonFood(
            id: "graham-crackers", name: "Graham crackers",
            // USDA FDC #172066
            aliases: ["graham crackers", "graham cracker", "honey graham crackers"],
            servingLabel: "2 full sheets / 8 squares (28 g)",
            calories: 130, proteinG: 2, carbsG: 22, fatG: 3, fiberG: 1
        ),
        CommonFood(
            id: "animal-crackers", name: "Animal crackers",
            // Barnum's official
            aliases: ["animal crackers", "animal cookies", "barnum's animal crackers"],
            servingLabel: "15 crackers (30 g)",
            calories: 120, proteinG: 2, carbsG: 22, fatG: 3, fiberG: 0
        ),

        // — Cookies —
        CommonFood(
            id: "oreo-cookies", name: "Oreo cookies",
            // Nabisco official
            aliases: ["oreos", "oreo", "oreo cookie", "oreo cookies", "double stuf oreos"],
            servingLabel: "3 cookies (34 g)",
            calories: 160, proteinG: 1, carbsG: 25, fatG: 7, fiberG: 1
        ),
        CommonFood(
            id: "chips-ahoy", name: "Chips Ahoy! cookies",
            // Nabisco official
            aliases: ["chips ahoy", "chips ahoy cookies", "chocolate chip cookies chips ahoy"],
            servingLabel: "3 cookies (33 g)",
            calories: 160, proteinG: 2, carbsG: 21, fatG: 8, fiberG: 1
        ),
        CommonFood(
            id: "nutter-butter", name: "Nutter Butter cookies",
            // Nabisco official
            aliases: ["nutter butter", "nutter butters", "peanut butter cookie nutter butter"],
            servingLabel: "2 cookies (28 g)",
            calories: 130, proteinG: 3, carbsG: 19, fatG: 6, fiberG: 1
        ),
        CommonFood(
            id: "fig-newtons", name: "Fig Newtons",
            // Nabisco official
            aliases: ["fig newtons", "fig newton", "newtons figs"],
            servingLabel: "2 cookies (31 g)",
            calories: 110, proteinG: 1, carbsG: 22, fatG: 2, fiberG: 1
        ),
        CommonFood(
            id: "nilla-wafers", name: "Nilla Wafers",
            // Nabisco official
            aliases: ["nilla wafers", "nilla wafer", "vanilla wafers", "vanilla cookies"],
            servingLabel: "8 wafers (30 g)",
            calories: 140, proteinG: 1, carbsG: 21, fatG: 6, fiberG: 0
        ),

        // — Protein & granola bars —
        CommonFood(
            id: "clif-bar", name: "Clif Bar",
            // Clif official (Chocolate Chip)
            aliases: ["clif bar", "cliff bar", "clif energy bar"],
            servingLabel: "1 bar (68 g)",
            calories: 250, proteinG: 9, carbsG: 44, fatG: 6, fiberG: 5
        ),
        CommonFood(
            id: "kind-bar", name: "Kind Bar",
            // Kind official (Dark Chocolate Nuts & Sea Salt)
            aliases: ["kind bar", "kind snack bar", "kind nut bar"],
            servingLabel: "1 bar (40 g)",
            calories: 200, proteinG: 6, carbsG: 17, fatG: 15, fiberG: 7
        ),
        CommonFood(
            id: "quest-bar", name: "Quest Bar",
            // Quest official (Chocolate Chip Cookie Dough)
            aliases: ["quest bar", "quest protein bar", "quest"],
            servingLabel: "1 bar (60 g)",
            calories: 190, proteinG: 21, carbsG: 21, fatG: 7, fiberG: 14
        ),
        CommonFood(
            id: "rxbar", name: "RXBAR",
            // RXBAR official (Chocolate Sea Salt)
            aliases: ["rxbar", "rx bar", "rx protein bar"],
            servingLabel: "1 bar (52 g)",
            calories: 210, proteinG: 12, carbsG: 23, fatG: 9, fiberG: 5
        ),
        CommonFood(
            id: "larabar", name: "Larabar",
            // Larabar official (Apple Pie)
            aliases: ["larabar", "lara bar", "larabar fruit bar"],
            servingLabel: "1 bar (45 g)",
            calories: 190, proteinG: 4, carbsG: 26, fatG: 10, fiberG: 4
        ),
        CommonFood(
            id: "nature-valley-bar", name: "Nature Valley granola bar",
            // General Mills official (Oats & Honey, 2 bars)
            aliases: ["nature valley", "nature valley granola bar", "nature valley bar", "granola bar nature valley"],
            servingLabel: "2 bars (42 g)",
            calories: 190, proteinG: 4, carbsG: 29, fatG: 7, fiberG: 2
        ),
        CommonFood(
            id: "nutri-grain-bar", name: "Nutri-Grain bar",
            // Kellogg's official (Strawberry)
            aliases: ["nutri-grain", "nutri grain bar", "nutrigrain bar", "kelloggs nutri-grain"],
            servingLabel: "1 bar (37 g)",
            calories: 120, proteinG: 2, carbsG: 24, fatG: 3, fiberG: 1
        ),

        // — Packaged house staples —
        CommonFood(
            id: "kraft-mac-cheese", name: "Kraft mac & cheese",
            // Kraft official (box, prepared with butter/milk)
            aliases: ["kraft mac and cheese", "kraft mac & cheese", "mac and cheese box", "boxed mac and cheese", "blue box mac and cheese"],
            servingLabel: "1 cup prepared (about ¼ box)",
            calories: 350, proteinG: 10, carbsG: 47, fatG: 13, fiberG: 2
        ),
        CommonFood(
            id: "hot-pocket", name: "Hot Pocket",
            // Nestlé official (Ham & Cheese, 1 pocket 128 g)
            aliases: ["hot pocket", "hot pockets", "hot pocket ham and cheese", "ham and cheese hot pocket"],
            servingLabel: "1 pocket (128 g)",
            calories: 310, proteinG: 13, carbsG: 38, fatG: 11, fiberG: 1
        ),
        CommonFood(
            id: "frozen-burrito", name: "Frozen burrito",
            // Amy's/generic bean & cheese frozen burrito
            aliases: ["frozen burrito", "bean and cheese burrito frozen", "microwave burrito", "el monterey burrito"],
            servingLabel: "1 burrito (142 g)",
            calories: 330, proteinG: 11, carbsG: 52, fatG: 9, fiberG: 5
        ),
        CommonFood(
            id: "microwave-popcorn", name: "Microwave popcorn",
            // Orville Redenbacher's Classic butter (per 3.5 cup popped)
            aliases: ["microwave popcorn", "popcorn bag", "orville popcorn", "act ii popcorn", "jiffy pop"],
            servingLabel: "3½ cups popped (30 g)",
            calories: 150, proteinG: 3, carbsG: 15, fatG: 9, fiberG: 3
        ),
        CommonFood(
            id: "hard-boiled-egg", name: "Hard boiled egg",
            // USDA FDC #173423
            aliases: ["hard boiled egg", "hardboiled egg", "hard-boiled egg", "boiled egg"],
            servingLabel: "1 large egg (50 g)",
            calories: 78, proteinG: 6, carbsG: 1, fatG: 5, fiberG: 0
        ),
        CommonFood(
            id: "oblea-con-arequipe", name: "Oblea con Arequipe",
            aliases: ["oblea con arequipe", "colombian wafer with dulce de leche", "obleas arequipe"],
            servingLabel: "1 filled oblea (75 g)",
            calories: 250, proteinG: 4, carbsG: 45, fatG: 6, fiberG: 1
        ),
        CommonFood(
            id: "arequipe-dulce-de-leche", name: "Arequipe (Dulce de Leche)",
            aliases: ["arequipe colombiano", "dulce de leche spread", "manjar de leche"],
            servingLabel: "1 tbsp (19 g)",
            calories: 60, proteinG: 1, carbsG: 11, fatG: 1, fiberG: 0
        ),
        CommonFood(
            id: "panelitas-de-leche", name: "Panelitas de Leche",
            aliases: ["panelitas de leche", "colombian milk fudge", "panelitas colombianas"],
            servingLabel: "1 piece (40 g)",
            calories: 160, proteinG: 2, carbsG: 30, fatG: 4, fiberG: 0
        ),
        CommonFood(
            id: "cocada-colombiana", name: "Cocada",
            aliases: ["cocada colombiana", "coconut candy cocada", "cocadas de coco"],
            servingLabel: "1 piece (35 g)",
            calories: 140, proteinG: 1, carbsG: 19, fatG: 7, fiberG: 2
        ),
        CommonFood(
            id: "merengon-colombiano", name: "Merengón",
            aliases: ["merengon colombiano", "colombian meringue dessert", "merengon de fresas"],
            servingLabel: "1 serving (150 g)",
            calories: 280, proteinG: 4, carbsG: 55, fatG: 9, fiberG: 1
        ),
        CommonFood(
            id: "postre-de-natas", name: "Postre de Natas",
            aliases: ["postre de natas", "colombian milk cream dessert", "natas colombianas"],
            servingLabel: "1 serving (120 g)",
            calories: 280, proteinG: 5, carbsG: 38, fatG: 12, fiberG: 0
        ),
        CommonFood(
            id: "manjar-blanco-colombiano", name: "Manjar Blanco",
            aliases: ["manjar blanco colombiano", "colombian sweet milk custard", "manjarblanco"],
            servingLabel: "¼ cup (60 g)",
            calories: 200, proteinG: 3, carbsG: 35, fatG: 5, fiberG: 0
        ),
        CommonFood(
            id: "brevas-con-arequipe", name: "Brevas con Arequipe",
            aliases: ["brevas con arequipe", "figs with dulce de leche", "brevas colombianas"],
            servingLabel: "2 stuffed figs (110 g)",
            calories: 190, proteinG: 2, carbsG: 42, fatG: 2, fiberG: 3
        ),
        CommonFood(
            id: "bocadillo-guava-paste", name: "Bocadillo (Guava Paste)",
            aliases: ["bocadillo de guayaba", "colombian guava paste", "bocadillo veleño"],
            servingLabel: "1 block (28 g)",
            calories: 85, proteinG: 0, carbsG: 21, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "achira-biscuit", name: "Achira Biscuit",
            aliases: ["achiras colombianas", "colombian arrowroot biscuit", "bizcocho de achira"],
            servingLabel: "3 biscuits (30 g)",
            calories: 130, proteinG: 3, carbsG: 15, fatG: 6, fiberG: 0
        ),
        CommonFood(
            id: "dedito-de-queso", name: "Dedito de Queso",
            aliases: ["dedito de queso", "colombian cheese stick pastry", "deditos de queso"],
            servingLabel: "1 piece (45 g)",
            calories: 150, proteinG: 5, carbsG: 14, fatG: 8, fiberG: 0
        ),
        CommonFood(
            id: "turon", name: "Turon",
            aliases: ["banana spring roll", "saba banana lumpia", "caramelized banana roll", "filipino banana fritter"],
            servingLabel: "1 piece (95 g)",
            calories: 210, proteinG: 2, carbsG: 40, fatG: 5, fiberG: 2
        ),
        CommonFood(
            id: "bibingka", name: "Bibingka",
            aliases: ["filipino rice cake", "baked coconut rice cake", "bibingka galapong", "filipino christmas cake"],
            servingLabel: "1 slice (110 g)",
            calories: 250, proteinG: 6, carbsG: 40, fatG: 8, fiberG: 2
        ),
        CommonFood(
            id: "puto", name: "Puto",
            aliases: ["steamed rice cake", "filipino puto", "puti puto", "white rice muffin"],
            servingLabel: "3 pieces (90 g)",
            calories: 150, proteinG: 3, carbsG: 30, fatG: 2, fiberG: 1
        ),
        CommonFood(
            id: "kutsinta", name: "Kutsinta",
            aliases: ["brown rice cake", "cuchinta", "filipino jelly cake", "steamed kutsinta"],
            servingLabel: "3 pieces (75 g)",
            calories: 120, proteinG: 1, carbsG: 28, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "sapin-sapin", name: "Sapin-sapin",
            aliases: ["layered rice cake", "glutinous layered dessert", "filipino sapin sapin", "tri color rice cake"],
            servingLabel: "1 slice (100 g)",
            calories: 200, proteinG: 2, carbsG: 38, fatG: 4, fiberG: 1
        ),
        CommonFood(
            id: "ube-halaya", name: "Ube halaya",
            aliases: ["purple yam jam", "ube jam", "filipino ube halaya", "mashed purple yam"],
            servingLabel: "½ cup (130 g)",
            calories: 250, proteinG: 3, carbsG: 42, fatG: 8, fiberG: 3
        ),
        CommonFood(
            id: "leche-flan", name: "Leche flan",
            aliases: ["filipino creme caramel", "steamed egg custard", "leche flan slice", "caramel custard"],
            servingLabel: "1 slice (110 g)",
            calories: 300, proteinG: 7, carbsG: 40, fatG: 9, fiberG: 0
        ),
        CommonFood(
            id: "buko-pie", name: "Buko pie",
            aliases: ["young coconut pie", "filipino coconut pie", "laguna buko pie", "fresh coconut tart"],
            servingLabel: "1 slice (130 g)",
            calories: 340, proteinG: 4, carbsG: 45, fatG: 16, fiberG: 2
        ),
        CommonFood(
            id: "biko", name: "Biko",
            aliases: ["sweet sticky rice cake", "filipino biko", "coconut caramel rice", "glutinous rice cake biko"],
            servingLabel: "1 slice (120 g)",
            calories: 290, proteinG: 3, carbsG: 50, fatG: 8, fiberG: 1
        ),
        CommonFood(
            id: "palitaw", name: "Palitaw",
            aliases: ["filipino palitaw", "sticky rice patty", "sweet rice flat cake", "coconut sugar rice patty"],
            servingLabel: "3 pieces (90 g)",
            calories: 180, proteinG: 2, carbsG: 38, fatG: 2, fiberG: 1
        ),
        CommonFood(
            id: "maja-blanca", name: "Maja blanca",
            aliases: ["coconut pudding filipino", "maja blanca coconut", "filipino corn pudding", "white coconut pudding"],
            servingLabel: "1 slice (100 g)",
            calories: 170, proteinG: 2, carbsG: 32, fatG: 4, fiberG: 1
        ),
        CommonFood(
            id: "cassava-cake", name: "Cassava cake",
            aliases: ["filipino cassava cake", "grated cassava cake", "balinghoy cake", "cassava custard cake"],
            servingLabel: "1 slice (120 g)",
            calories: 290, proteinG: 4, carbsG: 45, fatG: 10, fiberG: 2
        ),
        CommonFood(
            id: "mango-float", name: "Mango float",
            aliases: ["crema de fruta mango", "mango graham cake", "filipino mango icebox cake", "mango refrigerator cake"],
            servingLabel: "1 slice (130 g)",
            calories: 340, proteinG: 4, carbsG: 42, fatG: 18, fiberG: 2
        ),
        CommonFood(
            id: "hopia", name: "Hopia",
            aliases: ["filipino mung bean pastry", "hopia mongo", "hopia ube", "filipino bean cake pastry"],
            servingLabel: "1 piece (55 g)",
            calories: 190, proteinG: 3, carbsG: 30, fatG: 6, fiberG: 2
        ),
        CommonFood(
            id: "polvoron", name: "Polvoron",
            aliases: ["filipino polvoron", "powdered milk candy", "toasted flour candy", "goldilocks polvoron"],
            servingLabel: "1 piece (25 g)",
            calories: 110, proteinG: 2, carbsG: 14, fatG: 5, fiberG: 0
        ),
        CommonFood(
            id: "taho", name: "Taho",
            aliases: ["filipino silken tofu dessert", "taho with sago", "arnibal tofu", "sweet soybean pudding"],
            servingLabel: "1 cup (300 g)",
            calories: 220, proteinG: 6, carbsG: 42, fatG: 3, fiberG: 1
        ),
        CommonFood(
            id: "sorbetes", name: "Sorbetes",
            aliases: ["dirty ice cream", "filipino sorbetes", "coconut milk ice cream", "ube sorbetes scoop"],
            servingLabel: "1 scoop (70 g)",
            calories: 140, proteinG: 2, carbsG: 22, fatG: 5, fiberG: 0
        ),
        CommonFood(
            id: "red-ribbon-mango-cake", name: "Red Ribbon mango cake slice",
            // Red Ribbon official
            aliases: ["red ribbon mango cake", "filipino mango cake slice", "red ribbon dewberry mango", "mango chiffon cake slice"],
            servingLabel: "1 slice (115 g)",
            calories: 330, proteinG: 4, carbsG: 42, fatG: 16, fiberG: 1
        ),
        CommonFood(
            id: "goldilocks-ube-cake", name: "Goldilocks ube cake slice",
            // Goldilocks official
            aliases: ["goldilocks ube cake", "filipino ube chiffon cake", "purple yam cake slice goldilocks", "ube macapuno cake slice"],
            servingLabel: "1 slice (115 g)",
            calories: 340, proteinG: 4, carbsG: 48, fatG: 15, fiberG: 1
        ),
        CommonFood(
            id: "totinos-pizza-rolls", name: "Totino's pizza rolls (6)",
            // Totino's official
            aliases: ["totinos pizza rolls", "pepperoni pizza rolls", "frozen pizza rolls"],
            servingLabel: "6 rolls (85 g)",
            calories: 220, proteinG: 5, carbsG: 24, fatG: 11, fiberG: 1
        ),
        CommonFood(
            id: "tater-tots-frozen", name: "Tater tots (frozen)",
            // Ore-Ida official
            aliases: ["tater tots", "frozen tater tots", "potato tots", "tatertots"],
            servingLabel: "9 pieces (86 g)",
            calories: 160, proteinG: 2, carbsG: 20, fatG: 8, fiberG: 2
        ),
        CommonFood(
            id: "uncrustables-pbj", name: "Uncrustables PB&J",
            // Smucker's official
            aliases: ["uncrustables pbj", "peanut butter jelly uncrustable", "smucker's uncrustable", "frozen pb and j sandwich"],
            servingLabel: "1 sandwich (58 g)",
            calories: 210, proteinG: 7, carbsG: 25, fatG: 9, fiberG: 2
        ),
        CommonFood(
            id: "toaster-strudel", name: "Toaster strudel",
            // Pillsbury official
            aliases: ["toaster strudel", "pillsbury toaster strudel", "strawberry toaster pastry"],
            servingLabel: "1 pastry (54 g)",
            calories: 190, proteinG: 3, carbsG: 26, fatG: 8, fiberG: 1
        ),
        CommonFood(
            id: "bagel-bites", name: "Bagel Bites (4)",
            // Bagel Bites official
            aliases: ["bagel bites", "mini pizza bagels", "cheese pepperoni bagel bites"],
            servingLabel: "4 pieces (88 g)",
            calories: 200, proteinG: 7, carbsG: 28, fatG: 6, fiberG: 2
        ),
        CommonFood(
            id: "mozzarella-sticks-frozen", name: "Mozzarella sticks (4)",
            // Farm Rich official
            aliases: ["mozzarella sticks", "frozen mozzarella sticks", "breaded cheese sticks", "mozz sticks"],
            servingLabel: "4 sticks (88 g)",
            calories: 280, proteinG: 10, carbsG: 26, fatG: 15, fiberG: 2
        ),
        CommonFood(
            id: "jello-pudding-cup", name: "Jell-O pudding cup",
            // Jell-O official
            aliases: ["jello pudding cup", "jell-o chocolate pudding", "snack pack pudding"],
            servingLabel: "1 cup (113 g)",
            calories: 120, proteinG: 1, carbsG: 22, fatG: 3, fiberG: 1
        ),
        CommonFood(
            id: "cheese-danish", name: "Cheese danish",
            aliases: ["cheese danish pastry", "cream cheese danish", "bakery cheese danish"],
            servingLabel: "1 pastry (91 g)",
            calories: 340, proteinG: 6, carbsG: 38, fatG: 18, fiberG: 1
        ),
        CommonFood(
            id: "cinnamon-roll-icing", name: "Cinnamon roll with icing",
            aliases: ["iced cinnamon roll", "cinnamon bun with frosting", "bakery cinnamon roll"],
            servingLabel: "1 large roll (113 g)",
            calories: 340, proteinG: 5, carbsG: 49, fatG: 14, fiberG: 1
        ),
        CommonFood(
            id: "bear-claw-pastry", name: "Bear claw pastry",
            aliases: ["almond bear claw", "bear claw danish", "bakery bear claw"],
            servingLabel: "1 pastry (99 g)",
            calories: 420, proteinG: 7, carbsG: 44, fatG: 24, fiberG: 2
        ),
        CommonFood(
            id: "chocolate-chip-muffin", name: "Chocolate chip muffin",
            aliases: ["choc chip muffin", "chocolate chip bakery muffin", "double chocolate muffin"],
            servingLabel: "1 large muffin (113 g)",
            calories: 440, proteinG: 6, carbsG: 58, fatG: 21, fiberG: 2
        ),
        CommonFood(
            id: "pumpkin-bread-slice", name: "Pumpkin bread slice",
            aliases: ["pumpkin loaf slice", "spiced pumpkin bread", "pumpkin quick bread"],
            servingLabel: "1 slice (80 g)",
            calories: 270, proteinG: 3, carbsG: 40, fatG: 11, fiberG: 1
        ),
        CommonFood(
            id: "takis-fuego", name: "Takis Fuego",
            aliases: ["takis", "takis fuego", "rolled tortilla chips", "hot chili lime chips"],
            servingLabel: "about 12 pieces (28 g)",
            calories: 140, proteinG: 2, carbsG: 16, fatG: 8, fiberG: 1
        ),
        CommonFood(
            id: "funyuns", name: "Funyuns",
            aliases: ["funyuns", "onion flavored rings"],
            servingLabel: "1 oz (28 g)",
            calories: 140, proteinG: 2, carbsG: 18, fatG: 7, fiberG: 1
        ),
        CommonFood(
            id: "chex-mix", name: "Chex Mix",
            aliases: ["chex mix", "savory party mix"],
            servingLabel: "about 2/3 cup (30 g)",
            calories: 130, proteinG: 3, carbsG: 21, fatG: 4, fiberG: 2
        ),
        CommonFood(
            id: "skinnypop-popcorn", name: "SkinnyPop popcorn",
            aliases: ["skinnypop", "skinny pop popcorn"],
            servingLabel: "about 3.75 cups (28 g)",
            calories: 150, proteinG: 2, carbsG: 15, fatG: 10, fiberG: 3
        ),
        CommonFood(
            id: "cheetos-flamin-hot", name: "Cheetos Flamin' Hot",
            aliases: ["flamin hot cheetos", "hot cheetos", "flamin hot crunchy"],
            servingLabel: "21 pieces (28 g)",
            calories: 160, proteinG: 2, carbsG: 15, fatG: 11, fiberG: 1
        ),
        CommonFood(
            id: "hershey-milk-chocolate-bar", name: "Hershey's Milk Chocolate bar",
            aliases: ["hershey bar", "hersheys milk chocolate", "milk chocolate bar full size"],
            servingLabel: "1 bar (43 g)",
            calories: 220, proteinG: 3, carbsG: 26, fatG: 13, fiberG: 1
        ),
        CommonFood(
            id: "milky-way-bar", name: "Milky Way bar",
            aliases: ["milky way", "milkyway bar", "caramel nougat chocolate bar"],
            servingLabel: "1 bar (52 g)",
            calories: 240, proteinG: 2, carbsG: 37, fatG: 9, fiberG: 1
        ),
        CommonFood(
            id: "butterfinger-bar", name: "Butterfinger bar",
            aliases: ["butterfinger", "crispy peanut butter bar"],
            servingLabel: "1 bar (60 g)",
            calories: 275, proteinG: 3, carbsG: 42, fatG: 11, fiberG: 1
        ),
        CommonFood(
            id: "almond-joy-bar", name: "Almond Joy bar",
            aliases: ["almond joy", "coconut almond chocolate bar"],
            servingLabel: "1 bar (45 g)",
            calories: 220, proteinG: 2, carbsG: 26, fatG: 13, fiberG: 2
        ),
        CommonFood(
            id: "twizzlers", name: "Twizzlers",
            aliases: ["twizzlers", "red licorice twists", "strawberry licorice"],
            servingLabel: "4 twists (45 g)",
            calories: 150, proteinG: 1, carbsG: 34, fatG: 1, fiberG: 0
        ),
        CommonFood(
            id: "reeses-pieces", name: "Reese's Pieces",
            aliases: ["reeses pieces", "peanut butter candy pieces"],
            servingLabel: "1 package (46 g)",
            calories: 230, proteinG: 6, carbsG: 28, fatG: 11, fiberG: 1
        ),
        CommonFood(
            id: "ferrero-rocher", name: "Ferrero Rocher",
            aliases: ["ferrero rocher", "hazelnut chocolate balls"],
            servingLabel: "3 pieces (37 g)",
            calories: 220, proteinG: 3, carbsG: 17, fatG: 16, fiberG: 1
        ),
        CommonFood(
            id: "soft-pretzel", name: "Soft pretzel",
            aliases: ["soft pretzel", "bavarian pretzel", "mall pretzel"],
            servingLabel: "1 large (115 g)",
            calories: 340, proteinG: 9, carbsG: 71, fatG: 2, fiberG: 3
        ),
        CommonFood(
            id: "baklava", name: "Baklava",
            aliases: ["baklava", "phyllo nut pastry", "walnut honey pastry"],
            servingLabel: "1 piece (78 g)",
            calories: 290, proteinG: 4, carbsG: 29, fatG: 18, fiberG: 2
        ),
        CommonFood(
            id: "macaron", name: "French macaron",
            aliases: ["macaron", "french macaron", "almond meringue cookie"],
            servingLabel: "1 cookie (20 g)",
            calories: 90, proteinG: 1, carbsG: 13, fatG: 4, fiberG: 0
        ),
        CommonFood(
            id: "turkey-jerky", name: "Turkey jerky",
            aliases: ["turkey jerky", "dried turkey strips"],
            servingLabel: "1 oz (28 g)",
            calories: 80, proteinG: 13, carbsG: 6, fatG: 1, fiberG: 0
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

        // — Shake Shack — https://www.shakeshack.com/nutrition (Feb 2024 published values)
        CommonFood(
            id: "ff-ss-shackburger", name: "ShackBurger",
            aliases: ["shackburger", "shack burger", "shake shack burger", "shakeshack burger", "shake shack"],
            servingLabel: "1 sandwich (196 g)",
            calories: 530, proteinG: 28, carbsG: 38, fatG: 29, fiberG: 1
        ),
        CommonFood(
            id: "ff-ss-smokeshack", name: "SmokeShack",
            aliases: ["smokeshack", "smoke shack", "shake shack smokeshack", "smokeshack burger"],
            servingLabel: "1 sandwich (221 g)",
            calories: 590, proteinG: 35, carbsG: 38, fatG: 32, fiberG: 1
        ),
        CommonFood(
            id: "ff-ss-double-shackburger", name: "Double ShackBurger",
            aliases: ["double shackburger", "double shack burger", "shakeshack double"],
            servingLabel: "1 sandwich (280 g)",
            calories: 810, proteinG: 50, carbsG: 42, fatG: 48, fiberG: 1
        ),
        CommonFood(
            id: "ff-ss-fries", name: "Shake Shack crinkle fries",
            aliases: ["shake shack fries", "crinkle cut fries", "shakeshack fries", "crinkle fries shake shack"],
            servingLabel: "Regular (240 g)",
            calories: 470, proteinG: 7, carbsG: 63, fatG: 21, fiberG: 4
        ),
        CommonFood(
            id: "ff-ss-shake-chocolate", name: "Shake Shack chocolate shake",
            aliases: ["shake shack shake", "shake shack chocolate shake", "shakeshack shake", "shack chocolate milkshake"],
            servingLabel: "Small (16 oz)",
            calories: 640, proteinG: 13, carbsG: 88, fatG: 29, fiberG: 1
        ),

        // — Chipotle — https://www.chipotle.com/nutrition-calculator (2024)
        // Bowl calorie estimates: protein + cilantro-lime rice + black beans + mild salsa; no sour cream/guac/cheese
        CommonFood(
            id: "ff-chipotle-chicken-bowl", name: "Chipotle chicken bowl",
            aliases: ["chipotle chicken bowl", "chipotle bowl chicken", "chipotle chicken rice bowl"],
            servingLabel: "1 bowl (chicken + rice + black beans + salsa, ~450 g)",
            calories: 580, proteinG: 44, carbsG: 67, fatG: 13, fiberG: 11
        ),
        CommonFood(
            id: "ff-chipotle-steak-bowl", name: "Chipotle steak bowl",
            aliases: ["chipotle steak bowl", "chipotle bowl steak"],
            servingLabel: "1 bowl (steak + rice + black beans + salsa, ~450 g)",
            calories: 570, proteinG: 38, carbsG: 67, fatG: 14, fiberG: 11
        ),
        CommonFood(
            id: "ff-chipotle-carnitas-bowl", name: "Chipotle carnitas bowl",
            aliases: ["chipotle carnitas bowl", "chipotle carnitas", "carnitas bowl chipotle"],
            servingLabel: "1 bowl (carnitas + rice + black beans + salsa, ~450 g)",
            calories: 600, proteinG: 37, carbsG: 67, fatG: 17, fiberG: 11
        ),
        CommonFood(
            id: "ff-chipotle-chicken-burrito", name: "Chipotle chicken burrito",
            aliases: ["chipotle burrito", "chipotle chicken burrito", "chipotle burrito chicken"],
            servingLabel: "1 burrito (chicken + rice + beans + sour cream + salsa + tortilla, ~500 g)",
            calories: 820, proteinG: 48, carbsG: 92, fatG: 27, fiberG: 12
        ),
        CommonFood(
            id: "ff-chipotle-tacos", name: "Chipotle tacos",
            aliases: ["chipotle tacos", "chipotle chicken tacos", "chipotle crispy tacos"],
            servingLabel: "3 crispy tacos (chicken + salsa + cheese, ~250 g)",
            calories: 470, proteinG: 30, carbsG: 42, fatG: 19, fiberG: 7
        ),
        CommonFood(
            id: "ff-chipotle-guacamole", name: "Chipotle guacamole",
            // Chipotle official nutrition: 3.5 oz side (99 g) = 230 cal
            aliases: ["chipotle guac", "chipotle guacamole", "guacamole chipotle"],
            servingLabel: "1 side (3.5 oz / 99 g)",
            calories: 230, proteinG: 2, carbsG: 8, fatG: 22, fiberG: 6
        ),
        CommonFood(
            id: "ff-chipotle-chips-guac", name: "Chipotle chips & guacamole",
            // Chipotle chips side (~85 g) + guac side (99 g)
            aliases: ["chipotle chips and guac", "chipotle chips guacamole", "chips and guac chipotle", "chipotle chips"],
            servingLabel: "Chips + guac side (~184 g)",
            calories: 770, proteinG: 4, carbsG: 80, fatG: 46, fiberG: 10
        ),

        // — Popeyes — https://www.popeyes.com/nutrition
        CommonFood(
            id: "ff-popeyes-chicken-sandwich", name: "Popeyes chicken sandwich",
            aliases: ["popeyes sandwich", "popeyes chicken sandwich", "popeyes spicy sandwich"],
            servingLabel: "1 sandwich (198 g)",
            calories: 700, proteinG: 28, carbsG: 55, fatG: 42, fiberG: 2
        ),
        CommonFood(
            id: "ff-popeyes-chicken-piece", name: "Popeyes fried chicken (1 piece)",
            aliases: ["popeyes chicken", "popeyes fried chicken", "popeyes breast", "popeyes thigh"],
            servingLabel: "1 breast (178 g)",
            calories: 480, proteinG: 38, carbsG: 24, fatG: 26, fiberG: 2
        ),

        // — KFC — https://www.kfc.com/nutrition
        CommonFood(
            id: "ff-kfc-original-chicken", name: "KFC Original Recipe chicken",
            aliases: ["kfc chicken", "kfc original recipe", "kentucky fried chicken", "kfc breast"],
            servingLabel: "1 breast (161 g)",
            calories: 390, proteinG: 39, carbsG: 11, fatG: 21, fiberG: 0
        ),

        // — Taco Bell — https://www.tacobell.com/nutrition-guide
        CommonFood(
            id: "ff-tb-crunchwrap", name: "Taco Bell Crunchwrap Supreme",
            aliases: ["crunchwrap", "crunchwrap supreme", "taco bell crunchwrap"],
            servingLabel: "1 wrap (265 g)",
            calories: 520, proteinG: 17, carbsG: 68, fatG: 19, fiberG: 5
        ),
        CommonFood(
            id: "ff-tb-chalupa", name: "Taco Bell Chalupa Supreme",
            aliases: ["chalupa", "chalupa supreme", "taco bell chalupa"],
            servingLabel: "1 chalupa (153 g)",
            calories: 340, proteinG: 14, carbsG: 37, fatG: 15, fiberG: 3
        ),
        CommonFood(
            id: "ff-tb-quesadilla", name: "Taco Bell Quesadilla",
            aliases: ["taco bell quesadilla", "tb quesadilla"],
            servingLabel: "1 quesadilla (183 g)",
            calories: 510, proteinG: 26, carbsG: 38, fatG: 27, fiberG: 3
        ),

        // — Five Guys — https://www.fiveguys.com/menu/nutrition-info
        CommonFood(
            id: "ff-five-guys-burger", name: "Five Guys cheeseburger",
            aliases: ["five guys burger", "five guys cheeseburger", "five guys", "fiveguys burger"],
            servingLabel: "1 burger (397 g)",
            calories: 840, proteinG: 50, carbsG: 40, fatG: 52, fiberG: 2
        ),
        CommonFood(
            id: "ff-five-guys-fries", name: "Five Guys fries",
            aliases: ["five guys fries", "five guys cajun fries", "fiveguys fries"],
            servingLabel: "Regular (411 g)",
            calories: 953, proteinG: 13, carbsG: 131, fatG: 41, fiberG: 11
        ),

        // — In-N-Out — https://www.in-n-out.com/menu/nutrition
        CommonFood(
            id: "ff-innout-double-double", name: "In-N-Out Double-Double",
            aliases: ["double double", "in-n-out double double", "in n out burger", "animal style"],
            servingLabel: "1 burger (330 g)",
            calories: 700, proteinG: 39, carbsG: 41, fatG: 39, fiberG: 3
        ),

        // — Subway — https://www.subway.com/en-us/menunutrition/menu
        CommonFood(
            id: "ff-subway-turkey-footlong", name: "Subway Turkey footlong",
            aliases: ["subway turkey", "subway footlong turkey", "subway turkey breast footlong"],
            servingLabel: "12\" on 9-grain wheat + veggies",
            calories: 560, proteinG: 36, carbsG: 86, fatG: 10, fiberG: 8
        ),
        CommonFood(
            id: "ff-subway-italian-bmt", name: "Subway Italian BMT footlong",
            aliases: ["subway italian bmt", "bmt subway", "subway bmt footlong"],
            servingLabel: "12\" on Italian bread",
            calories: 960, proteinG: 48, carbsG: 90, fatG: 44, fiberG: 6
        ),

        // — Starbucks — https://www.starbucks.com/menu
        CommonFood(
            id: "ff-sbux-frappuccino", name: "Starbucks Frappuccino",
            aliases: ["frappuccino", "starbucks frappuccino", "caramel frappuccino", "mocha frappuccino"],
            servingLabel: "Grande 16 oz",
            calories: 420, proteinG: 6, carbsG: 68, fatG: 16, fiberG: 0
        ),
        CommonFood(
            id: "ff-sbux-caramel-macchiato", name: "Caramel macchiato",
            aliases: ["caramel macchiato", "starbucks caramel macchiato", "iced caramel macchiato"],
            servingLabel: "Grande 16 oz with 2% milk",
            calories: 250, proteinG: 10, carbsG: 34, fatG: 7, fiberG: 0
        ),
        CommonFood(
            id: "ff-sbux-pumpkin-spice-latte", name: "Pumpkin Spice Latte",
            aliases: ["pumpkin spice latte", "psl", "starbucks psl", "pumpkin latte"],
            servingLabel: "Grande 16 oz with 2% milk",
            calories: 380, proteinG: 14, carbsG: 52, fatG: 13, fiberG: 0
        ),

        // — Domino's / Pizza — https://www.dominos.com/en/
        CommonFood(
            id: "ff-dominos-pepperoni-slice", name: "Pepperoni pizza slice",
            aliases: ["dominos pepperoni pizza", "pepperoni pizza slice", "domino's pizza", "pizza hut pepperoni"],
            servingLabel: "1 slice large hand-tossed (107 g)",
            calories: 300, proteinG: 13, carbsG: 34, fatG: 12, fiberG: 2
        ),

        // — Jollibee — https://www.jollibee.com/us/nutrition
        CommonFood(
            id: "ff-jollibee-chickenjoy", name: "Jollibee Chickenjoy",
            aliases: ["chickenjoy", "jollibee chicken", "jollibee chickenjoy"],
            servingLabel: "1 piece (thigh, 155 g)",
            calories: 370, proteinG: 28, carbsG: 16, fatG: 22, fiberG: 1
        ),

        // — Raising Cane's — https://raisingcanes.com/nutrition
        CommonFood(
            id: "ff-canes-box-combo", name: "Raising Cane's 3-finger box",
            aliases: ["raising canes", "canes chicken", "canes finger", "three finger combo canes"],
            servingLabel: "3 fingers + toast + coleslaw (250 g)",
            calories: 570, proteinG: 32, carbsG: 54, fatG: 22, fiberG: 2
        ),

        // — Panera Bread — https://www.panerabread.com/en-us/articles/nutrition.html
        CommonFood(
            id: "ff-panera-mac-cheese", name: "Panera mac & cheese",
            aliases: ["panera mac and cheese", "panera mac & cheese", "panera macaroni"],
            servingLabel: "Cup (240 g)",
            calories: 450, proteinG: 17, carbsG: 51, fatG: 19, fiberG: 2
        ),
        CommonFood(
            id: "ff-panera-broccoli-cheddar", name: "Panera broccoli cheddar soup",
            aliases: ["panera broccoli cheddar", "panera broccoli soup", "broccoli cheddar soup panera"],
            servingLabel: "Cup (240 ml)",
            calories: 360, proteinG: 13, carbsG: 29, fatG: 23, fiberG: 3
        ),
        CommonFood(
            id: "ff-panera-turkey-sandwich", name: "Panera turkey sandwich",
            // Panera Turkey Chipotle Avocado on white whole grain
            aliases: ["panera turkey sandwich", "panera turkey", "turkey sandwich panera"],
            servingLabel: "1 whole sandwich (295 g)",
            calories: 470, proteinG: 26, carbsG: 53, fatG: 16, fiberG: 5
        ),
        CommonFood(
            id: "ff-panera-caesar-salad", name: "Panera chicken caesar salad",
            aliases: ["panera caesar salad", "panera chicken caesar", "caesar salad panera"],
            servingLabel: "Full salad (421 g)",
            calories: 490, proteinG: 35, carbsG: 20, fatG: 31, fiberG: 4
        ),

        // — Arby's — https://www.arbys.com/menu/nutritional-information/
        CommonFood(
            id: "ff-arbys-beef-n-cheddar", name: "Arby's Beef 'n Cheddar",
            aliases: ["arbys beef n cheddar", "arby's beef n cheddar", "beef n cheddar arby's", "beefy cheddar arby"],
            servingLabel: "1 sandwich (198 g)",
            calories: 450, proteinG: 25, carbsG: 46, fatG: 20, fiberG: 2
        ),
        CommonFood(
            id: "ff-arbys-roast-beef", name: "Arby's Classic Roast Beef",
            aliases: ["arbys roast beef", "arby's roast beef", "roast beef arby's"],
            servingLabel: "1 sandwich (154 g)",
            calories: 360, proteinG: 23, carbsG: 36, fatG: 14, fiberG: 2
        ),
        CommonFood(
            id: "ff-arbys-curly-fries", name: "Arby's curly fries",
            aliases: ["arby's curly fries", "arbys curly fries", "curly fries arby"],
            servingLabel: "Medium (142 g)",
            calories: 550, proteinG: 7, carbsG: 71, fatG: 26, fiberG: 6
        ),

        // — Sonic Drive-In — https://www.sonicdrivein.com/menu/nutrition
        CommonFood(
            id: "ff-sonic-cheeseburger", name: "Sonic cheeseburger",
            aliases: ["sonic burger", "sonic cheeseburger", "sonic drive in burger"],
            servingLabel: "1 burger (254 g)",
            calories: 630, proteinG: 31, carbsG: 48, fatG: 34, fiberG: 2
        ),
        CommonFood(
            id: "ff-sonic-tots", name: "Sonic tater tots",
            aliases: ["sonic tots", "sonic tater tots", "tater tots sonic"],
            servingLabel: "Medium (148 g)",
            calories: 360, proteinG: 4, carbsG: 44, fatG: 18, fiberG: 3
        ),
        CommonFood(
            id: "ff-sonic-corn-dog", name: "Sonic corn dog",
            aliases: ["sonic corn dog", "sonic hotdog", "corn dog sonic"],
            servingLabel: "1 corn dog (97 g)",
            calories: 220, proteinG: 7, carbsG: 26, fatG: 10, fiberG: 1
        ),

        // — Jack in the Box — https://www.jackinthebox.com/nutrition
        CommonFood(
            id: "ff-jack-spicy-chicken", name: "Jack in the Box Spicy Deluxe Crispy Chicken",
            aliases: ["jack in the box spicy chicken", "jack spicy chicken", "jitb spicy chicken sandwich"],
            servingLabel: "1 sandwich (236 g)",
            calories: 580, proteinG: 31, carbsG: 59, fatG: 25, fiberG: 3
        ),
        CommonFood(
            id: "ff-jack-jumbo-jack", name: "Jack in the Box Jumbo Jack",
            aliases: ["jumbo jack", "jack in the box jumbo jack", "jitb jumbo jack"],
            servingLabel: "1 burger (256 g)",
            calories: 590, proteinG: 26, carbsG: 47, fatG: 33, fiberG: 2
        ),

        // — Dairy Queen — https://www.dairyqueen.com/us-en/food/nutrition-info/
        CommonFood(
            id: "ff-dq-blizzard-medium", name: "Dairy Queen Blizzard",
            // DQ Oreo Blizzard medium
            aliases: ["dairy queen blizzard", "dq blizzard", "blizzard dairy queen", "oreo blizzard"],
            servingLabel: "Medium (414 g)",
            calories: 740, proteinG: 15, carbsG: 106, fatG: 28, fiberG: 1
        ),
        CommonFood(
            id: "ff-dq-soft-serve-cone", name: "Dairy Queen vanilla cone",
            aliases: ["dairy queen cone", "dq cone", "vanilla soft serve cone", "dq vanilla cone"],
            servingLabel: "Medium soft serve (163 g)",
            calories: 330, proteinG: 9, carbsG: 52, fatG: 11, fiberG: 0
        ),
        CommonFood(
            id: "ff-dq-chicken-strips", name: "Dairy Queen chicken strip basket",
            aliases: ["dq chicken strips", "dairy queen chicken strips", "dq strip basket"],
            servingLabel: "4-piece basket with fries (418 g)",
            calories: 1010, proteinG: 43, carbsG: 118, fatG: 40, fiberG: 7
        ),

        // — Wingstop — https://www.wingstop.com/menu/nutrition
        CommonFood(
            id: "ff-wingstop-original-hot", name: "Wingstop Original Hot wings",
            aliases: ["wingstop wings", "wingstop original hot", "wingstop classic wings", "wingstop hot wings"],
            servingLabel: "6 classic wings (~180 g meat)",
            calories: 560, proteinG: 46, carbsG: 2, fatG: 40, fiberG: 0
        ),
        CommonFood(
            id: "ff-wingstop-fries", name: "Wingstop seasoned fries",
            aliases: ["wingstop fries", "wingstop cajun fries", "wingstop seasoned fries"],
            servingLabel: "Large (227 g)",
            calories: 470, proteinG: 6, carbsG: 69, fatG: 20, fiberG: 5
        ),
        CommonFood(
            id: "ff-wingstop-boneless", name: "Wingstop boneless wings",
            aliases: ["wingstop boneless", "boneless wings wingstop", "wingstop boneless chicken"],
            servingLabel: "8 pieces (~180 g)",
            calories: 510, proteinG: 36, carbsG: 35, fatG: 23, fiberG: 2
        ),

        // — Dunkin' — https://www.dunkindonuts.com/en/menu/nutrition
        CommonFood(
            id: "ff-dunkin-glazed-donut", name: "Dunkin' glazed donut",
            aliases: ["dunkin glazed donut", "dunkin' glazed donut", "dunkin donuts glazed", "dd glazed donut"],
            servingLabel: "1 donut (58 g)",
            calories: 260, proteinG: 4, carbsG: 33, fatG: 14, fiberG: 1
        ),
        CommonFood(
            id: "ff-dunkin-egg-sandwich", name: "Dunkin' egg & cheese sandwich",
            aliases: ["dunkin egg sandwich", "dunkin breakfast sandwich", "dunkin egg cheese", "dd breakfast sandwich"],
            servingLabel: "1 sandwich (131 g) on croissant",
            calories: 420, proteinG: 14, carbsG: 31, fatG: 28, fiberG: 1
        ),

        // — Krispy Kreme — https://www.krispykreme.com/nutrition
        CommonFood(
            id: "ff-krispy-kreme-original", name: "Krispy Kreme Original Glazed donut",
            aliases: ["krispy kreme", "krispy kreme glazed", "original glazed donut krispy kreme", "kk original glazed"],
            servingLabel: "1 donut (52 g)",
            calories: 190, proteinG: 2, carbsG: 22, fatG: 11, fiberG: 0
        ),

        // — Culver's — https://www.culvers.com/menu-and-nutrition/
        CommonFood(
            id: "ff-culvers-butterburger", name: "Culver's ButterBurger",
            aliases: ["culvers butterburger", "culver's butterburger", "butterburger"],
            servingLabel: "1 single ButterBurger (156 g)",
            calories: 380, proteinG: 20, carbsG: 34, fatG: 18, fiberG: 1
        ),
        CommonFood(
            id: "ff-culvers-cheese-curds", name: "Culver's Wisconsin cheese curds",
            aliases: ["culvers cheese curds", "culver's cheese curds", "cheese curds culvers"],
            servingLabel: "Regular (151 g)",
            calories: 530, proteinG: 27, carbsG: 40, fatG: 29, fiberG: 1
        ),

        // — Whataburger — https://whataburger.com/nutrition
        CommonFood(
            id: "ff-whataburger", name: "Whataburger",
            aliases: ["whataburger", "whata burger"],
            servingLabel: "1 burger (301 g)",
            calories: 590, proteinG: 30, carbsG: 61, fatG: 26, fiberG: 3
        ),

        // — Buffalo Wild Wings — https://www.buffalowildwings.com/en/food/
        CommonFood(
            id: "ff-bww-traditional-wings", name: "Buffalo Wild Wings traditional wings",
            aliases: ["buffalo wild wings", "bww wings", "bdubs wings", "bdubs traditional", "buffalo wings bdubs"],
            servingLabel: "6 medium traditional wings with sauce (~200 g)",
            calories: 430, proteinG: 36, carbsG: 0, fatG: 30, fiberG: 0
        ),
        CommonFood(
            id: "ff-jollibee-spaghetti", name: "Jollibee Jolly Spaghetti",
            // Jollibee official
            aliases: ["jollibee spaghetti", "jolly spaghetti", "filipino sweet spaghetti jollibee", "jollibee pasta"],
            servingLabel: "1 plate (320 g)",
            calories: 560, proteinG: 19, carbsG: 84, fatG: 17, fiberG: 4
        ),
        CommonFood(
            id: "ff-jollibee-palabok", name: "Jollibee Palabok Fiesta",
            // Jollibee official
            aliases: ["jollibee palabok", "palabok fiesta", "jollibee pancit palabok", "filipino shrimp noodles jollibee"],
            servingLabel: "1 plate (340 g)",
            calories: 590, proteinG: 23, carbsG: 75, fatG: 22, fiberG: 3
        ),
        CommonFood(
            id: "ff-jollibee-peach-mango-pie", name: "Jollibee Peach Mango Pie",
            // Jollibee official
            aliases: ["jollibee peach mango pie", "jollibee mango pie", "peach mango pie jollibee", "jollibee fried pie"],
            servingLabel: "1 pie (80 g)",
            calories: 270, proteinG: 3, carbsG: 36, fatG: 12, fiberG: 2
        ),
        CommonFood(
            id: "ff-jollibee-burger-steak", name: "Jollibee Burger Steak",
            // Jollibee official
            aliases: ["jollibee burger steak", "burger steak jollibee", "jollibee mushroom gravy patty", "filipino burger steak rice"],
            servingLabel: "1 patty with gravy (130 g)",
            calories: 280, proteinG: 10, carbsG: 24, fatG: 16, fiberG: 1
        ),
        CommonFood(
            id: "ff-mcd-mcchicken", name: "McChicken",
            // McDonald's official
            aliases: ["mcchicken", "mcdonalds mcchicken", "mcdonald's mcchicken", "mc chicken sandwich"],
            servingLabel: "1 sandwich (143 g)",
            calories: 400, proteinG: 14, carbsG: 40, fatG: 21, fiberG: 2
        ),
        CommonFood(
            id: "ff-mcd-mcdouble", name: "McDouble",
            // McDonald's official
            aliases: ["mcdouble", "mcdonalds mcdouble", "double cheeseburger mcdonalds", "mc double"],
            servingLabel: "1 burger (151 g)",
            calories: 400, proteinG: 22, carbsG: 33, fatG: 20, fiberG: 2
        ),
        CommonFood(
            id: "ff-mcd-egg-mcmuffin", name: "Egg McMuffin",
            // McDonald's official
            aliases: ["egg mcmuffin", "mcdonalds egg mcmuffin", "egg mc muffin", "mcdonalds breakfast muffin"],
            servingLabel: "1 muffin (135 g)",
            calories: 310, proteinG: 17, carbsG: 30, fatG: 13, fiberG: 2
        ),
        CommonFood(
            id: "ff-mcd-sausage-mcmuffin-egg", name: "Sausage McMuffin with Egg",
            // McDonald's official
            aliases: ["sausage mcmuffin with egg", "mcdonalds sausage mcmuffin", "sausage egg mcmuffin", "sausage mc muffin"],
            servingLabel: "1 muffin (163 g)",
            calories: 480, proteinG: 20, carbsG: 30, fatG: 31, fiberG: 2
        ),
        CommonFood(
            id: "ff-mcd-hash-brown", name: "McDonald's hash brown",
            // McDonald's official
            aliases: ["mcdonalds hash brown", "mcdonald's hash brown", "mcdonalds hashbrown", "mcdonalds breakfast hash brown"],
            servingLabel: "1 piece (53 g)",
            calories: 140, proteinG: 1, carbsG: 16, fatG: 8, fiberG: 2
        ),
        CommonFood(
            id: "ff-mcd-hotcakes", name: "Hotcakes (3)",
            // McDonald's official
            aliases: ["mcdonalds hotcakes", "mcdonald's hotcakes", "mcdonalds pancakes", "three hotcakes"],
            servingLabel: "3 hotcakes with syrup & butter (228 g)",
            calories: 580, proteinG: 8, carbsG: 102, fatG: 16, fiberG: 3
        ),
        CommonFood(
            id: "ff-mcd-filet-o-fish", name: "Filet-O-Fish",
            // McDonald's official
            aliases: ["filet o fish", "filet-o-fish", "mcdonalds fish sandwich", "fillet o fish"],
            servingLabel: "1 sandwich (142 g)",
            calories: 390, proteinG: 15, carbsG: 39, fatG: 19, fiberG: 2
        ),
        CommonFood(
            id: "ff-mcd-mcflurry-oreo", name: "McFlurry with Oreo Cookies",
            // McDonald's official
            aliases: ["oreo mcflurry", "mcdonalds mcflurry", "mc flurry oreo", "oreo mc flurry"],
            servingLabel: "Regular (285 g)",
            calories: 480, proteinG: 11, carbsG: 80, fatG: 15, fiberG: 1
        ),
        CommonFood(
            id: "ff-mcd-apple-pie", name: "McDonald's Baked Apple Pie",
            // McDonald's official
            aliases: ["mcdonalds apple pie", "mcdonald's apple pie", "baked apple pie mcdonalds", "mcdonalds hot apple pie"],
            servingLabel: "1 pie (77 g)",
            calories: 230, proteinG: 2, carbsG: 33, fatG: 11, fiberG: 4
        ),
        CommonFood(
            id: "ff-mcd-sausage-biscuit", name: "Sausage Biscuit",
            // McDonald's official
            aliases: ["mcdonalds sausage biscuit", "mcdonald's sausage biscuit", "sausage biscuit mcdonalds", "breakfast sausage biscuit"],
            servingLabel: "1 biscuit (111 g)",
            calories: 460, proteinG: 11, carbsG: 36, fatG: 30, fiberG: 2
        ),
        CommonFood(
            id: "ff-mcd-mcnuggets-6", name: "Chicken McNuggets (6 pc)",
            // McDonald's official
            aliases: ["6 piece mcnuggets", "6 piece chicken nuggets mcdonalds", "six piece mcnuggets", "6pc mcnuggets"],
            servingLabel: "6 pieces (97 g)",
            calories: 250, proteinG: 14, carbsG: 15, fatG: 15, fiberG: 1
        ),
        CommonFood(
            id: "ff-mcd-fries-large", name: "McDonald's large fries",
            // McDonald's official
            aliases: ["mcdonalds large fries", "mcdonald's large fries", "mcdonalds large french fries", "large world famous fries"],
            servingLabel: "Large (150 g)",
            calories: 510, proteinG: 7, carbsG: 66, fatG: 24, fiberG: 6
        ),
        CommonFood(
            id: "ff-mcd-sausage-mcgriddles", name: "Sausage McGriddles",
            // McDonald's official
            aliases: ["sausage mcgriddles", "mcdonalds mcgriddle", "sausage mc griddle", "mcgriddle sausage"],
            servingLabel: "1 sandwich (115 g)",
            calories: 430, proteinG: 11, carbsG: 43, fatG: 24, fiberG: 2
        ),
        CommonFood(
            id: "ff-mcd-bacon-egg-cheese-biscuit", name: "Bacon, Egg & Cheese Biscuit",
            // McDonald's official
            aliases: ["bacon egg and cheese biscuit", "mcdonalds bacon egg cheese biscuit", "bacon egg cheese biscuit", "bec biscuit mcdonalds"],
            servingLabel: "1 biscuit (149 g)",
            calories: 460, proteinG: 19, carbsG: 38, fatG: 26, fiberG: 2
        ),
        CommonFood(
            id: "ff-wendys-baconator", name: "Wendy's Baconator",
            // Wendy's official
            aliases: ["wendys baconator", "wendy's baconator", "baconator burger", "wendys bacon burger"],
            servingLabel: "1 burger (296 g)",
            calories: 950, proteinG: 56, carbsG: 40, fatG: 62, fiberG: 2
        ),
        CommonFood(
            id: "ff-wendys-spicy-chicken-sandwich", name: "Wendy's Spicy Chicken Sandwich",
            // Wendy's official
            aliases: ["wendys spicy chicken sandwich", "wendy's spicy chicken", "spicy chicken sandwich wendys", "wendys spicy chicken sandwich"],
            servingLabel: "1 sandwich (225 g)",
            calories: 510, proteinG: 31, carbsG: 50, fatG: 20, fiberG: 3
        ),
        CommonFood(
            id: "ff-wendys-nuggets-10", name: "Wendy's Chicken Nuggets (10 pc)",
            // Wendy's official
            aliases: ["wendys nuggets", "wendy's chicken nuggets", "10 piece nuggets wendys", "wendys 10 piece nuggets"],
            servingLabel: "10 pieces (150 g)",
            calories: 420, proteinG: 24, carbsG: 24, fatG: 26, fiberG: 1
        ),
        CommonFood(
            id: "ff-wendys-jr-bacon-cheeseburger", name: "Wendy's Jr. Bacon Cheeseburger",
            // Wendy's official
            aliases: ["jr bacon cheeseburger", "wendys jr bacon cheeseburger", "junior bacon cheeseburger wendys", "wendys junior bacon burger"],
            servingLabel: "1 burger (129 g)",
            calories: 380, proteinG: 20, carbsG: 25, fatG: 22, fiberG: 1
        ),
        CommonFood(
            id: "ff-wendys-chili-small", name: "Wendy's Chili (small)",
            // Wendy's official
            aliases: ["wendys chili", "wendy's chili small", "small chili wendys", "wendys beef chili"],
            servingLabel: "Small (227 g)",
            calories: 240, proteinG: 17, carbsG: 23, fatG: 7, fiberG: 6
        ),
        CommonFood(
            id: "ff-wendys-baconator-fries", name: "Wendy's Baconator Fries",
            // Wendy's official
            aliases: ["baconator fries", "wendys baconator fries", "wendy's baconator fries", "bacon cheese fries wendys"],
            servingLabel: "1 order (170 g)",
            calories: 480, proteinG: 15, carbsG: 46, fatG: 27, fiberG: 5
        ),
        CommonFood(
            id: "ff-wendys-daves-double", name: "Wendy's Dave's Double",
            // Wendy's official
            aliases: ["daves double", "wendys daves double", "dave's double burger", "wendys double cheeseburger"],
            servingLabel: "1 burger (314 g)",
            calories: 810, proteinG: 48, carbsG: 40, fatG: 50, fiberG: 2
        ),
        CommonFood(
            id: "ff-tb-doritos-locos-taco", name: "Taco Bell Doritos Locos Taco",
            // Taco Bell official
            aliases: ["doritos locos taco", "taco bell doritos taco", "nacho cheese doritos locos taco", "dlt taco bell"],
            servingLabel: "1 taco (78 g)",
            calories: 170, proteinG: 8, carbsG: 13, fatG: 9, fiberG: 3
        ),
        CommonFood(
            id: "ff-tb-bean-burrito", name: "Taco Bell Bean Burrito",
            // Taco Bell official
            aliases: ["taco bell bean burrito", "bean burrito taco bell", "refried bean burrito", "tb bean burrito"],
            servingLabel: "1 burrito (198 g)",
            calories: 350, proteinG: 13, carbsG: 54, fatG: 9, fiberG: 11
        ),
        CommonFood(
            id: "ff-tb-nachos-bellgrande", name: "Taco Bell Nachos BellGrande",
            // Taco Bell official
            aliases: ["nachos bellgrande", "taco bell nachos bellgrande", "nachos bell grande", "tb nachos bellgrande"],
            servingLabel: "1 order (484 g)",
            calories: 740, proteinG: 16, carbsG: 82, fatG: 38, fiberG: 12
        ),
        CommonFood(
            id: "ff-tb-cinnamon-twists", name: "Taco Bell Cinnamon Twists",
            // Taco Bell official
            aliases: ["cinnamon twists", "taco bell cinnamon twists", "cinnamon twists taco bell", "tb cinnamon twists"],
            servingLabel: "1 order (35 g)",
            calories: 170, proteinG: 2, carbsG: 27, fatG: 6, fiberG: 1
        ),
        CommonFood(
            id: "ff-tb-mexican-pizza", name: "Taco Bell Mexican Pizza",
            // Taco Bell official
            aliases: ["mexican pizza", "taco bell mexican pizza", "mexican pizza taco bell", "tb mexican pizza"],
            servingLabel: "1 pizza (218 g)",
            calories: 540, proteinG: 19, carbsG: 48, fatG: 30, fiberG: 6
        ),
        CommonFood(
            id: "ff-tb-cheesy-gordita-crunch", name: "Taco Bell Cheesy Gordita Crunch",
            // Taco Bell official
            aliases: ["cheesy gordita crunch", "taco bell gordita crunch", "cheesy gordita crunch taco bell", "cgc taco bell"],
            servingLabel: "1 gordita (200 g)",
            calories: 500, proteinG: 20, carbsG: 41, fatG: 28, fiberG: 4
        ),
        CommonFood(
            id: "ff-tb-beefy-5-layer-burrito", name: "Taco Bell Beefy 5-Layer Burrito",
            // Taco Bell official
            aliases: ["beefy 5 layer burrito", "taco bell 5 layer burrito", "beefy five layer burrito", "beefy 5-layer burrito"],
            servingLabel: "1 burrito (248 g)",
            calories: 490, proteinG: 18, carbsG: 64, fatG: 18, fiberG: 9
        ),
        CommonFood(
            id: "ff-bk-chicken-fries", name: "Burger King Chicken Fries",
            // Burger King official
            aliases: ["bk chicken fries", "burger king chicken fries", "chicken fries burger king", "9 piece chicken fries"],
            servingLabel: "9 pieces (114 g)",
            calories: 280, proteinG: 13, carbsG: 19, fatG: 17, fiberG: 1
        ),
        CommonFood(
            id: "ff-bk-bacon-king", name: "Burger King Bacon King",
            // Burger King official
            aliases: ["bacon king", "burger king bacon king", "bk bacon king burger", "bacon king sandwich"],
            servingLabel: "1 sandwich (322 g)",
            calories: 1050, proteinG: 57, carbsG: 49, fatG: 70, fiberG: 2
        ),
        CommonFood(
            id: "ff-bk-whopper-jr", name: "Whopper Jr.",
            // Burger King official
            aliases: ["whopper jr", "burger king whopper jr", "whopper junior", "bk whopper jr"],
            servingLabel: "1 sandwich (133 g)",
            calories: 310, proteinG: 13, carbsG: 27, fatG: 17, fiberG: 1
        ),
        CommonFood(
            id: "ff-bk-mozzarella-sticks", name: "Burger King Mozzarella Sticks",
            // Burger King official
            aliases: ["bk mozzarella sticks", "burger king mozzarella sticks", "mozzarella sticks burger king", "4 piece mozzarella sticks bk"],
            servingLabel: "4 pieces (113 g)",
            calories: 350, proteinG: 14, carbsG: 33, fatG: 18, fiberG: 2
        ),
        CommonFood(
            id: "ff-bk-original-chicken-sandwich", name: "BK Original Chicken Sandwich",
            // Burger King official
            aliases: ["bk original chicken sandwich", "burger king chicken sandwich", "original chicken sandwich burger king", "bk chicken sandwich"],
            servingLabel: "1 sandwich (219 g)",
            calories: 660, proteinG: 28, carbsG: 52, fatG: 40, fiberG: 4
        ),
        CommonFood(
            id: "ff-bk-croissanwich", name: "Sausage, Egg & Cheese Croissan'wich",
            // Burger King official
            aliases: ["croissanwich", "burger king croissanwich", "sausage egg cheese croissanwich", "bk croissan'wich"],
            servingLabel: "1 sandwich (160 g)",
            calories: 500, proteinG: 18, carbsG: 28, fatG: 35, fiberG: 1
        ),
        CommonFood(
            id: "ff-sonic-mozzarella-sticks", name: "Sonic Mozzarella Sticks",
            // Sonic Drive-In official
            aliases: ["sonic mozzarella sticks", "sonic mozz sticks", "mozzarella sticks sonic", "sonic cheese sticks"],
            servingLabel: "5 pieces (137 g)",
            calories: 440, proteinG: 19, carbsG: 40, fatG: 22, fiberG: 2
        ),
        CommonFood(
            id: "ff-kfc-popcorn-chicken-lg", name: "KFC Popcorn Chicken (Large)",
            // KFC official
            aliases: ["kfc popcorn chicken", "popcorn chicken", "kentucky fried popcorn chicken", "kfc popcorn nuggets"],
            servingLabel: "Large (159 g)",
            calories: 620, proteinG: 30, carbsG: 36, fatG: 40, fiberG: 3
        ),
        CommonFood(
            id: "ff-kfc-famous-bowl", name: "KFC Famous Bowl",
            // KFC official
            aliases: ["kfc famous bowl", "famous bowl", "kentucky fried famous bowl", "mashed potato gravy bowl"],
            servingLabel: "1 bowl (485 g)",
            calories: 720, proteinG: 26, carbsG: 77, fatG: 33, fiberG: 6
        ),
        CommonFood(
            id: "ff-kfc-tenders-3pc", name: "KFC Crispy Tenders (3 pc)",
            // KFC official
            aliases: ["kfc tenders", "kfc crispy tenders", "kentucky fried tenders", "3 piece tenders kfc"],
            servingLabel: "3 tenders (132 g)",
            calories: 410, proteinG: 29, carbsG: 24, fatG: 21, fiberG: 2
        ),
        CommonFood(
            id: "ff-kfc-coleslaw", name: "KFC Coleslaw",
            // KFC official
            aliases: ["kfc coleslaw", "kfc cole slaw", "kentucky fried coleslaw", "kfc slaw side"],
            servingLabel: "Individual (130 g)",
            calories: 170, proteinG: 1, carbsG: 22, fatG: 9, fiberG: 3
        ),
        CommonFood(
            id: "ff-kfc-mashed-potatoes-gravy", name: "KFC Mashed Potatoes with Gravy",
            // KFC official
            aliases: ["kfc mashed potatoes", "kfc mashed potatoes and gravy", "kentucky fried mashed potatoes", "kfc potatoes gravy"],
            servingLabel: "Individual (136 g)",
            calories: 130, proteinG: 3, carbsG: 19, fatG: 5, fiberG: 1
        ),
        CommonFood(
            id: "ff-kfc-biscuit", name: "KFC Biscuit",
            // KFC official
            aliases: ["kfc biscuit", "kentucky fried biscuit", "kfc buttermilk biscuit"],
            servingLabel: "1 biscuit (62 g)",
            calories: 180, proteinG: 4, carbsG: 23, fatG: 8, fiberG: 1
        ),
        CommonFood(
            id: "ff-popeyes-red-beans-rice", name: "Popeyes Red Beans & Rice",
            // Popeyes official
            aliases: ["popeyes red beans and rice", "popeyes red beans", "cajun red beans rice", "louisiana red beans rice"],
            servingLabel: "Regular (139 g)",
            calories: 230, proteinG: 7, carbsG: 31, fatG: 8, fiberG: 7
        ),
        CommonFood(
            id: "ff-popeyes-biscuit", name: "Popeyes Buttermilk Biscuit",
            // Popeyes official
            aliases: ["popeyes biscuit", "popeyes buttermilk biscuit", "louisiana biscuit", "cajun biscuit"],
            servingLabel: "1 biscuit (60 g)",
            calories: 230, proteinG: 3, carbsG: 26, fatG: 13, fiberG: 1
        ),
        CommonFood(
            id: "ff-popeyes-cajun-fries", name: "Popeyes Cajun Fries",
            // Popeyes official
            aliases: ["popeyes cajun fries", "cajun fries", "popeyes seasoned fries", "louisiana cajun fries"],
            servingLabel: "Regular (95 g)",
            calories: 290, proteinG: 4, carbsG: 36, fatG: 15, fiberG: 4
        ),
        CommonFood(
            id: "ff-popeyes-blackened-tenders", name: "Popeyes Blackened Chicken Tenders (3 pc)",
            // Popeyes official
            aliases: ["popeyes blackened tenders", "popeyes blackened chicken", "cajun blackened tenders", "popeyes grilled tenders"],
            servingLabel: "3 tenders (130 g)",
            calories: 170, proteinG: 31, carbsG: 3, fatG: 4, fiberG: 1
        ),
        CommonFood(
            id: "ff-cfa-spicy-sandwich", name: "Chick-fil-A Spicy Chicken Sandwich",
            // Chick-fil-A official
            aliases: ["chick fil a spicy sandwich", "chick-fil-a spicy chicken sandwich", "cfa spicy sandwich", "chickfila spicy chicken"],
            servingLabel: "1 sandwich (187 g)",
            calories: 450, proteinG: 28, carbsG: 42, fatG: 19, fiberG: 2
        ),
        CommonFood(
            id: "ff-cfa-mac-and-cheese", name: "Chick-fil-A Mac & Cheese",
            // Chick-fil-A official
            aliases: ["chick fil a mac and cheese", "chick-fil-a mac and cheese", "cfa mac and cheese", "chickfila macaroni"],
            servingLabel: "Medium (218 g)",
            calories: 450, proteinG: 18, carbsG: 30, fatG: 29, fiberG: 1
        ),
        CommonFood(
            id: "ff-cfa-cobb-salad", name: "Chick-fil-A Cobb Salad (no dressing)",
            // Chick-fil-A official, with nuggets
            aliases: ["chick fil a cobb salad", "chick-fil-a cobb salad", "cfa cobb salad", "chickfila cobb"],
            servingLabel: "1 salad (337 g)",
            calories: 510, proteinG: 40, carbsG: 27, fatG: 28, fiberG: 5
        ),
        CommonFood(
            id: "ff-cfa-frosted-lemonade", name: "Chick-fil-A Frosted Lemonade",
            // Chick-fil-A official
            aliases: ["chick fil a frosted lemonade", "chick-fil-a frosted lemonade", "cfa frosted lemonade", "chickfila frosted lemonade"],
            servingLabel: "Small (482 g)",
            calories: 330, proteinG: 7, carbsG: 63, fatG: 6, fiberG: 0
        ),
        CommonFood(
            id: "ff-cfa-chicken-biscuit", name: "Chick-fil-A Chicken Biscuit",
            // Chick-fil-A official
            aliases: ["chick fil a chicken biscuit", "chick-fil-a chicken biscuit", "cfa chicken biscuit", "chickfila biscuit"],
            servingLabel: "1 biscuit (143 g)",
            calories: 460, proteinG: 17, carbsG: 45, fatG: 23, fiberG: 2
        ),
        CommonFood(
            id: "ff-cfa-grilled-nuggets-8", name: "Chick-fil-A Grilled Nuggets (8 ct)",
            // Chick-fil-A official
            aliases: ["chick fil a grilled nuggets", "chick-fil-a grilled nuggets", "cfa grilled nuggets", "chickfila grilled nuggets"],
            servingLabel: "8 count (113 g)",
            calories: 130, proteinG: 25, carbsG: 1, fatG: 3, fiberG: 0
        ),
        CommonFood(
            id: "ff-subway-meatball-marinara-footlong", name: "Subway Meatball Marinara Footlong",
            // Subway official
            aliases: ["subway meatball marinara", "meatball marinara footlong", "subway meatball sub", "footlong meatball marinara"],
            servingLabel: "Footlong (491 g)",
            calories: 960, proteinG: 42, carbsG: 116, fatG: 36, fiberG: 10
        ),
        CommonFood(
            id: "ff-subway-tuna-footlong", name: "Subway Tuna Footlong",
            // Subway official
            aliases: ["subway tuna footlong", "footlong tuna sub", "subway tuna sandwich", "tuna melt subway"],
            servingLabel: "Footlong (456 g)",
            calories: 960, proteinG: 42, carbsG: 76, fatG: 54, fiberG: 6
        ),
        CommonFood(
            id: "ff-subway-steak-cheese-footlong", name: "Subway Steak & Cheese Footlong",
            // Subway official
            aliases: ["subway steak and cheese", "steak and cheese footlong", "subway philly steak", "footlong steak cheese"],
            servingLabel: "Footlong (530 g)",
            calories: 740, proteinG: 48, carbsG: 86, fatG: 24, fiberG: 10
        ),
        CommonFood(
            id: "ff-subway-sweet-onion-chicken-teriyaki", name: "Subway Sweet Onion Chicken Teriyaki Footlong",
            // Subway official
            aliases: ["subway sweet onion chicken teriyaki", "sweet onion chicken teriyaki", "subway teriyaki chicken", "footlong chicken teriyaki"],
            servingLabel: "Footlong (560 g)",
            calories: 760, proteinG: 48, carbsG: 118, fatG: 12, fiberG: 8
        ),
        CommonFood(
            id: "ff-pizzahut-pepperoni-pan-slice", name: "Pizza Hut Pepperoni Pan Pizza (1 slice)",
            // Pizza Hut official
            aliases: ["pizza hut pepperoni pan", "pepperoni pan pizza slice", "pizza hut pan slice", "pizza hut pepperoni slice"],
            servingLabel: "1 slice, large (113 g)",
            calories: 340, proteinG: 13, carbsG: 33, fatG: 17, fiberG: 2
        ),
        CommonFood(
            id: "ff-littlecaesars-cheese-slice", name: "Little Caesars Cheese Pizza (1 slice)",
            // Little Caesars official
            aliases: ["little caesars cheese slice", "little caesars cheese pizza", "lil caesars cheese slice", "little caesars classic cheese"],
            servingLabel: "1 slice (104 g)",
            calories: 250, proteinG: 12, carbsG: 31, fatG: 9, fiberG: 1
        ),
        CommonFood(
            id: "ff-papajohns-pepperoni-slice", name: "Papa John's Pepperoni Pizza (1 slice)",
            // Papa John's official
            aliases: ["papa johns pepperoni slice", "papa johns pepperoni pizza", "papa john pepperoni slice", "papa johns original crust pepperoni"],
            servingLabel: "1 slice, large (109 g)",
            calories: 290, proteinG: 12, carbsG: 34, fatG: 12, fiberG: 1
        ),
        CommonFood(
            id: "ff-chipotle-sofritas-bowl", name: "Chipotle Sofritas Bowl",
            // Chipotle official, rice/beans/sofritas/salsa
            aliases: ["chipotle sofritas bowl", "sofritas bowl", "chipotle tofu bowl", "chipotle sofritas burrito bowl"],
            servingLabel: "1 bowl (510 g)",
            calories: 605, proteinG: 18, carbsG: 85, fatG: 21, fiberG: 15
        ),
        CommonFood(
            id: "ff-chipotle-queso-blanco", name: "Chipotle Queso Blanco (side)",
            // Chipotle official
            aliases: ["chipotle queso blanco", "chipotle queso", "queso blanco side", "chipotle white queso"],
            servingLabel: "4 oz side (113 g)",
            calories: 120, proteinG: 5, carbsG: 7, fatG: 9, fiberG: 1
        ),
        CommonFood(
            id: "ff-panda-beijing-beef", name: "Beijing Beef (Panda Express)",
            // Panda Express official
            aliases: ["beijing beef", "panda express beijing beef", "panda beijing beef", "crispy beijing beef"],
            servingLabel: "1 serving (5.6 oz / 159 g)",
            calories: 480, proteinG: 14, carbsG: 46, fatG: 27, fiberG: 1
        ),
        CommonFood(
            id: "ff-panda-kung-pao-chicken", name: "Kung Pao Chicken (Panda Express)",
            // Panda Express official
            aliases: ["kung pao chicken", "panda express kung pao", "panda kung pao chicken", "spicy kung pao chicken"],
            servingLabel: "1 serving (5.7 oz / 162 g)",
            calories: 290, proteinG: 16, carbsG: 14, fatG: 19, fiberG: 2
        ),
        CommonFood(
            id: "ff-panda-honey-walnut-shrimp", name: "Honey Walnut Shrimp (Panda Express)",
            // Panda Express official
            aliases: ["honey walnut shrimp", "panda express honey walnut shrimp", "panda walnut shrimp", "candied walnut shrimp"],
            servingLabel: "1 serving (3.7 oz / 105 g)",
            calories: 360, proteinG: 13, carbsG: 35, fatG: 23, fiberG: 2
        ),
        CommonFood(
            id: "ff-panda-fried-rice", name: "Fried Rice (Panda Express)",
            // Panda Express official
            aliases: ["panda express fried rice", "panda fried rice", "chinese fried rice side", "panda express white fried rice"],
            servingLabel: "1 side (9.3 oz / 264 g)",
            calories: 520, proteinG: 11, carbsG: 85, fatG: 16, fiberG: 1
        ),
        CommonFood(
            id: "ff-panda-super-greens", name: "Super Greens (Panda Express)",
            // Panda Express official
            aliases: ["panda express super greens", "super greens side", "panda super greens", "broccoli kale cabbage side"],
            servingLabel: "1 side (9.4 oz / 268 g)",
            calories: 90, proteinG: 6, carbsG: 10, fatG: 3, fiberG: 5
        ),
        CommonFood(
            id: "ff-panda-broccoli-beef", name: "Broccoli Beef (Panda Express)",
            // Panda Express official
            aliases: ["broccoli beef", "panda express broccoli beef", "panda broccoli beef", "beef and broccoli panda"],
            servingLabel: "1 serving (5.4 oz / 153 g)",
            calories: 150, proteinG: 9, carbsG: 13, fatG: 7, fiberG: 2
        ),
        CommonFood(
            id: "ff-sbux-bacon-gouda-sandwich", name: "Starbucks Bacon & Gouda Sandwich",
            // Starbucks official
            aliases: ["starbucks bacon gouda", "bacon gouda sandwich", "starbucks bacon and gouda breakfast", "sbux bacon gouda"],
            servingLabel: "1 sandwich (123 g)",
            calories: 360, proteinG: 17, carbsG: 31, fatG: 19, fiberG: 1
        ),
        CommonFood(
            id: "ff-sbux-egg-bites-bacon-gruyere", name: "Starbucks Bacon & Gruyère Egg Bites",
            // Starbucks official
            aliases: ["starbucks egg bites", "bacon gruyere egg bites", "sous vide egg bites", "starbucks bacon egg bites"],
            servingLabel: "2 bites (130 g)",
            calories: 300, proteinG: 19, carbsG: 9, fatG: 20, fiberG: 0
        ),
        CommonFood(
            id: "ff-sbux-cake-pop", name: "Starbucks Birthday Cake Pop",
            // Starbucks official
            aliases: ["starbucks cake pop", "birthday cake pop", "sbux cake pop", "starbucks vanilla cake pop"],
            servingLabel: "1 cake pop (43 g)",
            calories: 160, proteinG: 2, carbsG: 22, fatG: 8, fiberG: 0
        ),
        CommonFood(
            id: "ff-sbux-banana-bread", name: "Starbucks Banana Walnut Bread",
            // Starbucks official
            aliases: ["starbucks banana bread", "banana walnut bread starbucks", "sbux banana bread", "starbucks banana loaf"],
            servingLabel: "1 slice (113 g)",
            calories: 420, proteinG: 7, carbsG: 56, fatG: 19, fiberG: 3
        ),
        CommonFood(
            id: "ff-dunkin-boston-kreme-donut", name: "Dunkin' Boston Kreme Donut",
            // Dunkin' official
            aliases: ["dunkin boston kreme", "boston kreme donut", "dunkin boston cream donut", "boston creme donut dunkin"],
            servingLabel: "1 donut (87 g)",
            calories: 300, proteinG: 4, carbsG: 42, fatG: 13, fiberG: 1
        ),
        CommonFood(
            id: "ff-dunkin-munchkins-10", name: "Dunkin' Glazed Munchkins (10)",
            // Dunkin' official
            aliases: ["dunkin munchkins", "glazed munchkins", "dunkin donut holes", "munchkins 10 count"],
            servingLabel: "10 munchkins (200 g)",
            calories: 700, proteinG: 8, carbsG: 94, fatG: 33, fiberG: 3
        ),
        CommonFood(
            id: "ff-dunkin-bagel-cream-cheese", name: "Dunkin' Bagel with Cream Cheese",
            // Dunkin' official
            aliases: ["dunkin bagel with cream cheese", "dunkin plain bagel cream cheese", "dunkin bagel and cream cheese", "plain bagel cream cheese dunkin"],
            servingLabel: "1 bagel + spread (170 g)",
            calories: 520, proteinG: 15, carbsG: 78, fatG: 17, fiberG: 4
        ),
    ]

    // MARK: - Condiments, sauces & cooking fats
    // Logged as individual ingredients; per-tablespoon or standard packet sizing.

    private static let condiments: [CommonFood] = [
        CommonFood(
            id: "mayonnaise", name: "Mayonnaise",
            // USDA FDC #172339
            aliases: ["mayo", "mayonnaise", "hellmanns", "kewpie mayo", "japanese mayo"],
            servingLabel: "1 tbsp (14 g)",
            calories: 94, proteinG: 0, carbsG: 0, fatG: 10, fiberG: 0
        ),
        CommonFood(
            id: "ketchup", name: "Ketchup",
            // USDA FDC #172940
            aliases: ["ketchup", "catsup", "tomato ketchup", "heinz ketchup"],
            servingLabel: "1 tbsp (17 g)",
            calories: 19, proteinG: 0, carbsG: 5, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "mustard-yellow", name: "Mustard",
            // USDA FDC #172424
            aliases: ["mustard", "yellow mustard", "dijon mustard", "whole grain mustard"],
            servingLabel: "1 tbsp (15 g)",
            calories: 9, proteinG: 1, carbsG: 1, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "ranch-dressing", name: "Ranch dressing",
            // USDA FDC #172939
            aliases: ["ranch", "ranch dressing", "ranch sauce", "buttermilk ranch"],
            servingLabel: "2 tbsp (30 g)",
            calories: 145, proteinG: 1, carbsG: 2, fatG: 15, fiberG: 0
        ),
        CommonFood(
            id: "caesar-dressing", name: "Caesar dressing",
            // USDA FDC #172934
            aliases: ["caesar dressing", "caesar salad dressing"],
            servingLabel: "2 tbsp (30 g)",
            calories: 163, proteinG: 1, carbsG: 1, fatG: 17, fiberG: 0
        ),
        CommonFood(
            id: "balsamic-vinaigrette", name: "Balsamic vinaigrette",
            aliases: ["balsamic vinaigrette", "balsamic dressing", "italian dressing"],
            servingLabel: "2 tbsp (30 g)",
            calories: 90, proteinG: 0, carbsG: 8, fatG: 7, fiberG: 0
        ),
        CommonFood(
            id: "hot-sauce", name: "Hot sauce",
            // USDA FDC #172942 (Tabasco / Frank's style)
            aliases: ["hot sauce", "tabasco", "franks hot sauce", "louisiana hot sauce", "cholula", "valentina"],
            servingLabel: "1 tbsp (15 g)",
            calories: 3, proteinG: 0, carbsG: 1, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "sriracha", name: "Sriracha",
            // Huy Fong official
            aliases: ["sriracha", "sriracha sauce", "huy fong sriracha", "rooster sauce"],
            servingLabel: "1 tsp (5 g)",
            calories: 5, proteinG: 0, carbsG: 1, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "soy-sauce", name: "Soy sauce",
            // USDA FDC #172429
            aliases: ["soy sauce", "shoyu", "tamari", "liquid aminos", "dark soy sauce", "light soy sauce"],
            servingLabel: "1 tbsp (16 g)",
            calories: 10, proteinG: 1, carbsG: 1, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "oyster-sauce", name: "Oyster sauce",
            // USDA FDC #172430
            aliases: ["oyster sauce", "oyster flavored sauce"],
            servingLabel: "1 tbsp (18 g)",
            calories: 20, proteinG: 0, carbsG: 5, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "fish-sauce", name: "Fish sauce",
            // USDA FDC #172431
            aliases: ["fish sauce", "nam pla", "nuoc mam", "patis"],
            servingLabel: "1 tbsp (18 g)",
            calories: 13, proteinG: 1, carbsG: 1, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "honey", name: "Honey",
            // USDA FDC #169640
            aliases: ["honey", "raw honey", "manuka honey"],
            servingLabel: "1 tbsp (21 g)",
            calories: 64, proteinG: 0, carbsG: 17, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "maple-syrup", name: "Maple syrup",
            // USDA FDC #169661
            aliases: ["maple syrup", "pure maple syrup"],
            servingLabel: "1 tbsp (20 g)",
            calories: 52, proteinG: 0, carbsG: 13, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "bbq-sauce", name: "BBQ sauce",
            // USDA FDC #172932
            aliases: ["bbq sauce", "barbecue sauce", "hickory bbq sauce"],
            servingLabel: "2 tbsp (36 g)",
            calories: 50, proteinG: 0, carbsG: 12, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "teriyaki-sauce", name: "Teriyaki sauce",
            // USDA FDC #172933
            aliases: ["teriyaki sauce", "teriyaki marinade", "kikoman teriyaki"],
            servingLabel: "2 tbsp (30 g)",
            calories: 30, proteinG: 1, carbsG: 6, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "salsa-jar", name: "Salsa",
            // USDA FDC #172929
            aliases: ["salsa", "tomato salsa", "pico de gallo", "fresh salsa", "jar salsa"],
            servingLabel: "2 tbsp (30 g)",
            calories: 10, proteinG: 0, carbsG: 2, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "pesto-sauce", name: "Pesto",
            // USDA FDC #172938
            aliases: ["pesto", "basil pesto", "pesto sauce", "green pesto"],
            servingLabel: "2 tbsp (30 g)",
            calories: 160, proteinG: 3, carbsG: 2, fatG: 15, fiberG: 1
        ),
        CommonFood(
            id: "tzatziki-sauce", name: "Tzatziki",
            aliases: ["tzatziki", "cucumber yogurt sauce", "greek dip"],
            servingLabel: "2 tbsp (30 g)",
            calories: 35, proteinG: 2, carbsG: 2, fatG: 2, fiberG: 0
        ),
        CommonFood(
            id: "hoisin-sauce", name: "Hoisin sauce",
            // USDA FDC #172432
            aliases: ["hoisin sauce", "hoisin"],
            servingLabel: "1 tbsp (18 g)",
            calories: 35, proteinG: 1, carbsG: 7, fatG: 1, fiberG: 0
        ),
        CommonFood(
            id: "marinara-sauce", name: "Marinara sauce",
            // USDA FDC #172936
            aliases: ["marinara", "marinara sauce", "tomato sauce", "pasta sauce"],
            servingLabel: "½ cup (125 g)",
            calories: 70, proteinG: 2, carbsG: 14, fatG: 2, fiberG: 3
        ),
        CommonFood(
            id: "hummus-dip", name: "Hummus (as dip)",
            // USDA FDC #174275 — duplicate alias from legumes but common log pattern
            aliases: ["hummus dip", "store bought hummus", "sabra hummus"],
            servingLabel: "2 tbsp (30 g)",
            calories: 52, proteinG: 3, carbsG: 6, fatG: 3, fiberG: 2
        ),
        CommonFood(
            id: "guacamole-homemade", name: "Guacamole",
            aliases: ["guacamole", "homemade guacamole", "avocado dip"],
            servingLabel: "2 tbsp (30 g)",
            calories: 50, proteinG: 1, carbsG: 3, fatG: 4, fiberG: 2
        ),
        CommonFood(
            id: "cream-sauce", name: "Cream sauce / béchamel",
            aliases: ["cream sauce", "bechamel", "white sauce", "béchamel"],
            servingLabel: "¼ cup (60 g)",
            calories: 100, proteinG: 2, carbsG: 5, fatG: 8, fiberG: 0
        ),
        CommonFood(
            id: "hollandaise", name: "Hollandaise sauce",
            aliases: ["hollandaise", "hollandaise sauce"],
            servingLabel: "2 tbsp (30 g)",
            calories: 90, proteinG: 1, carbsG: 0, fatG: 9, fiberG: 0
        ),
        CommonFood(
            id: "coconut-milk", name: "Coconut milk",
            // USDA FDC #168583 (canned, full-fat)
            aliases: ["coconut milk", "coconut cream", "canned coconut milk", "full fat coconut milk"],
            servingLabel: "¼ cup (60 ml)",
            calories: 112, proteinG: 1, carbsG: 3, fatG: 12, fiberG: 0
        ),
        CommonFood(
            id: "aji-colombiano", name: "Ají Colombiano",
            aliases: ["aji colombiano", "colombian aji hot sauce", "aji picado"],
            servingLabel: "2 tbsp (30 g)",
            calories: 25, proteinG: 1, carbsG: 3, fatG: 1, fiberG: 1
        ),
        CommonFood(
            id: "hogao-criollo-sauce", name: "Hogao (Salsa Criolla)",
            aliases: ["hogao colombiano", "colombian criollo sauce", "salsa criolla hogao"],
            servingLabel: "2 tbsp (30 g)",
            calories: 30, proteinG: 0, carbsG: 3, fatG: 2, fiberG: 1
        ),
        CommonFood(
            id: "sweet-relish", name: "Sweet relish",
            // USDA FDC #168550
            aliases: ["sweet pickle relish", "hot dog relish", "sweet cucumber relish"],
            servingLabel: "1 tbsp (15 g)",
            calories: 20, proteinG: 0, carbsG: 5, fatG: 0, fiberG: 0
        ),
        CommonFood(
            id: "tartar-sauce", name: "Tartar sauce",
            // USDA FDC #173595
            aliases: ["tartar sauce", "tartare sauce", "fish fry sauce"],
            servingLabel: "2 tbsp (28 g)",
            calories: 140, proteinG: 0, carbsG: 4, fatG: 14, fiberG: 0
        ),
        CommonFood(
            id: "cocktail-sauce", name: "Cocktail sauce",
            aliases: ["shrimp cocktail sauce", "seafood cocktail sauce", "horseradish cocktail sauce"],
            servingLabel: "¼ cup (60 g)",
            calories: 80, proteinG: 1, carbsG: 19, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "buffalo-wing-sauce", name: "Buffalo wing sauce",
            // Frank's RedHot official
            aliases: ["buffalo wing sauce", "frank's buffalo sauce", "hot wing sauce"],
            servingLabel: "2 tbsp (30 g)",
            calories: 30, proteinG: 0, carbsG: 1, fatG: 3, fiberG: 0
        ),
        CommonFood(
            id: "honey-mustard", name: "Honey mustard",
            aliases: ["honey mustard sauce", "honey mustard dressing", "honey dijon dip"],
            servingLabel: "2 tbsp (30 g)",
            calories: 100, proteinG: 0, carbsG: 8, fatG: 8, fiberG: 0
        ),
        CommonFood(
            id: "thousand-island-dressing", name: "Thousand Island dressing",
            // USDA FDC #171428
            aliases: ["thousand island dressing", "1000 island dressing", "thousand island sauce"],
            servingLabel: "2 tbsp (30 g)",
            calories: 110, proteinG: 0, carbsG: 5, fatG: 10, fiberG: 0
        ),
        CommonFood(
            id: "blue-cheese-dressing", name: "Blue cheese dressing",
            // USDA FDC #167659
            aliases: ["blue cheese dressing", "bleu cheese dressing", "chunky blue cheese dip"],
            servingLabel: "2 tbsp (30 g)",
            calories: 150, proteinG: 1, carbsG: 2, fatG: 16, fiberG: 0
        ),
        CommonFood(
            id: "chimichurri", name: "Chimichurri sauce",
            aliases: ["chimichurri sauce", "argentinian chimichurri", "parsley garlic sauce"],
            servingLabel: "2 tbsp (30 g)",
            calories: 120, proteinG: 0, carbsG: 1, fatG: 13, fiberG: 0
        ),
        CommonFood(
            id: "hummus-roasted-red-pepper", name: "Roasted red pepper hummus",
            aliases: ["roasted red pepper hummus", "red pepper hummus"],
            servingLabel: "2 tbsp (30 g)",
            calories: 70, proteinG: 2, carbsG: 5, fatG: 5, fiberG: 2
        ),
        CommonFood(
            id: "hummus-garlic", name: "Roasted garlic hummus",
            aliases: ["garlic hummus", "roasted garlic hummus"],
            servingLabel: "2 tbsp (30 g)",
            calories: 70, proteinG: 2, carbsG: 5, fatG: 5, fiberG: 2
        ),
        CommonFood(
            id: "spinach-artichoke-dip", name: "Spinach artichoke dip",
            aliases: ["spinach artichoke dip", "spinach dip", "artichoke dip"],
            servingLabel: "1/4 cup (60 g)",
            calories: 150, proteinG: 4, carbsG: 6, fatG: 12, fiberG: 1
        ),

    ]

    // MARK: - Deli, Sandwiches & Bowls

    private static let deli: [CommonFood] = [
        // — Sandwiches
        CommonFood(
            id: "sandwich-italian-sub", name: "Italian sub",
            // USDA SR Legacy + Subway 6\" Italian BMT reference
            aliases: ["italian sub", "italian hoagie", "hoagie", "sub sandwich", "hero sandwich", "italian hero"],
            servingLabel: "1 6\" sub (220 g)",
            calories: 450, proteinG: 22, carbsG: 42, fatG: 20, fiberG: 3
        ),
        CommonFood(
            id: "sandwich-philly-cheesesteak", name: "Philly cheesesteak",
            // USDA SR Legacy restaurant cheesesteak estimate
            aliases: ["philly cheesesteak", "cheesesteak", "philly steak sandwich", "cheesesteak sandwich"],
            servingLabel: "1 sandwich (250 g)",
            calories: 540, proteinG: 32, carbsG: 46, fatG: 22, fiberG: 2
        ),
        CommonFood(
            id: "sandwich-meatball-sub", name: "Meatball sub",
            // Subway official meatball marinara 6\"
            aliases: ["meatball sub", "meatball sandwich", "meatball hero", "meatball marinara sub"],
            servingLabel: "1 6\" sub (250 g)",
            calories: 480, proteinG: 22, carbsG: 52, fatG: 18, fiberG: 4
        ),
        CommonFood(
            id: "sandwich-tuna-salad", name: "Tuna salad sandwich",
            // USDA FDC #172960
            aliases: ["tuna salad sandwich", "tuna sandwich", "tuna sub", "tuna melt", "tuna on bread"],
            servingLabel: "1 sandwich (220 g)",
            calories: 390, proteinG: 24, carbsG: 38, fatG: 14, fiberG: 3
        ),
        CommonFood(
            id: "sandwich-egg-salad", name: "Egg salad sandwich",
            // USDA FDC #172958
            aliases: ["egg salad sandwich", "egg salad on bread", "egg mayo sandwich"],
            servingLabel: "1 sandwich (190 g)",
            calories: 340, proteinG: 14, carbsG: 34, fatG: 16, fiberG: 2
        ),
        CommonFood(
            id: "sandwich-chicken-salad", name: "Chicken salad sandwich",
            aliases: ["chicken salad sandwich", "chicken salad on bread", "chicken mayo sandwich"],
            servingLabel: "1 sandwich (220 g)",
            calories: 360, proteinG: 20, carbsG: 36, fatG: 14, fiberG: 2
        ),
        CommonFood(
            id: "sandwich-pbj", name: "PB&J sandwich",
            // USDA FDC #172959 (2 slices white bread + 2 tbsp PB + 1 tbsp jam)
            aliases: ["pbj", "pb and j", "peanut butter and jelly", "peanut butter jelly sandwich", "pb&j"],
            servingLabel: "1 sandwich (120 g)",
            calories: 380, proteinG: 12, carbsG: 48, fatG: 16, fiberG: 3
        ),
        CommonFood(
            id: "sandwich-grilled-chicken-wrap", name: "Grilled chicken wrap",
            aliases: ["grilled chicken wrap", "chicken wrap", "chicken caesar wrap", "chicken lettuce wrap"],
            servingLabel: "1 wrap (280 g)",
            calories: 420, proteinG: 32, carbsG: 40, fatG: 14, fiberG: 4
        ),
        CommonFood(
            id: "sandwich-ham-swiss", name: "Ham and Swiss on rye",
            aliases: ["ham and swiss", "ham swiss sandwich", "ham on rye", "ham cheese sandwich", "ham swiss rye"],
            servingLabel: "1 sandwich (180 g)",
            calories: 360, proteinG: 22, carbsG: 34, fatG: 14, fiberG: 3
        ),
        CommonFood(
            id: "sandwich-roast-beef", name: "Roast beef sandwich",
            aliases: ["roast beef sandwich", "roast beef sub", "roast beef on roll", "roast beef and cheddar", "roast beef hero"],
            servingLabel: "1 sandwich (220 g)",
            calories: 400, proteinG: 28, carbsG: 38, fatG: 14, fiberG: 2
        ),
        CommonFood(
            id: "sandwich-caprese-panini", name: "Caprese panini",
            aliases: ["caprese panini", "mozzarella tomato panini", "tomato basil panini", "caprese sandwich"],
            servingLabel: "1 panini (200 g)",
            calories: 380, proteinG: 16, carbsG: 40, fatG: 18, fiberG: 3
        ),
        CommonFood(
            id: "sandwich-veggie-wrap", name: "Veggie wrap",
            aliases: ["veggie wrap", "vegetable wrap", "hummus veggie wrap", "veggie sandwich"],
            servingLabel: "1 wrap (260 g)",
            calories: 320, proteinG: 12, carbsG: 50, fatG: 10, fiberG: 8
        ),
        CommonFood(
            id: "sandwich-breakfast", name: "Breakfast sandwich",
            aliases: ["breakfast sandwich", "egg and cheese sandwich", "egg cheese bacon sandwich", "sausage egg muffin", "egg mcmuffin style"],
            servingLabel: "1 sandwich (egg + cheese + meat, 180 g)",
            calories: 440, proteinG: 22, carbsG: 36, fatG: 22, fiberG: 1
        ),
        CommonFood(
            id: "sandwich-turkey-avocado", name: "Turkey avocado sandwich",
            aliases: ["turkey avocado sandwich", "turkey avocado", "turkey avo sandwich", "turkey avocado blt"],
            servingLabel: "1 sandwich (230 g)",
            calories: 420, proteinG: 24, carbsG: 38, fatG: 18, fiberG: 6
        ),
        CommonFood(
            id: "wrap-chicken-bacon-ranch", name: "Chicken bacon ranch wrap",
            aliases: ["chicken bacon ranch wrap", "cbr wrap", "chicken ranch wrap", "bacon ranch chicken wrap"],
            servingLabel: "1 wrap (300 g)",
            calories: 580, proteinG: 38, carbsG: 44, fatG: 22, fiberG: 3
        ),
        CommonFood(
            id: "sandwich-lobster-roll", name: "Lobster roll",
            aliases: ["lobster roll", "maine lobster roll", "connecticut lobster roll", "new england lobster roll"],
            servingLabel: "1 roll (180 g)",
            calories: 400, proteinG: 22, carbsG: 36, fatG: 18, fiberG: 1
        ),
        CommonFood(
            id: "sandwich-po-boy", name: "Shrimp po' boy",
            aliases: ["po boy", "po' boy", "shrimp po boy", "oyster po boy", "new orleans po boy", "louisiana po boy"],
            servingLabel: "1 sandwich (250 g)",
            calories: 455, proteinG: 20, carbsG: 54, fatG: 16, fiberG: 3
        ),
        CommonFood(
            id: "sandwich-french-dip", name: "French dip",
            aliases: ["french dip", "french dip sandwich", "roast beef french dip", "au jus sandwich"],
            servingLabel: "1 sandwich with au jus (260 g)",
            calories: 470, proteinG: 34, carbsG: 44, fatG: 14, fiberG: 2
        ),
        CommonFood(
            id: "sandwich-croque-monsieur", name: "Croque Monsieur",
            aliases: ["croque monsieur", "croque madame", "french grilled cheese", "french ham cheese toasted"],
            servingLabel: "1 sandwich (200 g)",
            calories: 520, proteinG: 28, carbsG: 38, fatG: 28, fiberG: 2
        ),
        CommonFood(
            id: "sandwich-monte-cristo", name: "Monte Cristo sandwich",
            aliases: ["monte cristo", "monte cristo sandwich", "battered ham cheese sandwich", "deep fried sandwich"],
            servingLabel: "1 sandwich (220 g)",
            calories: 570, proteinG: 28, carbsG: 46, fatG: 28, fiberG: 2
        ),
        CommonFood(
            id: "sandwich-patty-melt", name: "Patty melt",
            aliases: ["patty melt", "beef patty melt", "patty melt on rye", "rye patty melt"],
            servingLabel: "1 sandwich (280 g)",
            calories: 660, proteinG: 34, carbsG: 44, fatG: 38, fiberG: 3
        ),
        CommonFood(
            id: "sandwich-torta", name: "Torta",
            aliases: ["torta", "mexican torta", "torta sandwich", "torta de milanesa", "torta ahogada"],
            servingLabel: "1 sandwich (280 g)",
            calories: 540, proteinG: 28, carbsG: 52, fatG: 22, fiberG: 4
        ),
        CommonFood(
            id: "sandwich-katsu-sando", name: "Katsu sando",
            aliases: ["katsu sando", "japanese katsu sandwich", "tonkatsu sandwich", "chicken katsu sandwich", "katsu sandwich"],
            servingLabel: "1 sandwich (220 g)",
            calories: 540, proteinG: 26, carbsG: 52, fatG: 22, fiberG: 3
        ),
        // — Deli salads (by the scoop / side)
        CommonFood(
            id: "deli-tuna-salad", name: "Tuna salad (deli scoop)",
            // USDA FDC #172960
            aliases: ["tuna salad", "deli tuna salad", "tuna mayo", "tuna salad scoop"],
            servingLabel: "½ cup (113 g)",
            calories: 190, proteinG: 16, carbsG: 2, fatG: 12, fiberG: 0
        ),
        CommonFood(
            id: "deli-chicken-salad", name: "Chicken salad (deli scoop)",
            aliases: ["chicken salad deli", "deli chicken salad", "chicken mayo scoop"],
            servingLabel: "½ cup (113 g)",
            calories: 210, proteinG: 14, carbsG: 4, fatG: 14, fiberG: 0
        ),
        CommonFood(
            id: "deli-egg-salad", name: "Egg salad (deli scoop)",
            aliases: ["egg salad deli", "deli egg salad", "egg mayo scoop"],
            servingLabel: "½ cup (113 g)",
            calories: 210, proteinG: 10, carbsG: 3, fatG: 18, fiberG: 0
        ),
        CommonFood(
            id: "deli-macaroni-salad", name: "Deli macaroni salad",
            // USDA FDC #172962
            aliases: ["deli macaroni salad", "cold macaroni salad", "mayo macaroni salad"],
            servingLabel: "½ cup (113 g)",
            calories: 180, proteinG: 3, carbsG: 22, fatG: 9, fiberG: 1
        ),
        CommonFood(
            id: "deli-potato-salad-mustard", name: "Deli mustard potato salad",
            aliases: ["mustard potato salad", "deli potato salad", "german potato salad"],
            servingLabel: "½ cup (113 g)",
            calories: 140, proteinG: 3, carbsG: 22, fatG: 5, fiberG: 2
        ),
        // — Grain & power bowls
        CommonFood(
            id: "bowl-mediterranean", name: "Mediterranean grain bowl",
            aliases: ["mediterranean bowl", "mediterranean grain bowl", "mediterranean quinoa bowl", "greek grain bowl"],
            servingLabel: "1 bowl (quinoa + hummus + roasted veggies + feta, 400 g)",
            calories: 480, proteinG: 18, carbsG: 60, fatG: 18, fiberG: 10
        ),
        CommonFood(
            id: "bowl-buddha", name: "Buddha bowl",
            aliases: ["buddha bowl", "nourish bowl", "grain bowl", "power bowl", "rainbow bowl"],
            servingLabel: "1 bowl (grains + roasted veggies + tahini dressing, 400 g)",
            calories: 450, proteinG: 16, carbsG: 62, fatG: 18, fiberG: 12
        ),
        CommonFood(
            id: "bowl-macro", name: "Macro bowl",
            aliases: ["macro bowl", "macro plate", "meal prep bowl", "fitness bowl"],
            servingLabel: "1 bowl (rice + grilled chicken + veggies, 400 g)",
            calories: 520, proteinG: 42, carbsG: 52, fatG: 12, fiberG: 6
        ),
        CommonFood(
            id: "bowl-greek", name: "Greek bowl",
            aliases: ["greek bowl", "greek rice bowl", "greek chicken bowl"],
            servingLabel: "1 bowl (rice + chicken + cucumber + tzatziki, 380 g)",
            calories: 460, proteinG: 34, carbsG: 50, fatG: 14, fiberG: 4
        ),
        CommonFood(
            id: "bowl-falafel-grain", name: "Falafel grain bowl",
            aliases: ["falafel bowl", "falafel grain bowl", "falafel rice bowl", "falafel and grains"],
            servingLabel: "1 bowl (falafel + quinoa + salad + tahini, 400 g)",
            calories: 550, proteinG: 18, carbsG: 68, fatG: 22, fiberG: 12
        ),
        CommonFood(
            id: "bowl-salmon-rice", name: "Salmon rice bowl",
            aliases: ["salmon rice bowl", "salmon bowl", "grilled salmon bowl"],
            servingLabel: "1 bowl (salmon + rice + veggies, 380 g)",
            calories: 540, proteinG: 36, carbsG: 52, fatG: 18, fiberG: 4
        ),
        CommonFood(
            id: "deli-broccoli-salad", name: "Broccoli salad (deli)",
            aliases: ["broccoli bacon salad", "broccoli cheddar salad", "creamy broccoli salad"],
            servingLabel: "½ cup (90 g)",
            calories: 200, proteinG: 4, carbsG: 14, fatG: 15, fiberG: 3
        ),
        CommonFood(
            id: "deli-three-bean-salad", name: "Three-bean salad (deli)",
            // USDA FDC #173017
            aliases: ["three bean salad", "marinated bean salad", "sweet and sour bean salad"],
            servingLabel: "½ cup (130 g)",
            calories: 130, proteinG: 4, carbsG: 23, fatG: 3, fiberG: 5
        ),
        CommonFood(
            id: "deli-ambrosia-salad", name: "Ambrosia salad (deli)",
            aliases: ["ambrosia fruit salad", "marshmallow fruit salad", "coconut fruit salad"],
            servingLabel: "½ cup (130 g)",
            calories: 200, proteinG: 2, carbsG: 30, fatG: 9, fiberG: 2
        ),
        CommonFood(
            id: "deli-seven-layer-salad", name: "Seven-layer salad (deli)",
            aliases: ["seven layer salad", "layered pea salad", "7 layer party salad"],
            servingLabel: "1 cup (150 g)",
            calories: 230, proteinG: 7, carbsG: 11, fatG: 18, fiberG: 2
        ),
    ]

    // MARK: - Sushi & Japanese extras

    private static let sushiExtended: [CommonFood] = [
        // — Rolls (maki / uramaki)
        CommonFood(
            id: "sushi-spicy-tuna-roll", name: "Spicy tuna roll",
            // USDA FDC #170379
            aliases: ["spicy tuna roll", "spicy tuna", "spicy tuna maki", "spicy tuna sushi"],
            servingLabel: "1 roll / 8 pieces (220 g)",
            calories: 290, proteinG: 20, carbsG: 32, fatG: 8, fiberG: 1
        ),
        CommonFood(
            id: "sushi-dragon-roll", name: "Dragon roll",
            aliases: ["dragon roll", "sushi dragon roll", "avocado shrimp roll"],
            servingLabel: "1 roll / 8 pieces (250 g)",
            calories: 420, proteinG: 18, carbsG: 48, fatG: 14, fiberG: 3
        ),
        CommonFood(
            id: "sushi-spider-roll", name: "Spider roll",
            aliases: ["spider roll", "soft shell crab roll", "spider sushi roll"],
            servingLabel: "1 roll / 8 pieces (240 g)",
            calories: 380, proteinG: 16, carbsG: 44, fatG: 14, fiberG: 2
        ),
        CommonFood(
            id: "sushi-rainbow-roll", name: "Rainbow roll",
            aliases: ["rainbow roll", "sushi rainbow roll", "rainbow sushi"],
            servingLabel: "1 roll / 8 pieces (270 g)",
            calories: 360, proteinG: 22, carbsG: 42, fatG: 10, fiberG: 2
        ),
        CommonFood(
            id: "sushi-shrimp-tempura-roll", name: "Shrimp tempura roll",
            aliases: ["shrimp tempura roll", "tempura shrimp roll", "shrimp tempura maki"],
            servingLabel: "1 roll / 8 pieces (240 g)",
            calories: 400, proteinG: 16, carbsG: 50, fatG: 14, fiberG: 2
        ),
        CommonFood(
            id: "sushi-philadelphia-roll", name: "Philadelphia roll",
            aliases: ["philadelphia roll", "philly roll", "cream cheese salmon roll", "philly sushi"],
            servingLabel: "1 roll / 8 pieces (230 g)",
            calories: 380, proteinG: 16, carbsG: 40, fatG: 16, fiberG: 2
        ),
        CommonFood(
            id: "sushi-tuna-roll", name: "Tuna roll (tekka maki)",
            // USDA FDC #170381
            aliases: ["tuna roll", "tekka maki", "tuna maki", "tuna sushi roll"],
            servingLabel: "1 roll / 6 pieces (140 g)",
            calories: 190, proteinG: 16, carbsG: 26, fatG: 2, fiberG: 1
        ),
        CommonFood(
            id: "sushi-cucumber-roll", name: "Cucumber roll (kappa maki)",
            // USDA FDC #170380
            aliases: ["cucumber roll", "kappa maki", "cucumber maki", "avocado roll", "avocado maki"],
            servingLabel: "1 roll / 6 pieces (120 g)",
            calories: 130, proteinG: 2, carbsG: 28, fatG: 0, fiberG: 1
        ),
        CommonFood(
            id: "sushi-volcano-roll", name: "Volcano roll",
            aliases: ["volcano roll", "baked sushi roll", "baked volcano roll"],
            servingLabel: "1 roll / 8 pieces (250 g)",
            calories: 430, proteinG: 18, carbsG: 46, fatG: 18, fiberG: 2
        ),
        CommonFood(
            id: "sushi-caterpillar-roll", name: "Caterpillar roll",
            aliases: ["caterpillar roll", "eel avocado roll", "unagi avocado roll"],
            servingLabel: "1 roll / 8 pieces (250 g)",
            calories: 400, proteinG: 16, carbsG: 48, fatG: 14, fiberG: 3
        ),
        // — Nigiri
        CommonFood(
            id: "sushi-nigiri-salmon", name: "Salmon nigiri",
            // USDA SR Legacy sushi restaurant estimate
            aliases: ["salmon nigiri", "sake nigiri", "nigiri salmon"],
            servingLabel: "2 pieces (80 g)",
            calories: 130, proteinG: 10, carbsG: 16, fatG: 4, fiberG: 0
        ),
        CommonFood(
            id: "sushi-nigiri-tuna", name: "Tuna nigiri",
            aliases: ["tuna nigiri", "maguro nigiri", "nigiri tuna"],
            servingLabel: "2 pieces (80 g)",
            calories: 120, proteinG: 12, carbsG: 16, fatG: 2, fiberG: 0
        ),
        CommonFood(
            id: "sushi-nigiri-shrimp", name: "Shrimp nigiri",
            aliases: ["shrimp nigiri", "ebi nigiri", "nigiri shrimp"],
            servingLabel: "2 pieces (80 g)",
            calories: 110, proteinG: 8, carbsG: 16, fatG: 1, fiberG: 0
        ),
        CommonFood(
            id: "sushi-nigiri-eel", name: "Eel nigiri (unagi)",
            aliases: ["eel nigiri", "unagi nigiri", "eel sushi", "unagi sushi"],
            servingLabel: "2 pieces (80 g)",
            calories: 150, proteinG: 10, carbsG: 18, fatG: 4, fiberG: 0
        ),
        // — Sashimi
        CommonFood(
            id: "sashimi-salmon", name: "Salmon sashimi",
            aliases: ["salmon sashimi", "sashimi salmon", "sake sashimi"],
            servingLabel: "5 pieces (100 g)",
            calories: 170, proteinG: 20, carbsG: 0, fatG: 10, fiberG: 0
        ),
        CommonFood(
            id: "sashimi-tuna", name: "Tuna sashimi",
            aliases: ["tuna sashimi", "sashimi tuna", "maguro sashimi"],
            servingLabel: "5 pieces (100 g)",
            calories: 130, proteinG: 28, carbsG: 0, fatG: 1, fiberG: 0
        ),
        CommonFood(
            id: "sashimi-yellowtail", name: "Yellowtail sashimi",
            aliases: ["yellowtail sashimi", "hamachi sashimi", "yellowtail sushi"],
            servingLabel: "5 pieces (100 g)",
            calories: 180, proteinG: 20, carbsG: 0, fatG: 10, fiberG: 0
        ),
        // — Bowls & sets
        CommonFood(
            id: "sushi-chirashi-bowl", name: "Chirashi bowl",
            aliases: ["chirashi", "chirashi bowl", "chirashi sushi", "scattered sushi", "chirashi don"],
            servingLabel: "1 bowl (rice + assorted sashimi, 350 g)",
            calories: 540, proteinG: 34, carbsG: 56, fatG: 16, fiberG: 2
        ),
        CommonFood(
            id: "sushi-unagi-don", name: "Unagi don",
            aliases: ["unagi don", "eel rice bowl", "unagi rice", "eel don", "unadon"],
            servingLabel: "1 bowl (300 g)",
            calories: 490, proteinG: 22, carbsG: 64, fatG: 14, fiberG: 1
        ),
        CommonFood(
            id: "sushi-hand-roll", name: "Hand roll (temaki)",
            aliases: ["hand roll", "temaki", "sushi hand roll", "cone sushi", "temaki cone"],
            servingLabel: "1 cone (80 g)",
            calories: 150, proteinG: 8, carbsG: 22, fatG: 4, fiberG: 1
        ),
        // — Starters
        CommonFood(
            id: "sushi-agedashi-tofu", name: "Agedashi tofu",
            aliases: ["agedashi tofu", "agedashi", "fried tofu japanese", "deep fried tofu broth"],
            servingLabel: "1 serving (3 pieces, 150 g)",
            calories: 160, proteinG: 8, carbsG: 16, fatG: 8, fiberG: 1
        ),
        CommonFood(
            id: "sushi-gyoza-restaurant", name: "Gyoza (restaurant, pan-fried)",
            // USDA SR Legacy restaurant potsticker estimate; distinct from the preparedMeals generic
            aliases: ["japanese gyoza", "pan fried gyoza", "restaurant gyoza", "yaki gyoza"],
            servingLabel: "5 pieces (120 g, pan-fried)",
            calories: 270, proteinG: 12, carbsG: 30, fatG: 10, fiberG: 2
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
