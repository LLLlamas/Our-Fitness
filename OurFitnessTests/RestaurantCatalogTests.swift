import XCTest
import SQLite3

/// Restaurant chain matching + query splitting (`Domain/RestaurantCatalog.swift`).
/// Pure fixtures — never the bundled database, whose chain list changes as menus
/// are added. One test builds a throwaway SQLite file to pin the table contract
/// with `scripts/build-food-db.py` and the "older database" no-op.
final class RestaurantCatalogTests: XCTestCase {

    private let shakeShack = RestaurantChain(
        slug: "shake-shack", name: "Shake Shack",
        aliases: ["shake shack", "shakeshack", "shack", "shake shac", "shakeshak"],
        kind: "fast-casual", itemCount: 4)
    private let canes = RestaurantChain(
        slug: "raising-canes", name: "Raising Cane's",
        aliases: ["raising canes", "canes"], kind: "fast-food", itemCount: 1)
    private let oliveGarden = RestaurantChain(
        slug: "olive-garden", name: "Olive Garden",
        aliases: ["olive garden", "olivegarden", "og"], kind: "casual-dining", itemCount: 1)

    private var chains: [RestaurantChain] { [shakeShack, canes, oliveGarden] }

    private func item(_ name: String, _ category: String, _ order: Int, chain: String = "shake-shack") -> RestaurantMenuItem {
        RestaurantMenuItem(
            chainSlug: chain, category: category, sortOrder: order, itemName: name,
            food: FoodDatabaseEntry(
                id: "rest:\(chain):\(order)", name: "Shake Shack \(name)", aliases: [],
                servingLabel: "1 serving", calories: 100, proteinG: 1, carbsG: 1, fatG: 1, fiberG: 0))
    }

    private var menu: [RestaurantMenuItem] {
        [item("ShackBurger", "Burgers", 0),
         item("Cheese Fries", "Fries", 1),
         item("Fries", "Fries", 2),
         item("Chocolate Shake", "Shakes", 3)]
    }

    private func slugs(_ q: String) -> [String] {
        RestaurantMatcher.chains(matching: q, in: chains).map(\.slug)
    }

    // MARK: - Chain matching

    func testRunTogetherAndPartialSpellingsMatch() {
        for q in ["shakesha", "shakeshack", "shake shack", "SHAKE SHACK", "shake-sh", "Shake Shack!"] {
            XCTAssertEqual(slugs(q).first, "shake-shack", q)
        }
    }

    func testLaterWordPrefixAndApostrophe() {
        XCTAssertEqual(slugs("cane").first, "raising-canes")
        XCTAssertEqual(slugs("raising cane's").first, "raising-canes")
        XCTAssertEqual(slugs("raisingcanes").first, "raising-canes")
    }

    func testAliasesAndOneTypo() {
        XCTAssertEqual(slugs("shakeshak").first, "shake-shack")   // alias typo from the data file
        XCTAssertEqual(slugs("shakshack").first, "shake-shack")   // one dropped letter
        XCTAssertEqual(slugs("og"), ["olive-garden"])             // exact 2-letter alias
    }

    func testTooShortOrUnrelatedDoesNotMatch() {
        XCTAssertEqual(slugs("sh"), [])
        XCTAssertEqual(slugs("ol"), [])
        XCTAssertEqual(slugs("chicken"), [])
        XCTAssertEqual(slugs("banana"), [])
    }

    /// Decision (documented on `RestaurantMatcher.score`): a bare first word
    /// matches. It's one compact row above the unchanged food results.
    func testBareFirstWordMatchesButRanksBelowExact() {
        XCTAssertEqual(slugs("shake"), ["shake-shack"])
        let exact = RestaurantMatcher.score(shakeShack, query: "shake shack")
        let partial = RestaurantMatcher.score(shakeShack, query: "shake")
        XCTAssertNotNil(partial)
        XCTAssertLessThan(exact!, partial!)
    }

    func testQueryStartingWithChainSurfacesThatChain() {
        XCTAssertEqual(slugs("shake shack fries").first, "shake-shack")
        XCTAssertEqual(slugs("og breadsticks").first, "olive-garden")
    }

    // MARK: - Splitting

    func testSplitSeparatesChainFromRemainder() {
        let s = RestaurantMatcher.split("shake shack fries", chains: chains)
        XCTAssertEqual(s?.chain.slug, "shake-shack")
        XCTAssertEqual(s?.remainder, "fries")

        let t = RestaurantMatcher.split("ShakeShack cheese fries", chains: chains)
        XCTAssertEqual(t?.chain.slug, "shake-shack")
        XCTAssertEqual(t?.remainder, "cheese fries")

        let u = RestaurantMatcher.split("raising canes box combo", chains: chains)
        XCTAssertEqual(u?.chain.slug, "raising-canes")
        XCTAssertEqual(u?.remainder, "box combo")
    }

    func testSplitPrefersLongestChainMatch() {
        // "shack" is also an alias, but "shake shack" consumes more of the query.
        let s = RestaurantMatcher.split("shake shack burger", chains: chains)
        XCTAssertEqual(s?.remainder, "burger")
    }

    func testSplitNeedsAWholeChainName() {
        XCTAssertNil(RestaurantMatcher.split("shake fries", chains: chains))
        XCTAssertNil(RestaurantMatcher.split("fries", chains: chains))
        XCTAssertEqual(RestaurantMatcher.split("shake shack", chains: chains)?.remainder, "")
    }

