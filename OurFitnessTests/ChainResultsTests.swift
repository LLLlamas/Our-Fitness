import XCTest

/// Typed search that starts with a chain (`Domain/ChainResults.swift`): the
/// chain's items first with sizes collapsed, duplicates and other chains
/// removed, the rest capped. Fixtures only — never the bundled database.
final class ChainResultsTests: XCTestCase {

    private let mcd = RestaurantChain(slug: "mcdonalds", name: "McDonald's",
                                      aliases: ["mcdonalds", "mcd"], kind: "fast-food", itemCount: 9)
    private let sbux = RestaurantChain(slug: "starbucks", name: "Starbucks",
                                       aliases: ["starbucks", "sbux"], kind: "coffee", itemCount: 8)
    private let wendys = RestaurantChain(slug: "wendys", name: "Wendy's",
                                         aliases: ["wendys"], kind: "fast-food", itemCount: 1)

    private func entry(_ id: String, _ name: String, _ serving: String, _ cal: Int) -> FoodDatabaseEntry {
        FoodDatabaseEntry(id: id, name: name, aliases: [], servingLabel: serving,
                          calories: cal, proteinG: 1, carbsG: 1, fatG: 1, fiberG: 0)
    }

    private func item(_ chain: RestaurantChain, _ slug: String, _ itemName: String, _ serving: String,
                      _ order: Int, cal: Int = 100) -> RestaurantMenuItem {
        RestaurantMenuItem(chainSlug: chain.slug, category: "Menu", sortOrder: order, itemName: itemName,
                           food: entry("rest:\(chain.slug):\(slug)", "\(chain.name) \(itemName)", serving, cal))
    }

    private var items: [RestaurantMenuItem] {
        [item(mcd, "fries-small", "World Famous Fries (Small)", "1 order (small)", 0, cal: 230),
         item(mcd, "fries-kids", "World Famous Fries (Kids)", "1 order (kids)", 1, cal: 110),
         item(mcd, "fries-medium", "World Famous Fries (Medium)", "1 order (medium)", 2, cal: 320),
         item(mcd, "fries-large", "World Famous Fries (Large)", "1 order (large)", 3, cal: 480),
         item(mcd, "nuggets-4", "Chicken McNuggets (4 piece)", "4 piece", 4),
         item(mcd, "nuggets-10", "Chicken McNuggets (10 piece)", "10 piece", 5),
         item(mcd, "nuggets-20", "Chicken McNuggets (20 piece)", "20 piece", 6),
         item(mcd, "bigmac", "Big Mac", "1 sandwich", 7),
         item(sbux, "caff-latte", "Caffè Latte", "Short 8 fl oz, 2% milk", 0),
         item(sbux, "caff-latte-2", "Caffè Latte", "Tall 12 fl oz, 2% milk", 1),
         item(sbux, "caff-latte-3", "Caffè Latte", "Grande 16 fl oz, 2% milk", 2),
         item(sbux, "caff-latte-4", "Caffè Latte", "Venti 20 fl oz, 2% milk", 3),
         item(sbux, "pecan-latte", "Pecan Crunch Latte", "Grande 16 fl oz", 4),
         item(wendys, "fries", "Fries", "1 order", 0)]
    }

    private func curated(_ id: String, _ name: String, _ aliases: [String] = []) -> CommonFood {
        CommonFood(id: id, name: name, aliases: aliases, servingLabel: "1 serving",
                   calories: 100, proteinG: 1, carbsG: 1, fatG: 1, fiberG: 0)
    }

    private func run(_ query: String, curated foods: [CommonFood] = [], items menu: [RestaurantMenuItem]? = nil) async -> FoodSearchOutcome {
        let catalog = RestaurantCatalog(chains: [mcd, sbux, wendys], items: menu ?? items)
        let index = CuratedSearchIndex(foods, catalog: catalog)
        return await FoodSearch.search(query, catalog: catalog,
                                       database: .open(path: "/nonexistent/none.db"), index: index)
    }

