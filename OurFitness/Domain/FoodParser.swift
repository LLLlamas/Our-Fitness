// On-device natural-language meal parser.
// No network required — matches user input against CommonFoods.all using
// simple tokenisation and quantity-word resolution.
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
            if let food = matchFood(in: chunk) {
                recognized.append(scaled(food: food, by: qty))
            } else if !chunk.isEmpty {
                unrecognized.append(chunk)
            }
        }

        // Fallback: try the whole text if we got nothing
        if recognized.isEmpty {
            let qty = resolveQuantity(from: lower)
            if let food = matchFood(in: lower) {
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

    // MARK: - Food matching

    private static func matchFood(in chunk: String) -> CommonFood? {
        // Build sorted (longest alias first) candidate list once
        struct Candidate { let food: CommonFood; let alias: String }
        var best: Candidate? = nil

        for food in CommonFoods.all {
            let names = [food.name.lowercased()] + food.aliases.map { $0.lowercased() }
            for alias in names {
                if chunk.contains(alias) {
                    if best == nil || alias.count > best!.alias.count {
                        best = Candidate(food: food, alias: alias)
                    }
                }
            }
        }
        return best?.food
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
