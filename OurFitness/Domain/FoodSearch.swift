// Shared curated + USDA food search used by the food library and ingredient
// pickers. Lenient on purpose: case, apostrophes, word order, simple plurals
// and spelling variants don't matter ("Donuts" = "donut" = "doughnut";
// "dunkin donut" finds "Dunkin' glazed donut"). Curated `CommonFoods` matches
// come first; the offline USDA database broadens the results, with curated
// entries winning on name so duplicates never appear. Each block is ranked by
// match quality, then A–Z — chains rarely found near NYC sort after the rest
// at the same quality (`RegionalChains`).

import Foundation

public enum FoodSearch {

    public static func combined(matching query: String) async -> [CommonFood] {
        let q = FoodSearchQuery(query)
        guard !q.isEmpty else { return [] }
        let curated = CuratedSearchIndex.shared.matches(q)
        let curatedNames = Set(curated.map { $0.name.lowercased() })
        let usda = await SQLiteFoodDatabase.shared.searchAsync(ftsQuery: q.ftsQuery, limit: 60)
            .map { $0.asCommonFood }
            .filter { !curatedNames.contains($0.name.lowercased()) }
            .compactMap { food in q.tier(name: food.name, aliases: food.aliases).map { (food, $0) } }
        return curated + ranked(usda)
    }

    /// Match quality, then foods from chains rare near NYC last, then A–Z.
    static func ranked(_ hits: [(CommonFood, Int)]) -> [CommonFood] {
        hits.sorted { a, b in
            let ra = RegionalChains.isRareNearby(foodId: a.0.id)
            let rb = RegionalChains.isRareNearby(foodId: b.0.id)
            if a.1 != b.1 { return a.1 < b.1 }
            if ra != rb { return !ra }
            return a.0.name.localizedCaseInsensitiveCompare(b.0.name) == .orderedAscending
        }
        .map(\.0)
    }
}

// MARK: - Query normalization

/// A typed query, normalized the same way as the food text it is matched
/// against, so the rules only need to be consistent — not linguistically perfect.
public struct FoodSearchQuery: Sendable {
    /// Words that must each hit the food (stopwords removed unless that's all there is).
    public let words: [String]
    /// The words run together ("chick fil a" → "chickfila"), for run-together names.
    public let compact: String

    static let stopwords: Set<String> = ["and", "with", "of", "the", "a", "n", "w", "or"]

    /// Spelling variants folded to one form, applied to query and food text alike.
    static let spellings: [String: String] = [
        "doughnut": "donut", "doughnuts": "donuts",
        "barbecue": "bbq", "barbeque": "bbq",
        "yoghurt": "yogurt", "yoghurts": "yogurts",
        "omelette": "omelet", "omelettes": "omelets",
        "kabob": "kebab", "kebob": "kebab", "kabab": "kebab",
        "kabobs": "kebabs", "kebobs": "kebabs",
        "catsup": "ketchup", "chilli": "chili", "expresso": "espresso",
        "hotdog": "hot dog", "hotdogs": "hot dogs",
    ]

    public init(_ text: String) {
        let all = Self.normalizedWords(text)
        let kept = all.filter { !Self.stopwords.contains($0) }
        words = kept.isEmpty ? all : kept
        compact = all.joined()
    }

    public var isEmpty: Bool { words.isEmpty }

    /// Lowercased, accent/apostrophe-folded words with spelling variants mapped.
    static func normalizedWords(_ text: String) -> [String] {
        RestaurantMatcher.words(text).flatMap { w -> [String] in
            guard let s = spellings[w] else { return [w] }
            return s.split(separator: " ").map(String.init)
        }
    }

    /// The word plus its singular forms: "donuts" → [donuts, donut],
    /// "berries" → [berries, berry, berrie], "cookies" → [cookies, cooky, cookie],
    /// "sandwiches" → [sandwiches, sandwich, sandwiche]. Only exact forms are
    /// compared (never a prefix of a singular), so "fries" → "frie" can't hit "fried".
    static func forms(_ w: String) -> [String] {
        guard w.count > 3, w.hasSuffix("s"), !w.hasSuffix("ss"),
              !w.hasSuffix("us"), !w.hasSuffix("is") else { return [w] }
        if w.hasSuffix("ies") { return [w, String(w.dropLast(3)) + "y", String(w.dropLast())] }
        if w.hasSuffix("es") { return [w, String(w.dropLast(2)), String(w.dropLast())] }
        return [w, String(w.dropLast())]
    }

    /// A query word hits a food word when the food word starts with it (typing
    /// in progress) or the two share a singular form ("donuts" ↔ "donut").
    static func hits(_ q: String, _ t: String) -> Bool {
        if t.hasPrefix(q) { return true }
        let tf = forms(t)
        return forms(q).contains { tf.contains($0) }
    }