    func testChainQueryCollapsesSizesDefaultFirst() async {
        let out = await run("mcdonalds fries")
        XCTAssertEqual(out.foods.map(\.id), ["rest:mcdonalds:fries-medium"])   // Wendy's fries dropped
        let sizes = out.sizeChoices["rest:mcdonalds:fries-medium"]
        XCTAssertEqual(sizes?.map(\.label), ["Kids", "Small", "Medium", "Large"])
        XCTAssertEqual(sizes?.map(\.food.id), ["rest:mcdonalds:fries-kids", "rest:mcdonalds:fries-small",
                                               "rest:mcdonalds:fries-medium", "rest:mcdonalds:fries-large"])
        XCTAssertEqual(sizes?.map(\.food.calories), [110, 230, 320, 480])   // each size keeps its own numbers

        // Piece counts: 10 pc is the default, the others stay choices.
        let nuggets = await run("mcdonalds nuggets")
        XCTAssertEqual(nuggets.foods.map(\.id), ["rest:mcdonalds:nuggets-10"])
        XCTAssertEqual(nuggets.sizeChoices["rest:mcdonalds:nuggets-10"]?.map(\.label), ["4 pc", "10 pc", "20 pc"])

        // Sizes live in the serving label: one Caffè Latte, Grande default.
        let latte = await run("starbucks latte")
        XCTAssertEqual(latte.foods.map(\.id), ["rest:starbucks:caff-latte-3", "rest:starbucks:pecan-latte"])
        XCTAssertEqual(latte.sizeChoices["rest:starbucks:caff-latte-3"]?.map(\.label), ["Short", "Tall", "Grande", "Venti"])
        XCTAssertNil(latte.sizeChoices["rest:starbucks:pecan-latte"])
    }

    func testDefaultSizePreference() {
        XCTAssertEqual(SizeVariants.defaultIndex(["Small", "Large", "Medium"]), 2)
        XCTAssertEqual(SizeVariants.defaultIndex(["Small", "Regular", "Large"]), 1)
        XCTAssertEqual(SizeVariants.defaultIndex(["Tall", "Grande", "Venti"]), 1)
        XCTAssertEqual(SizeVariants.defaultIndex(["4 pc", "10 pc", "20 pc"]), 1)
        XCTAssertEqual(SizeVariants.defaultIndex(["Kids", "Large"]), 0)
        let p = SizeVariants.parse(name: "Fries - Large", servingLabel: "1 order")
        XCTAssertEqual(p.size, "Large"); XCTAssertEqual(p.base, "fries")
        XCTAssertEqual(SizeVariants.parse(name: "Nuggets 10pc", servingLabel: "").size, "10 pc")
        XCTAssertNil(SizeVariants.parse(name: "Big Mac", servingLabel: "1 sandwich").size)
        XCTAssertNil(SizeVariants.parse(name: "The Big Carl (Triple) (402 g)", servingLabel: "1 burger").size)
    }

    func testChainQueryCapsGroupsAtFive() async {
        let many = (0..<8).flatMap { n in
            [item(mcd, "wrap\(n)-s", "Wrap \(n) (Small)", "1 wrap", n * 2),
             item(mcd, "wrap\(n)-l", "Wrap \(n) (Large)", "1 wrap", n * 2 + 1)]
        }
        let out = await run("mcdonalds wrap", items: many)
        XCTAssertEqual(out.foods.count, 5)
        XCTAssertEqual(out.sizeChoices.count, 5)
    }

    func testChainQuerySuppressesCuratedDuplicates() async {
        let ownCurated = curated("ff-mcd-fries-medium", "McDonald's medium fries")
        let otherChainCurated = curated("ff-wendys-fries", "Wendy's fries (a McDonald's rival)", ["mcdonalds fries"])
        let otherOfficial = curated("rest:wendys:fries", "Wendy's Fries", ["mcdonalds fries"])
        let plain = curated("fries", "French fries", ["mcdonalds fries"])

        let out = await run("mcdonalds fries", curated: [ownCurated, otherChainCurated, otherOfficial, plain])
        XCTAssertEqual(out.foods.map(\.id), ["rest:mcdonalds:fries-medium", "fries"])

        // No official rows for the chain → its own curated row is all there is, keep it.
        let noMenu = await run("mcdonalds fries", curated: [ownCurated, otherChainCurated, otherOfficial, plain],
                               items: items.filter { $0.chainSlug != "mcdonalds" })
        XCTAssertEqual(noMenu.foods.map(\.id).sorted(), ["ff-mcd-fries-medium", "fries"])
    }

    func testChainQueryCapsOtherRows() async {
        let others = (0..<9).map { curated("plain-\($0)", "Mcdonalds style fries \($0)") }
        let out = await run("mcdonalds fries", curated: others)
        XCTAssertEqual(out.foods.count, 1 + 5)
        XCTAssertEqual(out.foods.first?.id, "rest:mcdonalds:fries-medium")
    }

    func testNonChainQueryIsUnchanged() async {
        let out = await run("fries", curated: [curated("fries", "French fries", ["fries"])])
        XCTAssertEqual(out.foods.map(\.id), ["fries"])
        XCTAssertTrue(out.sizeChoices.isEmpty)
    }
}
