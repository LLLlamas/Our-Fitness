// Shared curated + USDA food search used by the food library and ingredient
// pickers. Lenient on purpose: case, apostrophes, word order, simple plurals
// and spelling variants don't matter ("Donuts" = "donut" = "doughnut";
// "dunkin donut" finds "Dunkin' glazed donut"). Curated `CommonFoods` matches
// lead; the offline USDA database broadens the results, with curated entries
// winning on name so duplicates never appear. Order (`merged`): close curated
// matches (tier ≤ 2) → close USDA matches (tier ≤ 1) → loose curated (tier 3)
// → other USDA → bulk/package USDA rows ("22lb 1ct", a flat 100 g) last. USDA
// rows keep the database's FTS relevance as the tie-break — not A–Z, which
// buried plain "Rice Krispies" under its colour variants — after match
// quality, chains rare near NYC (`RegionalChains`) and household-measure
// labels before weight/package-only ones (`ServingSanity`).

import Foundation

public enum FoodSearch {

    public static func combined(matching query: String) async -> [CommonFood] {
        await combined(FoodSearchQuery(query), index: .shared, database: .shared)
    }

    static func combined(_ q: FoodSearchQuery, index: CuratedSearchIndex, database: SQLiteFoodDatabase) async -> [CommonFood] {
        guard !q.isEmpty else { return [] }
        let curated = index.rankedMatches(q)
        let curatedNames = Set(curated.map { $0.food.name.lowercased() })
        let usda = await database.searchAsync(ftsQuery: q.ftsQuery, limit: 60)
            .map { $0.asCommonFood }
            .enumerated()
            .compactMap { rank, food -> USDAHit? in
                guard !curatedNames.contains(food.name.lowercased()),
                      let tier = q.tier(of: food) else { return nil }
                return USDAHit(food: food, tier: tier, ftsRank: rank)
            }
        return merged(curated: curated, usda: usda)
    }

    /// One USDA row that passed `tier`, with its position in the FTS result.
    struct USDAHit {
        let food: CommonFood
        let tier: Int
        let ftsRank: Int
    }

    /// Curated (already ranked) and USDA hits in one list — see the file header
    /// for the bands. Within a band the incoming order is kept.
    static func merged(curated: [(food: CommonFood, tier: Int)], usda: [USDAHit]) -> [CommonFood] {
        let sortedUSDA = usda.sorted { a, b in
            let bulkA = ServingSanity.isBulk(a.food), bulkB = ServingSanity.isBulk(b.food)
            if bulkA != bulkB { return !bulkA }
            if a.tier != b.tier { return a.tier < b.tier }
            let ra = RegionalChains.isRareNearby(foodId: a.food.id)
            let rb = RegionalChains.isRareNearby(foodId: b.food.id)
            if ra != rb { return !ra }
            let la = ServingSanity.labelRank(a.food.servingLabel)
            let lb = ServingSanity.labelRank(b.food.servingLabel)
            if la != lb { return la < lb }
            return a.ftsRank < b.ftsRank
        }
        let bands: [(band: Int, food: CommonFood)] =
            curated.map { ($0.tier <= 2 ? 0 : 2, $0.food) }
            + sortedUSDA.map { (ServingSanity.isBulk($0.food) ? 4 : ($0.tier <= 1 ? 1 : 3), $0.food) }
        return (0...4).flatMap { b in bands.filter { $0.band == b }.map(\.food) }
    }

    /// Model-proposed alternative queries made safe to show: trimmed, blanks and
    /// repeats (case-insensitive) dropped, anything equal to what was typed
    /// dropped, at most `maxSuggestions`. Order kept.
    static let maxSuggestions = 3