    /// Lower is better; nil = no match.
    ///   0 — the name or an alias is exactly the query ("donut", "Donuts")
    ///   1 — the name starts with the query and holds every word
    ///   2 — every word is in the name
    ///   3 — every word is somewhere in the name + aliases, or the run-together
    ///       query sits inside a run-together name/alias ("chickfila")
    public func tier(name: String, aliases: [String]) -> Int? {
        let nameWords = Self.normalizedWords(name)
        let aliasWords = aliases.map(Self.normalizedWords)
        return tier(nameWords: nameWords, aliasWords: aliasWords)
    }

    func tier(nameWords: [String], aliasWords: [[String]]) -> Int? {
        guard !words.isEmpty else { return nil }
        func same(_ ws: [String]) -> Bool {
            ws.count == words.count && zip(ws, words).allSatisfy { t, q in
                let tf = Self.forms(t)
                return Self.forms(q).contains { tf.contains($0) }
            }
        }
        if same(nameWords) || aliasWords.contains(where: same) { return 0 }
        func allHit(_ ws: [String]) -> Bool {
            words.allSatisfy { q in ws.contains { Self.hits(q, $0) } }
        }
        if allHit(nameWords) {
            if let first = nameWords.first, Self.hits(words[0], first) { return 1 }
            return 2
        }
        if allHit(nameWords + aliasWords.flatMap { $0 }) { return 3 }
        if compact.count >= 4, ([nameWords] + aliasWords).contains(where: { $0.joined().contains(compact) }) {
            return 3
        }
        return nil
    }

    /// FTS5 query for the USDA table: each word as a prefix, OR'd with its
    /// singular forms and spelling variants ("donuts" → (donuts* OR donut* OR doughnut*)).
    /// Deliberately loose — results are re-checked with `tier` before showing.
    public var ftsQuery: String {
        words.map { w in
            var alts = Self.forms(w)
            for (variant, canonical) in Self.spellings where alts.contains(canonical) {
                alts.append(variant)
            }
            let terms = Array(Set(alts)).sorted().map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }
            return terms.count == 1 ? terms[0] : "(" + terms.joined(separator: " OR ") + ")"
        }
        .joined(separator: " ")
    }
}

// MARK: - Curated index (built once)

/// Pre-normalized name/alias words for every curated food, so a search is a
/// pass over small arrays instead of re-normalizing ~5k aliases per keystroke.
final class CuratedSearchIndex: Sendable {
    static let shared = CuratedSearchIndex(CommonFoods.all)

    private let entries: [(food: CommonFood, name: [String], aliases: [[String]])]

    init(_ foods: [CommonFood]) {
        entries = foods.map { food in
            (food, FoodSearchQuery.normalizedWords(food.name), food.aliases.map(FoodSearchQuery.normalizedWords))
        }
    }

    func matches(_ q: FoodSearchQuery) -> [CommonFood] {
        FoodSearch.ranked(entries.compactMap { e in
            q.tier(nameWords: e.name, aliasWords: e.aliases).map { (e.food, $0) }
        })
    }
}

// MARK: - Regional ordering

/// Chains with few or no locations around New York City (the app's home
/// market). Used only as a tie-break so East Coast chains surface first —
/// nothing is hidden. Store footprints change; this list is a judgement call,
/// not sourced data.
public enum RegionalChains {
    public static let rareNearNYC: Set<String> = [
        "carls-jr", "culvers", "del-taco", "dutch-bros", "el-pollo-loco",
        "habit-burger", "in-n-out", "sheetz", "waffle-house", "whataburger", "zaxbys",
    ]

    /// Curated fast-food ids that predate the slugs (`ff-innout-…`).
    static let curatedPrefixes = ["ff-innout", "ff-in-n-out", "ff-culvers", "ff-whataburger",
                                  "ff-carls", "ff-del-taco", "ff-el-pollo", "ff-habit",
                                  "ff-dutch", "ff-sheetz", "ff-waffle-house", "ff-zaxby"]

    public static func isRare(slug: String) -> Bool { rareNearNYC.contains(slug) }

    /// `rest:<slug>:<item>` restaurant rows and the curated `ff-` equivalents.
    public static func isRareNearby(foodId: String) -> Bool {
        if foodId.hasPrefix("rest:") {
            let slug = foodId.dropFirst(5).split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
            return rareNearNYC.contains(slug)
        }
        return foodId.hasPrefix("ff-") && curatedPrefixes.contains { foodId.hasPrefix($0) }
    }
}
