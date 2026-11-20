// Restaurant / chain menus — "I ate at Shake Shack".
//
// Data: `scripts/restaurant-data/<slug>.json` → `scripts/build-food-db.py` →
// two small tables in the bundled `usda-foods.db` (`restaurant_chains`,
// `restaurant_items`). Each item is ALSO an ordinary `foods` row
// (`rest:<slug>:<item>`, name "<Chain> <Item>"), so plain food search and the
// parser find it with no special casing; this file adds what search can't:
//   • splitting "shake shack fries" (typos tolerated) into (Shake Shack,
//     "fries") so that chain's fries rank first among the individual matches
//     (`ChainResults.swift` arranges them).
//
// The whole catalog (a few thousand rows) is read ONCE into memory, so every
// keystroke is a pure in-memory scan over a handful of chains — never SQL.
// Degrades to empty when the database lacks the restaurant tables.
//
// Domain layer: Foundation only.

import Foundation

public struct RestaurantChain: Identifiable, Sendable, Hashable {
    public let slug: String
    public let name: String
    /// Lowercased alternate spellings from the data file (incl. the name itself).
    public let aliases: [String]
    /// "fast-food", "casual-dining", … — free text from the data file.
    public let kind: String
    public let itemCount: Int
    public var id: String { slug }

    /// Name + aliases run together ("shakeshack"), computed once so a keystroke
    /// never re-folds strings.
    let matchKeys: [String]

    public init(slug: String, name: String, aliases: [String], kind: String, itemCount: Int) {
        self.slug = slug
        self.name = name
        self.aliases = aliases
        self.kind = kind
        self.itemCount = itemCount
        var keys: [String] = []
        for k in ([name] + aliases).map(RestaurantMatcher.normalize) where !k.isEmpty && !keys.contains(k) {
            keys.append(k)
        }
        self.matchKeys = keys
    }
}

public struct RestaurantMenuItem: Identifiable, Sendable, Equatable {
    public let chainSlug: String
    public let category: String
    /// Position in the chain's source file — the menu's display order.
    public let sortOrder: Int
    /// The item as the menu names it ("ShackBurger").
    public let itemName: String
    /// The loggable food: same id + numbers as its `foods` row, name "<Chain> <Item>".
    public let food: FoodDatabaseEntry
    public var id: String { food.id }

    /// `itemName` / `category` folded into words once, so a menu-search
    /// keystroke never re-folds strings (a 1,300-item menu re-folded per
    /// keystroke cost ~10 ms on the main thread).
    let nameWords: [String]
    let categoryWords: [String]

    public init(chainSlug: String, category: String, sortOrder: Int, itemName: String, food: FoodDatabaseEntry) {
        self.chainSlug = chainSlug
        self.category = category
        self.sortOrder = sortOrder
        self.itemName = itemName
        self.food = food
        self.nameWords = RestaurantMatcher.words(itemName)
        self.categoryWords = RestaurantMatcher.words(category)
    }
}

// MARK: - Matching (pure)

public enum RestaurantMatcher {

    /// Typo tolerance (one edit) only kicks in from this many characters.
    public static let minTypoLength = 5