    static func cleanSuggestions(_ suggestions: [String], raw: String) -> [String] {
        let typed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var seen: Set<String> = [typed]
        var out: [String] = []
        for s in suggestions {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, seen.insert(t.lowercased()).inserted else { continue }
            out.append(t)
            if out.count == maxSuggestions { break }
        }
        return out
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
    public func tier(name: String, aliases: [String], aliasesCanBeExact: Bool = true) -> Int? {
        let nameWords = Self.normalizedWords(name)
        let aliasWords = aliases.map(Self.normalizedWords)
        return tier(nameWords: nameWords, aliasWords: aliasWords, aliasesCanBeExact: aliasesCanBeExact)
    }

    /// `tier` for a search result. A USDA row's alias never counts as exact:
    /// branded aliases are [description, brand, category] and generic ones the
    /// description's comma segments, so "cheese" or "cereal" alone would make
    /// every fondue and bran bud an exact match. Curated aliases are hand-written
    /// synonyms and still count.
    public func tier(of food: CommonFood) -> Int? {
        tier(name: food.name, aliases: food.aliases, aliasesCanBeExact: !food.id.hasPrefix("usda-"))
    }

    func tier(nameWords: [String], aliasWords: [[String]], aliasesCanBeExact: Bool = true) -> Int? {
        guard !words.isEmpty else { return nil }
        func same(_ ws: [String]) -> Bool {
            ws.count == words.count && zip(ws, words).allSatisfy { t, q in
                let tf = Self.forms(t)
                return Self.forms(q).contains { tf.contains($0) }
            }
        }
        if same(nameWords) || (aliasesCanBeExact && aliasWords.contains(where: same)) { return 0 }
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
        // AND, not a bare space: FTS5 rejects a space before a parenthesised OR
        // group ("syntax error near ("), which zeroed every multi-word query
        // with a plural or spelling variant ("shake shack fries").
        .joined(separator: " AND ")
    }
}

// MARK: - Curated index (built once)

/// Pre-normalized name/alias words for every curated food, so a search is a
/// pass over small arrays instead of re-normalizing ~5k aliases per keystroke.
final class CuratedSearchIndex: Sendable {
    static let shared = CuratedSearchIndex(CommonFoods.all, catalog: .shared)

    private let entries: [(food: CommonFood, name: [String], aliases: [[String]])]
    /// Typo-correction words: curated names + aliases, `catalog`'s menu-item
    /// words and chain keys (`SearchVocabulary`).
    let vocabulary: SearchVocabulary

    init(_ foods: [CommonFood], catalog: RestaurantCatalog? = nil) {
        let built = foods.map { food in
            (food: food, name: FoodSearchQuery.normalizedWords(food.name),
             aliases: food.aliases.map(FoodSearchQuery.normalizedWords))
        }
        entries = built
        vocabulary = SearchVocabulary(
            wordLists: built.flatMap { [$0.name] + $0.aliases } + (catalog?.itemWordLists ?? []),
            chainKeys: catalog?.chainKeys ?? [])
    }

    func matches(_ q: FoodSearchQuery) -> [CommonFood] {
        rankedMatches(q).map(\.food)
    }

