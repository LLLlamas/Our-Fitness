// On-device natural-language meal parser.
// No network required — matches user input against the curated CommonFoods.all
// AND the bundled USDA FoodDatabase using simple tokenisation and quantity-word
// resolution.
//
// Resolution order per chunk: prefer the curated CommonFoods match (hand-tuned
// aliases/servings); if none matches, fall back to the broader USDA FoodDatabase.
// When both match, the longer alias wins so the more specific phrase is chosen,
// but ties go to the curated entry. Behaviour for foods already in CommonFoods
// is unchanged.
//
// Usage:
//   let result = FoodParser.parse("a bowl of rice and some grilled chicken")
//   // result.recognized → [rice×1, chicken×1]
//   // result.totalPerServing → combined macros

import Foundation

public enum FoodParser {

    // MARK: - Result types

    public struct ParsedItem: Equatable, Sendable {
        public let food: CommonFood
        public let quantity: Double
        public let scaledCalories: Int
        public let scaledProteinG: Int
        public let scaledCarbsG: Int
        public let scaledFatG: Int
        public let scaledFiberG: Int
        public var description: String {
            quantity == 1
                ? food.name
                : "\(food.name) ×\(quantity.formatted(.number.precision(.fractionLength(0...1))))"
        }
    }

    public struct ParseResult: Sendable {
        public let inputText: String
        public let recognized: [ParsedItem]
        public let unrecognized: [String]
        public var hasMatches: Bool { !recognized.isEmpty }
        public var bestName: String {
            recognized.isEmpty
                ? inputText.trimmingCharacters(in: .whitespaces)
                : recognized.map(\.food.name).joined(separator: " + ")
        }
        public var totalPerServing: PerServing {
            recognized.reduce(into: PerServing.zero) { acc, item in
                acc = PerServing(
                    calories:   acc.calories   + item.scaledCalories,
                    proteinG:   acc.proteinG   + item.scaledProteinG,
                    carbsG:     acc.carbsG     + item.scaledCarbsG,
                    fatG:       acc.fatG       + item.scaledFatG,
                    fiberG:     acc.fiberG     + item.scaledFiberG
                )
            }
        }
    }

    // MARK: - Quantity vocabulary

    private static let quantityMap: [(word: String, value: Double)] = [
        ("half a",  0.5), ("half an", 0.5), ("half", 0.5), ("½", 0.5), ("¼", 0.25),
        ("a couple of", 2), ("a couple", 2), ("couple", 2),
        ("a few", 3), ("few", 3),
        ("two", 2), ("three", 3), ("four", 4),
        ("large", 1.5), ("big", 1.5), ("small", 0.5), ("medium", 1),
        ("a bowl of", 1), ("a bowl", 1), ("bowl of", 1), ("bowl", 1),
        ("a cup of", 1), ("a cup", 1), ("cup of", 1), ("cup", 1),
        ("a plate of", 1.5), ("plate of", 1.5), ("a plate", 1.5), ("plate", 1.5),
        ("a piece of", 1), ("piece of", 1), ("a piece", 1), ("piece", 1),
        ("a slice of", 1), ("slice of", 1), ("a slice", 1), ("slice", 1),
        ("a serving of", 1), ("serving of", 1), ("a serving", 1), ("serving", 1),
        ("a handful of", 0.5), ("handful of", 0.5), ("handful", 0.5),
        ("a glass of", 1), ("glass of", 1), ("a glass", 1), ("glass", 1),
        ("a scoop of", 1), ("scoop of", 1), ("a scoop", 1), ("scoop", 1),
        ("an", 1), ("a", 1), ("some", 1),
    ]

    // Separators between items in the input
    private static let itemSeparators = [" and ", " with ", " plus ", " & ", ", "]

    // MARK: - Parse

    public static func parse(text: String) -> ParseResult {
        parse(text: text, dbLookup: SQLiteFoodDatabase.shared.bestMatch(in:))
    }

    /// Keystroke-vs-submit control over whether the big USDA database is consulted.
    ///
    /// The LIVE per-keystroke path passes `includeDatabase: false` so matching hits
    /// only the small curated `CommonFoods` (size-independent, always instant); the
    /// big database is reserved for the submit path (`resolve`) and library search,
    /// where one disk-backed FTS5 query per submit is fast even at ~270k entries.
    public static func parse(text: String, includeDatabase: Bool) -> ParseResult {
        let lookup: (String) -> FoodDatabaseEntry? = includeDatabase
            ? SQLiteFoodDatabase.shared.bestMatch(in:)
            : { _ in nil }
        return parse(text: text, dbLookup: lookup)
    }

    /// Parse against an injectable in-memory database — used by tests so the matcher
    /// can be exercised without the bundled resource (which the hostless test target
    /// lacks). Semantics are unchanged from the original `database:` overload.
    public static func parse(text: String, database: FoodDatabase) -> ParseResult {
        parse(text: text, dbLookup: database.bestMatch(in:))
    }

    /// Shared parse implementation. `dbLookup` is the fallback consulted only when
    /// the curated `CommonFoods` match misses — it abstracts over the in-memory
    /// `FoodDatabase` (tests) and the on-disk `SQLiteFoodDatabase` (production).
    private static func parse(text: String, dbLookup: (String) -> FoodDatabaseEntry?) -> ParseResult {
        let lower = text.lowercased()

        // Split into candidate chunks at natural separators
        var chunks: [String] = [lower]
        for sep in itemSeparators {
            chunks = chunks.flatMap { $0.components(separatedBy: sep) }
        }
        chunks = chunks
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 1 }