    // MARK: - Menu

    func testFilterRanksNameStartFirstThenMenuOrder() {
        let names = RestaurantMatcher.filter(menu, query: "fries").map(\.itemName)
        XCTAssertEqual(names, ["Fries", "Cheese Fries"])
    }

    func testFilterPrefersTheShortestMatchingName() {
        let burgers = ["ShackBurger, Single Lettuce Wrap", "Single ShackBurger", "ShackBurger Gluten Free Bun, Single"]
            .enumerated().map { i, name in
                RestaurantMenuItem(chainSlug: "shake-shack", category: "Burgers", sortOrder: i, itemName: name,
                                   food: menu[0].food)
            }
        XCTAssertEqual(RestaurantMatcher.filter(burgers, query: "shackburger").first?.itemName, "Single ShackBurger")
    }

    func testFilterMatchesInsideRunTogetherNamesAndCategories() {
        XCTAssertEqual(RestaurantMatcher.filter(menu, query: "burger").map(\.itemName), ["ShackBurger"])
        XCTAssertEqual(RestaurantMatcher.filter(menu, query: "shakes").map(\.itemName), ["Chocolate Shake"])
        XCTAssertEqual(RestaurantMatcher.filter(menu, query: "").count, menu.count)
        XCTAssertEqual(RestaurantMatcher.filter(menu, query: "pizza"), [])
    }

    func testSectionsKeepSourceOrder() {
        let sections = RestaurantMatcher.sections(menu.reversed())
        XCTAssertEqual(sections.map(\.category), ["Burgers", "Fries", "Shakes"])
        XCTAssertEqual(sections[1].items.map(\.itemName), ["Cheese Fries", "Fries"])
    }

    func testMenuMatchesNeedARemainder() {
        let catalog = RestaurantCatalog(chains: chains, items: menu)
        XCTAssertEqual(catalog.menuMatches(for: "shake shack fries").first?.itemName, "Fries")
        XCTAssertEqual(catalog.menuMatches(for: "shake shack"), [])
        XCTAssertEqual(catalog.menuMatches(for: "fries"), [])
    }

    // MARK: - Database contract

    func testLoadsTablesFromDatabaseAndNoOpsWithoutThem() throws {
        let dir = FileManager.default.temporaryDirectory
        let withTables = dir.appendingPathComponent("rest-\(UUID().uuidString).db").path
        let withoutTables = dir.appendingPathComponent("rest-\(UUID().uuidString).db").path
        defer {
            try? FileManager.default.removeItem(atPath: withTables)
            try? FileManager.default.removeItem(atPath: withoutTables)
        }
        try exec(withTables, """
            CREATE TABLE restaurant_chains (slug TEXT PRIMARY KEY, name TEXT NOT NULL, aliases TEXT NOT NULL,
              kind TEXT NOT NULL, item_count INTEGER NOT NULL, source_url TEXT NOT NULL,
              source_kind TEXT NOT NULL, retrieved TEXT NOT NULL);
            CREATE TABLE restaurant_items (id TEXT PRIMARY KEY, chain_slug TEXT NOT NULL, category TEXT NOT NULL,
              sort_order INTEGER NOT NULL, item_name TEXT NOT NULL, name TEXT NOT NULL, serving_label TEXT NOT NULL,
              calories INTEGER NOT NULL, protein_g INTEGER NOT NULL, carbs_g INTEGER NOT NULL,
              fat_g INTEGER NOT NULL, fiber_g INTEGER NOT NULL);
            INSERT INTO restaurant_chains VALUES ('shake-shack','Shake Shack','shake shack|shakeshack','fast-casual',2,'','official','2026-10-14');
            INSERT INTO restaurant_items VALUES ('rest:shake-shack:fries','shake-shack','Fries',1,'Fries','Shake Shack Fries','1 order',470,6,63,22,6);
            INSERT INTO restaurant_items VALUES ('rest:shake-shack:shackburger','shake-shack','Burgers',0,'ShackBurger','Shake Shack ShackBurger','1 burger',500,29,26,30,0);
            """)
        try exec(withoutTables, "CREATE TABLE foods (id TEXT);")

        let catalog = RestaurantCatalog(database: .open(path: withTables))
        XCTAssertEqual(catalog.chains.map(\.name), ["Shake Shack"])
        XCTAssertEqual(catalog.chains.first?.aliases, ["shake shack", "shakeshack"])
        XCTAssertEqual(catalog.menu(for: "shake-shack").map(\.itemName), ["ShackBurger", "Fries"])
        let fries = catalog.menu(for: "shake-shack")[1].food
        XCTAssertEqual(fries.id, "rest:shake-shack:fries")
        XCTAssertEqual(fries.name, "Shake Shack Fries")
        XCTAssertEqual([fries.calories, fries.proteinG, fries.carbsG, fries.fatG, fries.fiberG], [470, 6, 63, 22, 6])
        XCTAssertEqual(catalog.chains(matching: "shakesha").first?.slug, "shake-shack")

        XCTAssertTrue(RestaurantCatalog(database: .open(path: withoutTables)).isEmpty)
        XCTAssertTrue(RestaurantCatalog(database: .open(path: dir.appendingPathComponent("missing/x.db").path)).isEmpty)
    }

    private func exec(_ path: String, _ sql: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw XCTSkip("sqlite open failed") }
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }
}