    /// `matches` with each food's tier, for `FoodSearch.merged`.
    func rankedMatches(_ q: FoodSearchQuery) -> [(food: CommonFood, tier: Int)] {
        let hits = entries.compactMap { e in
            q.tier(nameWords: e.name, aliasWords: e.aliases).map { (e.food, $0) }
        }
        let tiers = Dictionary(hits.map { ($0.0.id, $0.1) }, uniquingKeysWith: min)
        return FoodSearch.ranked(hits).map { ($0, tiers[$0.id] ?? 3) }
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

// MARK: - Serving sanity (USDA rows)

/// Makes USDA rows read the way a person logs a meal, without inventing data:
/// labels and names are only reworded, and every gram weight and macro stays
/// what the database holds. Applied in `FoodDatabaseEntry.asCommonFood` to
/// `usda-` rows; also feeds `FoodSearch.merged`'s ordering.
public enum ServingSanity {

    /// Generic (SR Legacy / Foundation) rows got one of these labels from
    /// `scripts/build-food-db.py` `SERVING_RULES`, matched against the WHOLE
    /// description — so "Bread, oatmeal" got the oatmeal rule's "1 cup cooked".
    /// Pattern = the script's keyword regex; nil = the script's fallback.
    static let genericRules: [(label: String, pattern: String?, grams: String)] = [
        ("1 tbsp (14 g)", #"\b(oil|butter|margarine|lard|shortening)\b"#, "14 g"),
        ("1 tbsp (20 g)", #"\b(mayonnaise|ketchup|mustard|honey|syrup|jam|jelly)\b"#, "20 g"),
        ("1 oz (28 g)", #"\b(cheese|nuts?|almonds?|walnuts?|pecans?|cashews?|pistachios?|seeds?)\b"#, "1 oz (28 g)"),
        ("4 oz cooked (113 g)", #"\b(chicken|beef|pork|turkey|fish|salmon|cod|tilapia|tuna|shrimp|lamb|steak)\b"#, "4 oz (113 g)"),
        ("1 cup cooked (158 g)", #"\b(rice|pasta|quinoa|couscous|barley|oats?|oatmeal)\b"#, "158 g"),
        ("1 slice/piece (40 g)", #"\b(bread|bagel|tortilla|roll)\b"#, "40 g"),
        ("1 cup (240 g)", #"\b(milk|juice|beverage|drink)\b"#, "240 g"),
        ("1 medium (150 g)", #"\b(apple|banana|orange|pear|peach|plum)\b"#, "150 g"),
        ("1 cup (150 g)", nil, "150 g"),
    ]

    /// The row as shown: generic rows get a readable name and an honest label,
    /// branded labels lose their raw unit codes. Non-USDA rows pass through.
    public static func tidied(_ food: CommonFood) -> CommonFood {
        guard food.id.hasPrefix("usda-") else { return food }
        var out = food
        if let rule = genericRules.first(where: { $0.label == food.servingLabel }),
           let description = food.aliases.first, description.contains(",") {
            let segments = description.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let first = segments[0]
            if food.name.lowercased() == first.lowercased() {
                // "Cheese" ×300 → "Cheese, cheddar"; up to three segments.
                let name = segments.prefix(3).joined(separator: ", ")
                out = CommonFood(id: food.id, name: name.prefix(1).uppercased() + name.dropFirst(),
                                 aliases: food.aliases, servingLabel: food.servingLabel,
                                 calories: food.calories, proteinG: food.proteinG, carbsG: food.carbsG,
                                 fatG: food.fatG, fiberG: food.fiberG)
            }
            // The household word is real only when the rule's keyword names the food itself.
            let real = rule.pattern.map { first.lowercased().range(of: $0, options: .regularExpression) != nil } ?? false
            if !real { out = relabeled(out, rule.grams) }
            return out
        }
        let human = humanizedLabel(food.servingLabel)
        return human == food.servingLabel ? out : relabeled(out, human)
    }

    private static func relabeled(_ f: CommonFood, _ label: String) -> CommonFood {
        CommonFood(id: f.id, name: f.name, aliases: f.aliases, servingLabel: label,
                   calories: f.calories, proteinG: f.proteinG, carbsG: f.carbsG,
                   fatG: f.fatG, fiberG: f.fiberG)
    }

    /// Branded label text as people write it: "40GRM" → "40 g", "4 ONZ" → "4 oz",
    /// "8 OZA" → "8 fl oz", "1 SLICE" → "1 slice", "0.5 cup" → "½ cup".
    public static func humanizedLabel(_ label: String) -> String {
        var s = label.trimmingCharacters(in: .whitespaces)
        for (code, unit) in [("GRM", "g"), ("ONZ", "oz"), ("OZA", "fl oz"), ("MLT", "ml")] {
            s = s.replacingOccurrences(of: #"(\d)\s*"# + code + #"\b"#, with: "$1 " + unit,
                                       options: [.regularExpression, .caseInsensitive])
        }
        if s.rangeOfCharacter(from: .lowercaseLetters) == nil { s = s.lowercased() }
        for (decimal, fraction) in [("0.25", "¼"), ("0.5", "½"), ("0.75", "¾"), ("0.33", "⅓"), ("0.67", "⅔")] {
            s = s.replacingOccurrences(of: "^" + NSRegularExpression.escapedPattern(for: decimal) + #"(?=\s)"#,
                                       with: fraction, options: .regularExpression)
        }
        return s
    }

    /// Bulk / institutional rows nobody logs for one meal: a package size in
    /// the name ("Kellogg Rice Krispies Cereal 22lb 1ct") or a flat 100 g label
    /// (the branded fallback when the label had no serving).
    public static func isBulk(_ food: CommonFood) -> Bool {
        guard food.id.hasPrefix("usda-") else { return false }
        if food.name.range(of: #"\d\s?(lb|lbs|ct|count|pk|pack)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        return food.servingLabel.range(of: #"^100\s?(g|grams?)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// 0 = a household measure ("1 cup", "1 slice", "2 tbsp"); 1 = weight-only
    /// ("40 g", "4 oz", "1 oz (28 g)") or a package unit ("1 container", "1/5 package").
    public static func labelRank(_ label: String) -> Int {
        let l = label.lowercased()
        if l.range(of: #"^[\d./¼½¾⅓⅔\s]+(g|grams?|oz|fl oz|ml)\b"#, options: .regularExpression) != nil { return 1 }
        if l.range(of: #"\b(container|package|pkg|box|pouch|bag)\b"#, options: .regularExpression) != nil { return 1 }
        return 0
    }
}
