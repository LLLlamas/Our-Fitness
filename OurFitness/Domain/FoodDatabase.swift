// In-memory food database — used by tests and as a value-type building block.
//
// PRODUCTION use: `SQLiteFoodDatabase` (Domain/SQLiteFoodDatabase.swift) is the
// live implementation — it queries the bundled `usda-foods.db` (SQLite/FTS5) on
// disk so RAM stays low at ~270k entries. `FoodParser.parse(text:)` and
// `resolve(items:)` use `SQLiteFoodDatabase.shared`.
//
// THIS FILE serves two purposes:
//   1. `FoodDatabaseEntry` — the shared value type both implementations return.
//      Pure Foundation, fully testable without any bundle resource.
//   2. `FoodDatabase` (in-memory struct + token index) — injected via
//      `parse(text:database:)` / `resolve(items:database:)` in `OurFitnessTests`
//      so the parser can be exercised without the bundled `.db` (the hostless
//      test target ships no resources). `FoodDatabase.shared` still degrades
//      gracefully to empty; no test or live path depends on it for matching.
//
// Resolution authority: curated `CommonFoods` always wins; this DB is the
// broader-coverage fallback (see `FoodParser`). Numbers are never invented —
// only real USDA per-serving values appear here.

import Foundation

/// One USDA-derived food. Mirrors the fields `CommonFood` exposes so the parser
/// can treat curated and USDA matches uniformly. Decoded from the bundled JSON.
public struct FoodDatabaseEntry: Codable, Identifiable, Sendable, Equatable {
    public let id: String                // e.g. "usda-173688"
    public let name: String
    public let aliases: [String]
    public let servingLabel: String
    public let calories: Int
    public let proteinG: Int
    public let carbsG: Int
    public let fatG: Int
    public let fiberG: Int

    public init(
        id: String, name: String, aliases: [String], servingLabel: String,
        calories: Int, proteinG: Int, carbsG: Int, fatG: Int, fiberG: Int
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.servingLabel = servingLabel
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
    }

    /// Adapt to the curated `CommonFood` shape so parser callers stay uniform.
    public var asCommonFood: CommonFood {
        CommonFood(
            id: id, name: name, aliases: aliases, servingLabel: servingLabel,
            calories: calories, proteinG: proteinG, carbsG: carbsG,
            fatG: fatG, fiberG: fiberG
        )
    }
}

public struct FoodDatabase: Sendable {

    public let entries: [FoodDatabaseEntry]

    /// First-token bucket: the leading word of each lowercased alias/name → the
    /// (alias, entry) pairs that start with it. Lets `bestMatch` narrow to a tiny
    /// candidate set instead of scanning every alias in the database.
    ///
    /// Soundness: if `chunk.contains(alias)` then `chunk` contains `alias`'s leading
    /// token, so the chunk's word list always reaches the right bucket — narrowing by
    /// first token never drops a match the flat scan would have found.
    ///
    /// Buckets are appended in `entries` order, preserving the flat scan's "first wins
    /// among equal-length aliases" tie-break.
    private let tokenIndex: [String: [(alias: String, entry: FoodDatabaseEntry)]]

    public init(entries: [FoodDatabaseEntry]) {
        self.entries = entries

        var buckets: [String: [(alias: String, entry: FoodDatabaseEntry)]] = [:]
        for entry in entries {
            let names = [entry.name.lowercased()] + entry.aliases.map { $0.lowercased() }
            for alias in names {
                guard let token = FoodDatabase.firstToken(of: alias) else { continue }
                buckets[token, default: []].append((alias: alias, entry: entry))
            }
        }
        self.tokenIndex = buckets
    }

    public var isEmpty: Bool { entries.isEmpty }

    /// Leading whitespace-delimited word of a lowercased string, or nil if blank.
    private static func firstToken(of text: String) -> String? {
        text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)
    }

    /// Best substring match for a chunk of meal text: the entry whose alias is the
    /// LONGEST alias contained in `chunk` (mirrors `FoodParser`'s longest-alias rule).
    ///
    /// Narrows via `tokenIndex` — only aliases whose leading word appears as a word in
    /// `chunk` are tested for containment, so cost scales with the chunk's word count
    /// and bucket sizes, not the full alias count.
    public func bestMatch(in chunk: String) -> FoodDatabaseEntry? {
        var best: (alias: String, entry: FoodDatabaseEntry)? = nil
        var seenAliases = Set<String>()
        for word in chunk.split(separator: " ", omittingEmptySubsequences: true) {
            guard let candidates = tokenIndex[String(word)] else { continue }
            for candidate in candidates {
                // A bucket can be reached by more than one chunk word when an alias
                // repeats a token; dedup so each alias is tested at most once.
                guard seenAliases.insert(candidate.alias).inserted else { continue }
                if chunk.contains(candidate.alias),
                   best == nil || candidate.alias.count > best!.alias.count {
                    best = candidate
                }
            }
        }
        return best?.entry
    }

    // MARK: - Bundled resource

    public static let resourceName = "usda-foods"

    /// Lazily-loaded database backed by the bundled JSON. Empty when absent.
    public static let shared: FoodDatabase = loadBundled()

    /// Load `usda-foods.json` from `Bundle.main`. Returns an empty database if the
    /// resource is missing or unreadable — callers must tolerate an empty DB.
    public static func loadBundled(bundle: Bundle = .main) -> FoodDatabase {
        guard
            let url = bundle.url(forResource: resourceName, withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([FoodDatabaseEntry].self, from: data)
        else {
            return FoodDatabase(entries: [])
        }
        return FoodDatabase(entries: decoded)
    }
}
