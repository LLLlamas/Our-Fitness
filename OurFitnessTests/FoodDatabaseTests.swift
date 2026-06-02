import XCTest

final class FoodDatabaseTests: XCTestCase {

    // MARK: - Graceful degradation (no bundled resource in the hostless target)

    func test_loadBundled_missingResource_returnsEmptyDatabase() {
        // The hostless test target ships no app bundle resource. Loading must
        // never crash — it degrades to an empty database.
        let db = FoodDatabase.loadBundled(bundle: Bundle(for: FoodDatabaseTests.self))
        XCTAssertTrue(db.isEmpty)
        XCTAssertNil(db.bestMatch(in: "anything at all"))
    }

    func test_shared_isUsableEvenWithoutResource() {
        // `.shared` reads Bundle.main; in tests that has no resource, so it must
        // be a valid (likely empty) database, not a crash. Just touching it and
        // querying it must be safe.
        let db = FoodDatabase.shared
        _ = db.bestMatch(in: "rice")
        _ = db.entries.count
    }

    // MARK: - Pure matching (no bundle required)

    private func sampleDB() -> FoodDatabase {
        FoodDatabase(entries: [
            FoodDatabaseEntry(
                id: "usda-test-tilapia", name: "Tilapia",
                aliases: ["tilapia", "grilled tilapia"],
                servingLabel: "4 oz (113 g)",
                calories: 145, proteinG: 30, carbsG: 0, fatG: 3, fiberG: 0
            ),
            FoodDatabaseEntry(
                id: "usda-test-kiwi", name: "Kiwi",
                aliases: ["kiwi", "kiwifruit"],
                servingLabel: "1 medium (69 g)",
                calories: 42, proteinG: 1, carbsG: 10, fatG: 0, fiberG: 2
            ),
        ])
    }

    func test_bestMatch_findsBySubstring() {
        let entry = sampleDB().bestMatch(in: "i had some grilled tilapia for dinner")
        XCTAssertEqual(entry?.id, "usda-test-tilapia")
    }

    func test_bestMatch_prefersLongerAlias() {
        // "grilled tilapia" (15) should win over the bare "tilapia" (7) alias.
        let entry = sampleDB().bestMatch(in: "grilled tilapia")
        XCTAssertEqual(entry?.name, "Tilapia")
    }

    func test_bestMatch_noMatch_returnsNil() {
        XCTAssertNil(sampleDB().bestMatch(in: "a giant slice of cardboard"))
    }

    func test_asCommonFood_preservesMacros() {
        let common = sampleDB().entries[0].asCommonFood
        XCTAssertEqual(common.calories, 145)
        XCTAssertEqual(common.proteinG, 30)
        XCTAssertEqual(common.aliases, ["tilapia", "grilled tilapia"])
    }
}
