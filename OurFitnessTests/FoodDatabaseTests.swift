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

    // MARK: - Token-index narrowing (scale-hardening)

    /// The token index narrows by the LEADING word of each alias. A multi-word alias
    /// must still match even when its leading word is not the chunk's first word.
    func test_bestMatch_multiWordAlias_leadingWordMidSentence() {
        let entry = sampleDB().bestMatch(in: "for dinner i had grilled tilapia tonight")
        XCTAssertEqual(entry?.id, "usda-test-tilapia")
    }

    /// Longest-alias-wins must survive the narrowing: a bare alias and a longer alias
    /// live in different buckets ("grilled" vs "tilapia"), yet the longer one wins.
    func test_bestMatch_longestAliasWins_acrossBuckets() {
        let db = FoodDatabase(entries: [
            FoodDatabaseEntry(
                id: "usda-chicken", name: "Chicken",
                aliases: ["chicken", "grilled chicken breast"],
                servingLabel: "100 g",
                calories: 165, proteinG: 31, carbsG: 0, fatG: 4, fiberG: 0
            )
        ])
        // Both "chicken" and "grilled chicken breast" are contained; the longer wins,
        // proving the bucket reached via "grilled" is considered, not just "chicken".
        let entry = db.bestMatch(in: "i ate grilled chicken breast")
        XCTAssertEqual(entry?.id, "usda-chicken")
    }

    /// Narrowing must not invent matches: a chunk whose words hit no bucket returns nil.
    func test_bestMatch_noBucketHit_returnsNil() {
        XCTAssertNil(sampleDB().bestMatch(in: "plain buttered toast"))
    }

    /// A token shared by two distinct entries' aliases still resolves the right one
    /// by substring containment after narrowing.
    func test_bestMatch_sharedLeadingToken_picksContained() {
        let db = FoodDatabase(entries: [
            FoodDatabaseEntry(
                id: "usda-green-beans", name: "Green beans",
                aliases: ["green beans"], servingLabel: "1 cup",
                calories: 31, proteinG: 2, carbsG: 7, fatG: 0, fiberG: 3
            ),
            FoodDatabaseEntry(
                id: "usda-green-tea", name: "Green tea",
                aliases: ["green tea"], servingLabel: "1 cup",
                calories: 2, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0
            ),
        ])
        // Both share leading token "green"; only "green tea" is actually contained.
        XCTAssertEqual(db.bestMatch(in: "a cup of green tea")?.id, "usda-green-tea")
    }

    /// The narrowed match must agree with a brute-force flat scan over the same data
    /// for a spread of queries — guards the optimization against silent divergence.
    func test_bestMatch_agreesWithBruteForce() {
        let db = sampleDB()
        let pairs: [(alias: String, entry: FoodDatabaseEntry)] = db.entries.flatMap { e in
            ([e.name.lowercased()] + e.aliases.map { $0.lowercased() }).map { ($0, e) }
        }
        func bruteForce(_ chunk: String) -> FoodDatabaseEntry? {
            var best: (alias: String, entry: FoodDatabaseEntry)? = nil
            for c in pairs where chunk.contains(c.alias) {
                if best == nil || c.alias.count > best!.alias.count { best = c }
            }
            return best?.entry
        }
        let queries = [
            "grilled tilapia", "tilapia", "kiwifruit", "i had a kiwi",
            "nothing here", "grilled tilapia and a kiwi", "",
        ]
        for q in queries {
            XCTAssertEqual(db.bestMatch(in: q)?.id, bruteForce(q)?.id,
                           "narrowed match diverged from brute force for '\(q)'")
        }
    }
}
