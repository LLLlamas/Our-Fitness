import XCTest

/// The must-pass typo queries against the REAL bundled `usda-foods.db` (read
/// from the repo, not the test bundle) and the real curated library. Skipped
/// when the database file isn't where the sources are.
final class FoodSearchRealDataTests: XCTestCase {

    private static let dbPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("OurFitness/Resources/usda-foods.db").path

    private func search(_ query: String) async throws -> FoodSearchOutcome {
        guard FileManager.default.fileExists(atPath: Self.dbPath) else { throw XCTSkip("usda-foods.db not found") }
        let db = SQLiteFoodDatabase.open(path: Self.dbPath)
        let catalog = RestaurantCatalog(database: db)
        let index = CuratedSearchIndex(CommonFoods.all, catalog: catalog)
        return await FoodSearch.search(query, catalog: catalog, database: db, index: index)
    }

    private func assertFirst(_ query: String, _ id: String, corrected: String?, file: StaticString = #filePath, line: UInt = #line) async throws {
        let out = try await search(query)
        XCTAssertEqual(out.foods.first?.id, id, query, file: file, line: line)
        XCTAssertEqual(out.correctedQuery, corrected, query, file: file, line: line)
    }

    func testChainQueriesLeadWithTheDefaultSize() async throws {
        let fries = try await search("mcdonalds fries")
        XCTAssertEqual(fries.foods.first?.id, "rest:mcdonalds:world-famous-fries-medium")
        XCTAssertEqual(fries.sizeChoices["rest:mcdonalds:world-famous-fries-medium"]?.map(\.label),
                       ["Kids", "Small", "Medium", "Large"])
        XCTAssertEqual(fries.foods.filter { $0.name.contains("World Famous Fries") }.count, 1)
        XCTAssertFalse(fries.foods.contains { $0.id.hasPrefix("ff-mcd") })   // curated duplicates suppressed
        XCTAssertFalse(fries.foods.contains { $0.id == "usda-170721" })      // bare "Mcdonald's" brand row dropped
        XCTAssertEqual(fries.strength, .strong)

        let latte = try await search("starbucks latte")
        XCTAssertEqual(latte.foods.first?.id, "rest:starbucks:caff-latte-3")   // Grande
        XCTAssertEqual(latte.sizeChoices["rest:starbucks:caff-latte-3"]?.map(\.label), ["Short", "Tall", "Grande", "Venti"])
        XCTAssertEqual(latte.foods.filter { $0.name.hasPrefix("Starbucks Caff") }.count, 1)
        XCTAssertLessThanOrEqual(latte.foods.count, 5 + 5)
    }

    func testMustPassTypoQueries() async throws {
        let medium = "rest:mcdonalds:world-famous-fries-medium"
        try await assertFirst("mdconalds fries", medium, corrected: "McDonald's fries")
        try await assertFirst("mcdonals nuggets", "rest:mcdonalds:chicken-mcnuggets-10-piece", corrected: "McDonald's nuggets")
        try await assertFirst("starbuks latte", "rest:starbucks:caff-latte-3", corrected: "Starbucks latte")
        try await assertFirst("shak shack fries", "rest:shake-shack:regular-fries", corrected: "Shake Shack fries")
        try await assertFirst("mcdonalds frys", medium, corrected: nil)            // "frys" is a plural form of "fries"
        try await assertFirst("mcdonalds freis", medium, corrected: "McDonald's fries")
        try await assertFirst("shake shack fires", "rest:shake-shack:regular-fries", corrected: "Shake Shack fries")
        try await assertFirst("chiken breast", "chicken-breast", corrected: "chicken breast")
        try await assertFirst("bananna", "banana", corrected: "banana")
        try await assertFirst("grenola", "granola", corrected: "granola")
    }

    func testValidQueriesAreLeftAlone() async throws {
        try await assertFirst("banana", "banana", corrected: nil)
        try await assertFirst("shake shack fries", "rest:shake-shack:regular-fries", corrected: nil)
        let chick = try await search("chick")                          // still typing a valid prefix
        XCTAssertNil(chick.correctedQuery)
        XCTAssertFalse(chick.foods.isEmpty)
    }
}
