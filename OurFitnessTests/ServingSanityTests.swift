import XCTest

/// `ServingSanity` (USDA label/name tidy-up, bulk + label ranking) and
/// `FoodSearch.merged` bands, on hand-made rows.
final class ServingSanityTests: XCTestCase {

    private func food(_ id: String, _ name: String, aliases: [String] = [], label: String = "1 cup") -> CommonFood {
        CommonFood(id: id, name: name, aliases: aliases, servingLabel: label,
                   calories: 100, proteinG: 1, carbsG: 1, fatG: 1, fiberG: 0)
    }

    func testHumanizedLabels() {
        XCTAssertEqual(ServingSanity.humanizedLabel("40GRM"), "40 g")
        XCTAssertEqual(ServingSanity.humanizedLabel("4 ONZ"), "4 oz")
        XCTAssertEqual(ServingSanity.humanizedLabel("8 OZA"), "8 fl oz")
        XCTAssertEqual(ServingSanity.humanizedLabel("1 SLICE"), "1 slice")
        XCTAssertEqual(ServingSanity.humanizedLabel("0.5 cup"), "½ cup")
        XCTAssertEqual(ServingSanity.humanizedLabel("1.25 cup"), "1.25 cup")
        XCTAssertEqual(ServingSanity.humanizedLabel("2 Tbsp"), "2 Tbsp")
    }

    func testGenericRowsGetReadableNamesAndHonestLabels() {
        // Real rows (usda-328637, usda-173884, "Bread, oatmeal").
        let cheddar = ServingSanity.tidied(food("usda-328637", "Cheese", aliases: ["cheese, cheddar", "cheese", "cheddar"], label: "1 oz (28 g)"))
        XCTAssertEqual(cheddar.name, "Cheese, cheddar")
        XCTAssertEqual(cheddar.servingLabel, "1 oz (28 g)")              // keyword names the food: kept
        let cheerios = ServingSanity.tidied(food("usda-173884", "Cereals ready-to-eat",
            aliases: ["cereals ready-to-eat, general mills, cheerios", "cereals ready-to-eat"], label: "1 cup (150 g)"))
        XCTAssertEqual(cheerios.name, "Cereals ready-to-eat, general mills, cheerios")
        XCTAssertEqual(cheerios.servingLabel, "150 g")                   // script fallback: grams only
        let bread = ServingSanity.tidied(food("usda-9", "Bread", aliases: ["bread, oatmeal", "bread"], label: "1 cup cooked (158 g)"))
        XCTAssertEqual(bread.servingLabel, "158 g")                      // the oatmeal rule fired on a bread
        XCTAssertEqual(bread.calories, 100)                              // numbers untouched
        // Curated / restaurant rows pass through.
        XCTAssertEqual(ServingSanity.tidied(food("banana", "Banana", label: "40GRM")).servingLabel, "40GRM")
    }

    func testBulkAndLabelRank() {
        XCTAssertTrue(ServingSanity.isBulk(food("usda-2236705", "Kellogg Rice Krispies Cereal 22lb 1ct", label: "100 grams")))
        XCTAssertTrue(ServingSanity.isBulk(food("usda-2", "Store Granola", label: "100 g")))
        XCTAssertFalse(ServingSanity.isBulk(food("usda-1912508", "Rice Krispies Toasted Rice Cereal", label: "1.25 cup")))
        XCTAssertFalse(ServingSanity.isBulk(food("rest:x:y", "Party Pack 12ct")))   // only USDA rows
        XCTAssertEqual(ServingSanity.labelRank("1.25 cup"), 0)
        XCTAssertEqual(ServingSanity.labelRank("1 slice"), 0)
        XCTAssertEqual(ServingSanity.labelRank("40 g"), 1)
        XCTAssertEqual(ServingSanity.labelRank("1 oz (28 g)"), 1)
        XCTAssertEqual(ServingSanity.labelRank("1/5 package"), 1)
    }

    func testUSDAAliasesNeverMakeAnExactMatch() {
        let q = FoodSearchQuery("cereal")
        let branded = food("usda-5", "All-Bran Buds", aliases: ["all-bran buds", "kellogg", "cereal"])
        XCTAssertEqual(q.tier(of: branded), 3)
        let curated = food("cereal-generic", "Breakfast bowl", aliases: ["cereal"])
        XCTAssertEqual(q.tier(of: curated), 0)
    }

    func testMergedBandsAndFTSTieBreak() {
        let curatedClose = food("c1", "Cereal")
        let curatedLoose = food("c2", "Granola bowl")
        let usdaHoliday = food("usda-10", "Rice Krispies Holiday Colors", label: "40 g")
        let usdaPlain = food("usda-11", "Rice Krispies Toasted Rice Cereal", label: "1.25 cup")
        let usdaBulk = food("usda-12", "Rice Krispies Cereal 22lb 1ct", label: "100 grams")
        let usdaLoose = food("usda-13", "Snack mix")
        let out = FoodSearch.merged(
            curated: [(curatedClose, 0), (curatedLoose, 3)],
            usda: [.init(food: usdaBulk, tier: 1, ftsRank: 0), .init(food: usdaHoliday, tier: 1, ftsRank: 1),
                   .init(food: usdaPlain, tier: 1, ftsRank: 2), .init(food: usdaLoose, tier: 3, ftsRank: 3)])
        // Household label beats a gram-only one at the same tier; bulk last.
        XCTAssertEqual(out.map(\.id), ["c1", "usda-11", "usda-10", "c2", "usda-13", "usda-12"])
    }

    func testTypicalPickIsValidatedAgainstShownResults() {
        let shown = [food("a", "Rice Krispies Holiday Colors"), food("b", "Rice Krispies Toasted Rice Cereal")]
        XCTAssertEqual(ServingPick.validated(choice: 2, servings: 1.4, candidates: shown),
                       ServingPick(foodId: "b", quantity: 1.5))                     // snapped to an allowed amount
        XCTAssertNil(ServingPick.validated(choice: 3, servings: 1, candidates: shown))   // not a shown option
        XCTAssertNil(ServingPick.validated(choice: 0, servings: 1, candidates: shown))
        XCTAssertNil(ServingPick.validated(choice: .min, servings: 1, candidates: shown))   // model output; must not trap
        XCTAssertEqual(ServingPick.validated(choice: 1, servings: 40, candidates: shown)?.quantity, 2)
        XCTAssertEqual(ServingPick.validated(choice: 1, servings: .nan, candidates: shown)?.quantity, 1)

        let pick = ServingPick(foodId: "b", quantity: 1)
        XCTAssertEqual(ServingPick.reordered(shown, pick: pick).map(\.id), ["b", "a"])
        XCTAssertEqual(ServingPick.reordered(shown, pick: ServingPick(foodId: "zzz", quantity: 1)).map(\.id), ["a", "b"])
        XCTAssertEqual(ServingPick.reordered(shown, pick: nil).map(\.id), ["a", "b"])
    }
}
