import XCTest
import SQLite3

/// Restaurant chain query splitting, menu filtering and typo tolerance (`Domain/RestaurantCatalog.swift`).
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

    private let mcdonalds = RestaurantChain(
        slug: "mcdonalds", name: "McDonald's",
        aliases: ["mcdonalds", "mcdonald", "mcd"], kind: "fast-food", itemCount: 1)
    private let starbucks = RestaurantChain(
        slug: "starbucks", name: "Starbucks", aliases: ["starbucks", "sbux"], kind: "coffee", itemCount: 1)
    private let quest = RestaurantChain(
        slug: "quest-nutrition", name: "Quest Nutrition", aliases: ["quest", "quest bar"], kind: "supplement", itemCount: 1)
    private let panera = RestaurantChain(
        slug: "panera", name: "Panera Bread", aliases: ["panera", "panera bread"], kind: "fast-casual", itemCount: 1)
    private let noodles = RestaurantChain(
        slug: "noodles-and-company", name: "Noodles & Company", aliases: ["noodles"], kind: "fast-casual", itemCount: 1)
    private let chilis = RestaurantChain(
        slug: "chilis", name: "Chili's", aliases: ["chilis", "chili's"], kind: "casual-dining", itemCount: 1)

    private var chains: [RestaurantChain] { [shakeShack, canes, oliveGarden] }
    private var allChains: [RestaurantChain] { chains + [mcdonalds, starbucks, quest, panera, noodles, chilis] }

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

    // MARK: - Typos

    func testTranspositionIsOneEdit() {
        func d(_ a: String, _ b: String) -> Int { RestaurantMatcher.editDistance(Array(a), Array(b), cap: 2) }
        XCTAssertEqual(d("freis", "fries"), 1)
        XCTAssertEqual(d("fires", "fries"), 1)
        XCTAssertEqual(d("mdconalds", "mcdonalds"), 1)
        XCTAssertEqual(d("ab", "ba"), 1)
        XCTAssertEqual(d("fries", "fries"), 0)
        XCTAssertEqual(d("shak", "shake"), 1)
        XCTAssertEqual(d("abc", "cba"), 2)            // a non-adjacent swap is still two edits
        XCTAssertEqual(d("fries", "fried"), 1)
        XCTAssertGreaterThan(d("fries", "fresh"), 1)
    }

    func testSplitToleratesOneTypoInChainName() {
        func split(_ q: String) -> (String, String, Bool)? {
            RestaurantMatcher.split(q, chains: allChains).map { ($0.chain.slug, $0.remainder, $0.fuzzy) }
        }
        for (q, slug, rest) in [("mdconalds fries", "mcdonalds", "fries"),     // swapped letters
                                ("mcdonals nuggets", "mcdonalds", "nuggets"),   // dropped letter
                                ("starbuks latte", "starbucks", "latte"),
                                ("shak shack fries", "shake-shack", "fries"),   // two words, run together
                                ("shake shack fires", "shake-shack", "fires")] {
            let s = split(q)
            XCTAssertEqual(s?.0, slug, q)
            XCTAssertEqual(s?.1, rest, q)
        }
        XCTAssertEqual(split("mdconalds fries")?.2, true)
        XCTAssertEqual(split("shake shack fires")?.2, false)   // exact chain, typo is in the remainder
        XCTAssertEqual(split("mcdonalds fries")?.2, false)     // exact stays exact
    }

    func testSplitIgnoresRealFoodWords() {
        for q in ["cakes", "queso dip", "panela cheese", "zoodles", "chiles rellenos", "cakes and pies"] {
            XCTAssertNil(RestaurantMatcher.split(q, chains: allChains), q)
        }
        // The vocabulary guard: a word the curated list knows is never a chain typo.
        XCTAssertNotNil(RestaurantMatcher.split("starbuks latte", chains: allChains))
        XCTAssertNil(RestaurantMatcher.split("starbuks latte", chains: allChains, isFoodWord: { $0 == "starbuks" }))
        // Too short, or two chains equally near → no guess.
        XCTAssertNil(RestaurantMatcher.split("cane fries", chains: allChains))
        // "chilxs" is one edit from both Chili's ("chilis") and Chilas.
        XCTAssertNotNil(RestaurantMatcher.split("chilxs", chains: allChains))
        XCTAssertNil(RestaurantMatcher.split("chilxs", chains: allChains + [RestaurantChain(
            slug: "chilas", name: "Chilas", aliases: ["chilas"], kind: "x", itemCount: 1)]))
    }

    func testFilterAcceptsPluralFormsAndMenuCorrectionFixesWords() {
        XCTAssertEqual(RestaurantMatcher.filter(menu, query: "fry").map(\.itemName), ["Fries", "Cheese Fries"])
        XCTAssertEqual(RestaurantMatcher.filter(menu, query: "burgers").map(\.itemName), ["ShackBurger"])
        XCTAssertTrue(RestaurantMatcher.filter(menu, query: "fried").isEmpty)   // "fries" never reaches "fried"
        XCTAssertEqual(RestaurantMatcher.menuCorrection(for: "fires", in: menu), "fries")
        XCTAssertEqual(RestaurantMatcher.menuCorrection(for: "freis", in: menu), "fries")
        XCTAssertEqual(RestaurantMatcher.menuCorrection(for: "fries", in: menu), "fries")   // already valid
        XCTAssertNil(RestaurantMatcher.menuCorrection(for: "pizza", in: menu))
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
        XCTAssertEqual(catalog.split("shake shack fries")?.chain.slug, "shake-shack")
        XCTAssertEqual(catalog.menuMatches(for: "shake shack fries").first?.itemName, "Fries")

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