    /// Lowercased words with diacritics folded and apostrophes dropped, so
    /// "Raising Cane's" → ["raising", "canes"] and "shake-shack" → ["shake", "shack"].
    public static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map(String.init)
    }

    /// The words run together: "Shake Shack" / "shake-shack" / "SHAKESHACK" → "shakeshack".
    public static func normalize(_ text: String) -> String { words(text).joined() }

    /// Real words that sit one edit from a chain key but aren't the chain:
    /// cakes/canes, queso/quest, panela/panera, zoodles/noodles, chiles/chilis.
    /// A floor under the vocabulary check (`CuratedSearchIndex` adds every curated
    /// food word), for words the curated list doesn't carry.
    static let nonChainWords: Set<String> = [
        "cakes", "queso", "panela", "zoodles", "chiles", "organ", "habits",
    ]
    public static func isNonChainWord(_ w: String) -> Bool { nonChainWords.contains(w) }

    /// Splits "shake shack fries" / "shakeshack fries" / "raising canes box"
    /// into (chain, remainder) when the query's leading words spell a chain's
    /// whole name or an alias. The longest leading match wins. Remainder may be
    /// empty ("shake shack"). Partial chain names don't split — "shake fries"
    /// stays a plain food search.
    ///
    /// No exact match → typo tolerance: leading words run together (≥5
    /// characters, `fuzzy` = true) within ONE edit (an adjacent swap counts as
    /// one) of a key of exactly one chain split off ("mdconalds fries",
    /// "shak shack fries"), unless the word is a real food word
    /// (`isFoodWord`: "cakes" ≠ Canes, "queso" ≠ Quest).
    public static func split(
        _ query: String, chains: [RestaurantChain],
        isFoodWord: (String) -> Bool = RestaurantMatcher.isNonChainWord
    ) -> (chain: RestaurantChain, remainder: String, fuzzy: Bool)? {
        let qw = words(query)
        guard !qw.isEmpty else { return nil }
        var prefixes: [String] = []
        var acc = ""
        for w in qw { acc += w; prefixes.append(acc) }

        var best: (chain: RestaurantChain, consumed: Int)?
        for chain in chains {
            for (i, p) in prefixes.enumerated() where p.count >= 2 && chain.matchKeys.contains(p) {
                let n = i + 1
                if best == nil || n > best!.consumed { best = (chain, n) }
            }
        }
        if let best { return (best.chain, qw[best.consumed...].joined(separator: " "), false) }

        var fuzzy: (chain: RestaurantChain, consumed: Int)?
        for (i, p) in prefixes.enumerated() where p.count >= minTypoLength && !isFoodWord(p) {
            let a = Array(p)
            let near = chains.filter { chain in
                chain.matchKeys.contains { editDistance(a, Array($0), cap: 1) == 1 }
            }
            if near.count == 1 { fuzzy = (near[0], i + 1) }   // longest leading match wins
        }
        guard let fuzzy else { return nil }
        return (fuzzy.chain, qw[fuzzy.consumed...].joined(separator: " "), true)
    }

    /// Menu items matching `query`: every query word must prefix a word of the
    /// item name or its category (or share its singular form — "fry" finds
    /// "Fries", never "Fried"), or appear inside the run-together item name
    /// ("burger" finds "ShackBurger"). Ranked: all words hit the item name before
    /// category-only hits; within that, the name with the fewest words beyond the
    /// query (so "shackburger" puts "Single ShackBurger" above "ShackBurger, Single
    /// Lettuce Wrap"), then a name that starts with the query; menu order breaks
    /// ties. Blank query → the whole menu in order.
    public static func filter(_ items: [RestaurantMenuItem], query: String) -> [RestaurantMenuItem] {
        let qw = words(query)
        guard !qw.isEmpty else { return items }
        let q = qw.joined()
        var hits: [(item: RestaurantMenuItem, rank: [Int])] = []
        for item in items {
            let nameWords = item.nameWords
            let compactName = nameWords.joined()
            let catWords = item.categoryWords
            var allInName = true
            var matched = true
            for w in qw {
                if nameWords.contains(where: { FoodSearchQuery.hits(w, $0) }) || compactName.contains(w) { continue }
                allInName = false
                if !catWords.contains(where: { FoodSearchQuery.hits(w, $0) }) { matched = false; break }
            }
            guard matched else { continue }
            let extraWords = max(0, nameWords.count - qw.count)
            let rank = [allInName ? 0 : 1, extraWords, compactName.hasPrefix(q) ? 0 : 1, item.sortOrder]
            hits.append((item, rank))
        }
        return hits
            .sorted { $0.rank.lexicographicallyPrecedes($1.rank) }
            .map(\.item)
    }

    /// Fixes one misspelled query word against THIS menu: the word itself when
    /// any item accepts it (as `filter` would), else the single menu word ≥4
    /// letters one edit away (most frequent first, then A–Z), else nil. Scoped
    /// to the menu on purpose — "fires" is a word, but at Shake Shack the user
    /// meant "fries".
    static func menuCorrection(for w: String, in items: [RestaurantMenuItem]) -> String? {
        guard w.count >= SearchVocabulary.minCorrectableLength, w.allSatisfy(\.isLetter) else { return nil }
        var freq: [String: Int] = [:]
        for item in items {
            let compact = item.nameWords.joined()
            if item.nameWords.contains(where: { FoodSearchQuery.hits(w, $0) }) || compact.contains(w)
                || item.categoryWords.contains(where: { FoodSearchQuery.hits(w, $0) }) { return w }
            for word in item.nameWords + item.categoryWords where word.count >= 4 && word.allSatisfy(\.isLetter) {
                freq[word, default: 0] += 1
            }
        }
        let a = Array(w)
        let near = freq.filter { editDistance(a, Array($0.key), cap: 1) == 1 }
        return near.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
    }

    /// Edit distance (insert / delete / substitute, plus an adjacent swap as ONE
    /// edit — optimal string alignment: "freis" ↔ "fries" = 1), short-circuiting
    /// once two consecutive rows all exceed `cap`.
    static func editDistance(_ a: [Character], _ b: [Character], cap: Int) -> Int {
        if abs(a.count - b.count) > cap { return cap + 1 }
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var prevPrev: [Int] = []
        var prev = Array(0...b.count)
        var prevMin = 0
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            var rowMin = cur[0]
            for j in stride(from: 1, through: b.count, by: 1) {
                var v = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    v = min(v, prevPrev[j - 2] + 1)
                }
                cur[j] = v
                rowMin = min(rowMin, v)
            }
            // A swap reaches two rows back, so only give up when both rows are over.
            if rowMin > cap, prevMin > cap { return cap + 1 }
            prevPrev = prev
            prev = cur
            prevMin = rowMin
        }
        return prev[b.count]
    }
}

