import XCTest

final class FoodParserTests: XCTestCase {

    // Empty DB → exercises the curated-only path (matches the hostless runtime,
    // where Bundle.main carries no resource).
    private let emptyDB = FoodDatabase(entries: [])

    // MARK: - Curated CommonFoods still parse correctly

    func test_curated_singleFood_resolves() {
        let r = FoodParser.parse(text: "grilled chicken", database: emptyDB)
        XCTAssertTrue(r.hasMatches)
        XCTAssertEqual(r.recognized.first?.food.id, "chicken-breast")
    }

    func test_curated_multipleFoods_combine() {
        let r = FoodParser.parse(text: "a bowl of rice and some grilled chicken", database: emptyDB)
        let ids = r.recognized.map(\.food.id)
        XCTAssertTrue(ids.contains("rice-white"))
        XCTAssertTrue(ids.contains("chicken-breast"))
        XCTAssertEqual(r.totalPerServing.calories,
                       r.recognized.reduce(0) { $0 + $1.scaledCalories })
    }

    // New CommonFoods entries added with this feature.
    func test_newCommonFoods_parse() {
        let cases: [(text: String, id: String)] = [
            ("naan", "naan"),
            ("croissant", "croissant"),
            ("mashed potatoes", "mashed-potato"),
            ("chicken thigh", "chicken-thigh"),
            ("egg whites", "egg-whites"),
            ("brussels sprouts", "brussels-sprouts"),
            ("potato chips", "potato-chips"),
            ("ice cream", "ice-cream"),
            ("latte", "latte"),
            ("protein bar", "protein-bar"),
        ]
        for c in cases {
            let r = FoodParser.parse(text: c.text, database: emptyDB)
            XCTAssertEqual(r.recognized.first?.food.id, c.id,
                           "expected '\(c.text)' → \(c.id)")
        }
    }

    func test_quantityWords_scaleMacros() {
        let one = FoodParser.parse(text: "egg", database: emptyDB)
        let two = FoodParser.parse(text: "two eggs", database: emptyDB)
        XCTAssertEqual(two.recognized.first?.scaledCalories,
                       (one.recognized.first?.scaledCalories ?? 0) * 2)
    }

    // MARK: - Merged resolution order

    private func dbWithUSDAOnly() -> FoodDatabase {
        FoodDatabase(entries: [
            // A food NOT in CommonFoods → should resolve only via the DB.
            FoodDatabaseEntry(
                id: "usda-test-okra", name: "Okra",
                aliases: ["okra", "ladies fingers"],
                servingLabel: "1 cup (100 g)",
                calories: 33, proteinG: 2, carbsG: 7, fatG: 0, fiberG: 3
            ),
            // A food that COLLIDES with a curated entry by alias ("chicken").
            // The curated entry must win regardless of this being present.
            FoodDatabaseEntry(
                id: "usda-test-chicken", name: "USDA chicken stand-in",
                aliases: ["chicken"],
                servingLabel: "100 g",
                calories: 999, proteinG: 1, carbsG: 1, fatG: 1, fiberG: 1
            ),
        ])
    }

    func test_usdaOnlyFood_resolvesViaDatabase() {
        let r = FoodParser.parse(text: "some okra", database: dbWithUSDAOnly())
        XCTAssertEqual(r.recognized.first?.food.id, "usda-test-okra")
        XCTAssertEqual(r.recognized.first?.scaledCalories, 33)
    }

    func test_curatedWins_overUSDAonCollision() {
        // "chicken" exists in both; the curated CommonFoods entry must win, so
        // the bogus 999-cal USDA stand-in is never chosen.
        let r = FoodParser.parse(text: "grilled chicken", database: dbWithUSDAOnly())
        XCTAssertEqual(r.recognized.first?.food.id, "chicken-breast")
        XCTAssertNotEqual(r.recognized.first?.scaledCalories, 999)
    }

    func test_curatedAndUSDA_mixInOneMeal() {
        let r = FoodParser.parse(text: "grilled chicken and some okra", database: dbWithUSDAOnly())
        let ids = r.recognized.map(\.food.id)
        XCTAssertTrue(ids.contains("chicken-breast"))   // curated
        XCTAssertTrue(ids.contains("usda-test-okra"))   // USDA fallback
    }

    func test_unknownFood_isUnrecognized() {
        let r = FoodParser.parse(text: "xyzzy goop", database: emptyDB)
        XCTAssertFalse(r.hasMatches)
        XCTAssertFalse(r.unrecognized.isEmpty)
    }
}
