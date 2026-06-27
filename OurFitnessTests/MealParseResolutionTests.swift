import XCTest

// The on-device AI parser (Services/MealParseService) only produces TEXT items;
// the deterministic resolution + scaling lives in FoodParser.resolve(items:).
// That bridge is pure and DB-injectable, so we test it here without
// FoundationModels (the model call itself isn't unit-testable). These tests pin
// the SAFETY contract: every number comes from the food database, AI-supplied
// names that don't resolve are unrecognised, and scaling matches the string path.
final class MealParseResolutionTests: XCTestCase {

    // Empty DB → curated-only path (mirrors the hostless runtime: no bundled resource).
    private let emptyDB = FoodDatabase(entries: [])

    private func items(_ pairs: [(String, Double)]) -> [FoodParser.ExtractedItem] {
        pairs.map { FoodParser.ExtractedItem(name: $0.0, quantity: $0.1) }
    }

    func test_resolve_singleCuratedItem() {
        let r = FoodParser.resolve(items: items([("grilled chicken", 1)]), database: emptyDB)
        XCTAssertTrue(r.hasMatches)
        XCTAssertEqual(r.recognized.first?.food.id, "chicken-breast")
    }

    func test_resolve_quantityScalesLikeStringParser() {
        let one = FoodParser.resolve(items: items([("egg", 1)]), database: emptyDB)
        let two = FoodParser.resolve(items: items([("egg", 2)]), database: emptyDB)
        XCTAssertEqual(two.recognized.first?.scaledCalories,
                       (one.recognized.first?.scaledCalories ?? 0) * 2)
        XCTAssertEqual(two.recognized.first?.quantity, 2)
    }

    func test_resolve_fractionalQuantity() {
        let half = FoodParser.resolve(items: items([("white rice", 0.5)]), database: emptyDB)
        let full = FoodParser.resolve(items: items([("white rice", 1)]), database: emptyDB)
        let halfCal = half.recognized.first?.scaledCalories ?? 0
        let fullCal = full.recognized.first?.scaledCalories ?? 0
        XCTAssertLessThan(halfCal, fullCal)
    }

    func test_resolve_multipleItemsCombineTotals() {
        let r = FoodParser.resolve(items: items([("rice", 1), ("grilled chicken", 1)]), database: emptyDB)
        let ids = r.recognized.map(\.food.id)
        XCTAssertTrue(ids.contains("rice-white"))
        XCTAssertTrue(ids.contains("chicken-breast"))
        XCTAssertEqual(r.totalPerServing.calories,
                       r.recognized.reduce(0) { $0 + $1.scaledCalories })
    }

    // SAFETY: a name the AI extracts that isn't in the DB must be unrecognised,
    // never fabricated into macros.
    func test_resolve_unknownItem_isUnrecognized_notInvented() {
        let r = FoodParser.resolve(items: items([("xyzzy goop", 2)]), database: emptyDB)
        XCTAssertFalse(r.hasMatches)
        XCTAssertEqual(r.unrecognized, ["xyzzy goop"])
        XCTAssertEqual(r.totalPerServing.calories, 0)
    }

    func test_resolve_mixesRecognizedAndUnrecognized() {
        let r = FoodParser.resolve(items: items([("grilled chicken", 1), ("xyzzy goop", 1)]), database: emptyDB)
        XCTAssertEqual(r.recognized.first?.food.id, "chicken-breast")
        XCTAssertEqual(r.unrecognized, ["xyzzy goop"])
    }

    func test_resolve_usdaFallbackUsesDatabaseNumbers() {
        let db = FoodDatabase(entries: [
            FoodDatabaseEntry(
                id: "usda-test-veg", name: "Synthveg",
                aliases: ["synthveg"], servingLabel: "1 cup (100 g)",
                calories: 33, proteinG: 2, carbsG: 7, fatG: 0, fiberG: 3
            ),
        ])
        let r = FoodParser.resolve(items: items([("synthveg", 1)]), database: db)
        XCTAssertEqual(r.recognized.first?.food.id, "usda-test-veg")
        XCTAssertEqual(r.recognized.first?.scaledCalories, 33)
    }

    func test_resolve_zeroQuantity_clampsToOne() {
        let r = FoodParser.resolve(items: items([("egg", 0)]), database: emptyDB)
        let one = FoodParser.resolve(items: items([("egg", 1)]), database: emptyDB)
        XCTAssertEqual(r.recognized.first?.scaledCalories, one.recognized.first?.scaledCalories)
    }

    func test_resolve_dropsBlankAndOneCharNames() {
        let r = FoodParser.resolve(items: items([("", 1), ("x", 1)]), database: emptyDB)
        XCTAssertTrue(r.recognized.isEmpty)
        XCTAssertTrue(r.unrecognized.isEmpty)
    }
}