        var recognized: [ParsedItem] = []
        var unrecognized: [String] = []

        for chunk in chunks {
            let qty = resolveQuantity(from: chunk)
            if let food = matchFood(in: chunk, dbLookup: dbLookup) {
                recognized.append(scaled(food: food, by: qty))
            } else if !chunk.isEmpty {
                unrecognized.append(chunk)
            }
        }

        // Fallback: try the whole text if we got nothing
        if recognized.isEmpty {
            let qty = resolveQuantity(from: lower)
            if let food = matchFood(in: lower, dbLookup: dbLookup) {
                recognized.append(scaled(food: food, by: qty))
                return ParseResult(inputText: text, recognized: recognized, unrecognized: [])
            }
        }

        return ParseResult(inputText: text, recognized: recognized, unrecognized: unrecognized)
    }

    // MARK: - Quantity resolution

    private static func resolveQuantity(from chunk: String) -> Double {
        // Check quantity vocabulary first (longest match wins)
        let sorted = quantityMap.sorted { $0.word.count > $1.word.count }
        for entry in sorted {
            if chunk.hasPrefix(entry.word + " ") || chunk == entry.word {
                return entry.value
            }
        }
        // Leading numeral
        let digits = chunk.prefix(while: { $0.isNumber || $0 == "." })
        if let n = Double(digits), n > 0, n < 20 {
            return n
        }
        return 1.0
    }

    // MARK: - Resolving pre-extracted items (shared with the AI parser)

    /// A food name + quantity that some upstream stage already isolated (e.g. the
    /// on-device AI meal parser in `Services/MealParseService.swift`). The AI is
    /// only allowed to produce TEXT — it never supplies nutrition numbers. We hand
    /// those names straight back through this resolver so every calorie/macro value
    /// still comes from `CommonFoods`/`FoodDatabase`, never from the model.
    public struct ExtractedItem: Equatable, Sendable {
        public let name: String
        public let quantity: Double
        public init(name: String, quantity: Double) {
            self.name = name
            self.quantity = max(0, quantity)
        }
    }

    /// Resolve a list of already-split items into the SAME `ParseResult` the string
    /// parser produces. Each name is matched against the curated + USDA databases and
    /// scaled with the identical per-serving math; unmatched names land in
    /// `unrecognized`. This is the single bridge the AI parser uses so its output is
    /// indistinguishable from (and as safe as) the string path downstream.
    public static func resolve(items: [ExtractedItem]) -> ParseResult {
        resolve(items: items, dbLookup: SQLiteFoodDatabase.shared.bestMatch(in:))
    }

    /// Injectable in-memory-database variant for the hostless tests (no bundle).
    public static func resolve(items: [ExtractedItem], database: FoodDatabase) -> ParseResult {
        resolve(items: items, dbLookup: database.bestMatch(in:))
    }

    /// Shared resolver. `dbLookup` abstracts over the in-memory `FoodDatabase`
    /// (tests) and the on-disk `SQLiteFoodDatabase` (production), consulted only as
    /// the curated-miss fallback inside `matchFood`.
    private static func resolve(items: [ExtractedItem], dbLookup: (String) -> FoodDatabaseEntry?) -> ParseResult {
        var recognized: [ParsedItem] = []
        var unrecognized: [String] = []

        for item in items {
            let name = item.name.trimmingCharacters(in: .whitespaces)
            guard name.count > 1 else { continue }
            let qty = item.quantity > 0 ? item.quantity : 1.0
            if let food = matchFood(in: name.lowercased(), dbLookup: dbLookup) {
                recognized.append(scaled(food: food, by: qty))
            } else {
                unrecognized.append(name)
            }
        }

        let joined = items.map(\.name).joined(separator: ", ")
        return ParseResult(inputText: joined, recognized: recognized, unrecognized: unrecognized)
    }

    // MARK: - Food matching

    /// Curated `CommonFoods` wins; the `dbLookup` fallback (in-memory or SQLite)
    /// supplies breadth the curated set misses.
    private static func matchFood(in chunk: String, dbLookup: (String) -> FoodDatabaseEntry?) -> CommonFood? {
        // Curated CommonFoods first — hand-tuned aliases/servings are authoritative.
        // `bestMatch` is the indexed longest-alias matcher (size-independent, so the
        // curated set can grow without slowing the per-keystroke parse).
        if let curated = CommonFoods.bestMatch(in: chunk) { return curated }

        // Fall back to the broader USDA database for coverage curated foods miss.
        return dbLookup(chunk)?.asCommonFood
    }

    // MARK: - Scaling

    private static func scaled(food: CommonFood, by qty: Double) -> ParsedItem {
        ParsedItem(
            food: food,
            quantity: qty,
            scaledCalories: Int((Double(food.calories) * qty).rounded()),
            scaledProteinG: Int((Double(food.proteinG) * qty).rounded()),
            scaledCarbsG:   Int((Double(food.carbsG)   * qty).rounded()),
            scaledFatG:     Int((Double(food.fatG)      * qty).rounded()),
            scaledFiberG:   Int((Double(food.fiberG)    * qty).rounded())
        )
    }
}
