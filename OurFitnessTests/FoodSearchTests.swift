import XCTest

/// Lenient food search (`Domain/FoodSearch.swift`): case, apostrophes, word
/// order, plurals and spelling variants don't matter; results rank by match
/// quality then A–Z. Curated fixtures only — never the bundled USDA database.
final class FoodSearchTests: XCTestCase {

    private func food(_ id: String, _ name: String, _ aliases: [String] = []) -> CommonFood {
        CommonFood(id: id, name: name, aliases: aliases, servingLabel: "1 serving",
                   calories: 100, proteinG: 1, carbsG: 1, fatG: 1, fiberG: 0)
    }

    private lazy var index = CuratedSearchIndex([
        food("krispy", "Krispy Kreme Original Glazed donut", ["krispy kreme"]),
        food("donut", "Donut", ["doughnut", "glazed donut"]),
        food("dunkin", "Dunkin' glazed donut", ["dunkin donuts glazed"]),
        food("fries", "French fries", ["fries"]),
        food("fried-chicken", "Fried chicken"),
        food("berries", "Mixed berries"),
        food("cookie", "Chocolate chip cookie"),
        food("cfa", "Chick-fil-A sandwich"),
        food("mac", "Mac & cheese", ["macaroni and cheese"]),
        food("rest:in-n-out:cheeseburger", "In-N-Out Cheeseburger"),
        food("rest:shake-shack:cheeseburger", "Shake Shack Cheeseburger"),
        food("double-cheeseburger", "Double cheeseburger"),
    ])

    private func ids(_ query: String) -> [String] {
        index.matches(FoodSearchQuery(query)).map(\.id)
    }

    func testCaseApostrophesAndPluralsAreTheSameSearch() {
        let expected = ["donut", "dunkin", "krispy"]   // exact name first, then A–Z
        XCTAssertEqual(ids("donut"), expected)
        XCTAssertEqual(ids("Donut"), expected)
        XCTAssertEqual(ids("DONUTS"), expected)
        XCTAssertEqual(ids("doughnut"), expected)
        XCTAssertEqual(ids("doughnuts"), expected)
    }

    func testChainPlusFoodMatchesInAnyOrder() {
        XCTAssertEqual(ids("dunkin donut"), ["dunkin"])
        XCTAssertEqual(ids("Dunkin' Donuts"), ["dunkin"])
        XCTAssertEqual(ids("donut dunkin"), ["dunkin"])
    }

    func testSingularFormsNeverPrefixMatch() {
        // "fries" must not reach "fried" through its "frie" form.
        XCTAssertEqual(ids("fries"), ["fries"])
        XCTAssertEqual(ids("fry"), ["fries"])
        XCTAssertEqual(ids("berry"), ["berries"])
        XCTAssertEqual(ids("cookies"), ["cookie"])
    }

    func testStopwordsAndRunTogetherNames() {
        XCTAssertEqual(ids("mac and cheese"), ["mac"])
        XCTAssertEqual(ids("chickfila"), ["cfa"])
        XCTAssertEqual(ids("chick fil a"), ["cfa"])
    }

    func testChainsRareNearNYCSortLastAtSameTier() {
        // All three are tier 2 (word in name, not first). A–Z alone would put
        // In-N-Out before Shake Shack; the regional tie-break moves it last.
        XCTAssertEqual(ids("cheeseburger"),
                       ["double-cheeseburger", "rest:shake-shack:cheeseburger", "rest:in-n-out:cheeseburger"])
        XCTAssertTrue(RegionalChains.isRareNearby(foodId: "rest:in-n-out:double-double"))
        XCTAssertTrue(RegionalChains.isRareNearby(foodId: "ff-innout-double-double"))
        XCTAssertFalse(RegionalChains.isRareNearby(foodId: "rest:dunkin:glazed-donut"))
        XCTAssertFalse(RegionalChains.isRareNearby(foodId: "donut"))
    }

    func testRealCuratedLibraryDonutSearches() {
        let real = CuratedSearchIndex.shared
        for q in ["donut", "Donuts", "doughnut"] {
            let hits = real.matches(FoodSearchQuery(q)).map(\.id)
            XCTAssertEqual(hits.first, "donut", q)
            XCTAssertTrue(hits.contains("ff-dunkin-glazed-donut"), q)
            XCTAssertTrue(hits.contains("ff-krispy-kreme-original"), q)
        }
        // Every Dunkin' donut, A–Z (Boston Kreme before Glazed), and nothing else.
        let dunkin = real.matches(FoodSearchQuery("dunkin donut"))
        XCTAssertTrue(dunkin.map(\.id).contains("ff-dunkin-glazed-donut"))
        XCTAssertTrue(dunkin.allSatisfy { $0.name.lowercased().contains("dunkin") })
        XCTAssertEqual(dunkin.map(\.name), dunkin.map(\.name).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    func testFTSQueryORsSingularsAndSpellingVariants() {
        let fts = FoodSearchQuery("Donuts").ftsQuery
        XCTAssertTrue(fts.contains("\"donut\"*"))
        XCTAssertTrue(fts.contains("\"donuts\"*"))
        XCTAssertTrue(fts.contains("\"doughnut\"*"))
        XCTAssertEqual(FoodSearchQuery("rice").ftsQuery, "\"rice\"*")
    }

    func testRepeatIngredientsKeepPortionsWithFreshIds() {
        let uid = UUID()
        let ing = MealIngredient(foodId: "bagel", name: "Bagel", servingLabel: "1 bagel",
                                 quantity: 1.25, perServing: PerServing(calories: 280, proteinG: 10, carbsG: 55, fatG: 2, fiberG: 2))
        let withIngredients = FoodLogEntryDTO(userId: uid, date: "2026-11-05", slot: .breakfast,
                                              customName: "Bagel", perServing: ing.scaledPerServing,
                                              ingredients: [ing])
        let again = withIngredients.repeatIngredients
        XCTAssertEqual(again.map(\.quantity), [1.25])
        XCTAssertNotEqual(again.first?.id, ing.id)

        let manual = FoodLogEntryDTO(userId: uid, date: "2026-11-05", slot: .lunch, customName: "Slice",
                                     servings: 1.5, perServing: PerServing(calories: 300, proteinG: 12, carbsG: 35, fatG: 12, fiberG: 2))
        let rebuilt = manual.repeatIngredients
        XCTAssertEqual(rebuilt.count, 1)
        XCTAssertEqual(rebuilt[0].quantity, 1.5)
        XCTAssertEqual(rebuilt[0].scaledPerServing.calories, manual.totalNutrition.calories)
    }
}