// MARK: - Catalog (in-memory, loaded once)

public final class RestaurantCatalog: Sendable {

    public let chains: [RestaurantChain]
    private let itemsBySlug: [String: [RestaurantMenuItem]]

    /// Read once from the bundled database on first use (a few ms). Touch it off
    /// the main thread early (AddFoodSheet does) so the first keystroke is free.
    public static let shared = RestaurantCatalog(database: .shared)

    public init(chains: [RestaurantChain], items: [RestaurantMenuItem]) {
        self.chains = chains
        self.itemsBySlug = Dictionary(grouping: items, by: \.chainSlug)
            .mapValues { $0.sorted { $0.sortOrder < $1.sortOrder } }
    }

    public convenience init(database: SQLiteFoodDatabase) {
        let data = database.restaurantData()
        self.init(chains: data.chains, items: data.items)
    }

    public var isEmpty: Bool { chains.isEmpty }

    /// The chain's whole menu, in source order.
    public func menu(for slug: String) -> [RestaurantMenuItem] { itemsBySlug[slug] ?? [] }

    public func split(
        _ query: String, isFoodWord: (String) -> Bool = RestaurantMatcher.isNonChainWord
    ) -> (chain: RestaurantChain, remainder: String, fuzzy: Bool)? {
        RestaurantMatcher.split(query, chains: chains, isFoodWord: isFoodWord)
    }

    /// Item-name words of every menu, for the search vocabulary.
    var itemWordLists: [[String]] { itemsBySlug.values.flatMap { $0.map(\.nameWords) } }

    /// Every chain name / alias run together, for the search vocabulary.
    var chainKeys: [String] { chains.flatMap(\.matchKeys) }

    /// "shake shack fries" → Shake Shack's items matching "fries", best first.
    /// Empty when the query doesn't start with a chain or names only the chain.
    public func menuMatches(for query: String, limit: Int = 8) -> [RestaurantMenuItem] {
        guard let (chain, remainder, _) = split(query), !remainder.isEmpty else { return [] }
        return Array(RestaurantMatcher.filter(menu(for: chain.slug), query: remainder).prefix(limit))
    }
}
