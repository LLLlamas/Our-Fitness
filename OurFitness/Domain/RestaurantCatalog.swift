// Restaurant / chain menus — "I ate at Shake Shack".
//
// Data: `scripts/restaurant-data/<slug>.json` → `scripts/build-food-db.py` →
// two small tables in the bundled `usda-foods.db` (`restaurant_chains`,
// `restaurant_items`). Each item is ALSO an ordinary `foods` row
// (`rest:<slug>:<item>`, name "<Chain> <Item>"), so plain food search and the
// parser find it with no special casing; this file adds what search can't:
//   • chain matches for a typed query ("shakesha" → Shake Shack), shown as the
//     Restaurants row in `AddFoodSheet`;
//   • a chain's menu grouped by its own categories, in source order
//     (`RestaurantMenuView`);
//   • splitting "shake shack fries" into (Shake Shack, "fries") so that chain's
//     fries rank first among the individual matches.
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
    /// A packaged-product brand (protein powder, gainer, bars) rather than a
    /// restaurant — same data shape, different copy ("Products" vs "Menu").
    public var isBrand: Bool { kind == "supplement" }
    public let itemCount: Int
    public var id: String { slug }

    /// Name + aliases run together ("shakeshack"), computed once so a keystroke
    /// never re-folds strings.
    let matchKeys: [String]
    /// The name from its 2nd, 3rd… word on ("canes" for Raising Cane's).
    let nameTails: [String]

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
        let nameWords = RestaurantMatcher.words(name)
        self.nameTails = nameWords.indices.dropFirst().map { nameWords[$0...].joined() }
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

public struct RestaurantMenuSection: Identifiable, Sendable, Equatable {
    public let category: String
    public let items: [RestaurantMenuItem]
    public var id: String { category }
}

// MARK: - Matching (pure)

public enum RestaurantMatcher {

    /// Shortest query that may prefix-match a chain. Two letters ("sh") would
    /// light up half the list; an exact alias ("og") still matches at 2.
    public static let minPrefixLength = 3
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

    /// Lower is better; nil = no match.
    ///   0 — the whole name or an alias, exactly ("shake shack", "shakeshack", "og")
    ///   1 — a prefix of the name or an alias ("shakesha", "shake sh")
    ///   2 — a prefix starting at a later word of the NAME ("cane" → Raising Cane's)
    ///   3 — one typo against the name/alias prefix ("shakshack")
    ///
    /// Deliberate: a bare first word ("shake", "olive") DOES match at tier 1. The
    /// restaurant row is one compact row above the unchanged food results, so a
    /// false positive costs a glance; refusing "taco" → Taco Bell or "shack" →
    /// Shake Shack would cost the feature.
    public static func score(_ chain: RestaurantChain, query: String) -> Int? {
        score(chain, normalized: normalize(query))
    }

    static func score(_ chain: RestaurantChain, normalized q: String) -> Int? {
        guard q.count >= 2 else { return nil }
        let fulls = chain.matchKeys
        if fulls.contains(q) { return 0 }
        guard q.count >= minPrefixLength else { return nil }
        if fulls.contains(where: { $0.hasPrefix(q) }) { return 1 }
        if chain.nameTails.contains(where: { $0.hasPrefix(q) }) { return 2 }
        if q.count >= minTypoLength, fulls.contains(where: { withinOneEditOfPrefix(q, of: $0) }) { return 3 }
        return nil
    }

    /// Chains matching `query`, best first (score, then name). A query that
    /// STARTS with a chain ("shake shack fries") includes that chain first.
    public static func chains(matching query: String, in chains: [RestaurantChain], limit: Int = 3) -> [RestaurantChain] {
        let q = normalize(query)
        var ranked = chains
            .compactMap { c in score(c, normalized: q).map { (c, $0) } }
            .sorted { ($0.1, $0.0.name) < ($1.1, $1.0.name) }
            .map(\.0)
        if let lead = split(query, chains: chains)?.chain {
            ranked.removeAll { $0.slug == lead.slug }
            ranked.insert(lead, at: 0)
        }
        return Array(ranked.prefix(limit))
    }

    /// Splits "shake shack fries" / "shakeshack fries" / "raising canes box"
    /// into (chain, remainder) when the query's leading words spell a chain's
    /// whole name or an alias. The longest leading match wins. Remainder may be
    /// empty ("shake shack"). Partial chain names don't split — "shake fries"
    /// stays a plain food search.
    public static func split(_ query: String, chains: [RestaurantChain]) -> (chain: RestaurantChain, remainder: String)? {
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
        guard let best else { return nil }
        return (best.chain, qw[best.consumed...].joined(separator: " "))
    }

    /// Menu items matching `query`: every query word must prefix a word of the
    /// item name or its category, or appear inside the run-together item name
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
                if nameWords.contains(where: { $0.hasPrefix(w) }) || compactName.contains(w) { continue }
                allInName = false
                if !catWords.contains(where: { $0.hasPrefix(w) }) { matched = false; break }
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

    /// Items grouped by category; categories in order of first appearance,
    /// items in menu order.
    public static func sections(_ items: [RestaurantMenuItem]) -> [RestaurantMenuSection] {
        var order: [String] = []
        var byCategory: [String: [RestaurantMenuItem]] = [:]
        for item in items.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            if byCategory[item.category] == nil { order.append(item.category) }
            byCategory[item.category, default: []].append(item)
        }
        return order.map { RestaurantMenuSection(category: $0, items: byCategory[$0] ?? []) }
    }

    /// True when `q` is within one edit (insert/delete/substitute) of some
    /// prefix of `key` — prefixes of length |q|-1 … |q|+1.
    static func withinOneEditOfPrefix(_ q: String, of key: String) -> Bool {
        let a = Array(q), b = Array(key)
        let lo = max(0, a.count - 1), hi = min(b.count, a.count + 1)
        guard lo <= hi else { return false }   // key too short to be one edit away
        for len in lo...hi {
            if editDistance(a, Array(b[0..<len]), cap: 1) <= 1 { return true }
        }
        return false
    }

    /// Levenshtein distance, short-circuiting once every cell exceeds `cap`.
    static func editDistance(_ a: [Character], _ b: [Character], cap: Int) -> Int {
        if abs(a.count - b.count) > cap { return cap + 1 }
        guard !a.isEmpty else { return b.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            var rowMin = cur[0]
            for j in stride(from: 1, through: b.count, by: 1) {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                rowMin = min(rowMin, cur[j])
            }
            if rowMin > cap { return cap + 1 }
            prev = cur
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

    public func chains(matching query: String, limit: Int = 3) -> [RestaurantChain] {
        RestaurantMatcher.chains(matching: query, in: chains, limit: limit)
    }

    /// The chain's whole menu, in source order.
    public func menu(for slug: String) -> [RestaurantMenuItem] { itemsBySlug[slug] ?? [] }

    public func sections(for slug: String) -> [RestaurantMenuSection] {
        RestaurantMatcher.sections(menu(for: slug))
    }

    public func split(_ query: String) -> (chain: RestaurantChain, remainder: String)? {
        RestaurantMatcher.split(query, chains: chains)
    }

    /// "shake shack fries" → Shake Shack's items matching "fries", best first.
    /// Empty when the query doesn't start with a chain or names only the chain.
    public func menuMatches(for query: String, limit: Int = 8) -> [RestaurantMenuItem] {
        guard let (chain, remainder) = split(query), !remainder.isEmpty else { return [] }
        return Array(RestaurantMatcher.filter(menu(for: chain.slug), query: remainder).prefix(limit))
    }
}
