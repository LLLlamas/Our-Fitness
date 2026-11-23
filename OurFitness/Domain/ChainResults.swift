// Typed-search results when the query starts with a restaurant chain
// ("mcdonalds fries", "starbucks latte").
//
// `RestaurantMatcher.split` peels the chain off; this file arranges what comes
// back so the list reads as that chain's menu, not a pile of near-duplicates:
//   • the chain's own items first, sizes collapsed into ONE row per item
//     (Small / Medium / Large of the same fries) with the default size shown
//     and the others offered as inline choices (`SizeChoice`);
//   • at most `maxChainGroups` item groups;
//   • curated `ff-` rows of that chain are dropped when official `rest:` rows
//     exist (the same food from a second source), other chains' rows are
//     dropped, and what's left (USDA / curated) is capped at `maxOtherRows`.
//
// Domain layer: Foundation only.

import Foundation

/// One size of a chain item ("Medium", "10 pc") and the row that logs it.
struct SizeChoice: Equatable, Sendable, Identifiable {
    let label: String
    let food: CommonFood
    var id: String { food.id }
}

/// Everything a typed search shows: the rows, the size choices for rows that
/// stand for several sizes (keyed by the shown row's id), and — when the
/// query's spelling was fixed — what it was fixed to.
struct FoodSearchOutcome: Sendable {
    var foods: [CommonFood] = []
    var sizeChoices: [String: [SizeChoice]] = [:]
    var correctedQuery: String?
    /// How sure the results are that they answer the query (see `MatchStrength`).
    var strength: MatchStrength = .none
}

/// How well the top result answers the typed query.
///   none   — nothing found
///   weak   — something found, but only loosely (the words are spread over name
///            and aliases, or the best food merely contains them)
///   strong — a chain's own menu items matched, or the best food is named
///            exactly / starts with the query (`FoodSearchQuery.tier` ≤ 1)
enum MatchStrength: Sendable, Equatable {
    case none, weak, strong
}

enum SizeVariants {

    /// Display order, smallest first. Tall = small, Grande = medium+ (Starbucks).
    private static let ranks: [String: Int] = [
        "kids": 0, "kid": 0, "short": 1, "junior": 1,
        "small": 2, "tall": 2, "regular": 3, "medium": 3,
        "grande": 4, "large": 5, "venti": 6, "trenta": 7,
    ]
    private static let pieceUnits: Set<String> = ["piece", "pieces", "pc", "pcs", "ct", "count"]
    /// Units that follow a number in a serving label ("16 fl oz", "4 piece").
    private static let servingUnits: Set<String> = ["fl", "oz", "ml", "g", "l", "piece", "pieces", "pc", "pcs", "ct", "count"]

    struct Parsed: Equatable {
        /// Name with the size taken off, folded to words ("world famous fries").
        let base: String
        /// "Medium", "10 pc"; nil when the row carries no size.
        let size: String?
        /// Serving label with size words / volumes / counts removed, so two
        /// sizes of one item compare equal but "oat milk" ≠ "2% milk".
        let servingRest: String
    }

    static func parse(name: String, servingLabel: String) -> Parsed {
        var base = name.trimmingCharacters(in: .whitespaces)
        var size: String?

        // 1. A trailing bracket that is only a size: "Fries (Medium)", "Nuggets (10 piece)".
        if base.hasSuffix(")"), let open = base.lastIndex(of: "(") {
            let inner = String(base[base.index(after: open)..<base.index(before: base.endIndex)])
            if let label = sizeLabel(RestaurantMatcher.words(inner)) {
                size = label
                base = String(base[..<open])
            }
        }
        // 2. Trailing words: "Fries - Large", "Nuggets 10 pc", "Nuggets 10pc".
        if size == nil {
            let tokens = base.split(separator: " ").map(String.init)
            if tokens.count > 2, let label = pieceLabel(RestaurantMatcher.words(tokens.suffix(2).joined(separator: " "))) {
                size = label
                base = tokens.dropLast(2).joined(separator: " ")
            } else if tokens.count > 1, let label = sizeLabel(RestaurantMatcher.words(tokens[tokens.count - 1])) {
                size = label
                base = tokens.dropLast().joined(separator: " ")
            }
        }
        // 3. Neither in the name → the serving label ("Grande 16 fl oz, 2% milk").
        let servingWords = RestaurantMatcher.words(servingLabel)
        if size == nil {
            if let w = servingWords.first(where: { ranks[$0] != nil }) {
                size = w.prefix(1).uppercased() + w.dropFirst()
            } else {
                size = pieceLabel(servingWords)
            }
        }

        let baseKey = RestaurantMatcher.words(base).joined(separator: " ")
        return Parsed(base: baseKey, size: size, servingRest: servingRest(servingWords))
    }

    /// "medium" → "Medium", ["10","pc"] / ["10pc"] → "10 pc"; nil for anything
    /// that isn't purely a size.
    private static func sizeLabel(_ words: [String]) -> String? {
        guard !words.isEmpty else { return nil }
        if let p = pieceLabel(words) { return p }
        let allowed = words.allSatisfy { ranks[$0] != nil || $0 == "size" }
        guard allowed, words.contains(where: { ranks[$0] != nil }) else { return nil }
        let text = words.joined(separator: " ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// A count of pieces: ["10","piece"], ["10pc"] or one anywhere inside a
    /// longer serving label ("10 piece, 160 g").
    private static func pieceLabel(_ words: [String]) -> String? {
        for (i, w) in words.enumerated() {
            if let n = Int(w), i + 1 < words.count, pieceUnits.contains(words[i + 1]) { return "\(n) pc" }
            let digits = w.prefix { $0.isNumber }
            if !digits.isEmpty, digits.count < w.count, pieceUnits.contains(String(w.dropFirst(digits.count))) {
                return "\(digits) pc"
            }
        }
        return nil
    }

    private static func servingRest(_ words: [String]) -> String {
        var out: [String] = []
        var i = 0
        while i < words.count {
            let w = words[i]
            if ranks[w] != nil || w == "size" { i += 1; continue }
            if Int(w) != nil, i + 1 < words.count, servingUnits.contains(words[i + 1]) {
                i += 2
                if i < words.count, words[i - 1] == "fl", words[i] == "oz" { i += 1 }
                continue
            }
            out.append(w)
            i += 1
        }
        return out.joined(separator: " ")
    }

    static func rank(_ label: String) -> Int {
        let l = label.lowercased()
        if let r = ranks[l] { return r }
        if let n = Int(l.split(separator: " ").first ?? "") { return 100 + n }
        return 50
    }

    /// Medium > Regular > Grande > 10-piece > the first one listed.
    static func defaultIndex(_ labels: [String]) -> Int {
        let lower = labels.map { $0.lowercased() }
        for pick in ["medium", "regular", "grande", "10 pc"] {
            if let i = lower.firstIndex(of: pick) { return i }
        }
        return 0
    }

    /// Collapses size variants of one item into the default-size row. Group
    /// order follows the first appearance in `foods`; at most `maxGroups`
    /// groups come back. A row with no recognisable size is its own group.
    /// `choices[shown.id]` lists every size of that group, smallest first.
    static func group(_ foods: [CommonFood], maxGroups: Int) -> (foods: [CommonFood], choices: [String: [SizeChoice]]) {
        var order: [String] = []
        var members: [String: [(food: CommonFood, size: String?)]] = [:]
        for f in foods {
            let p = parse(name: f.name, servingLabel: f.servingLabel)
            let key = p.size == nil ? "id:\(f.id)" : "\(p.base)|\(p.servingRest)"
            if members[key] == nil { order.append(key) }
            members[key, default: []].append((f, p.size))
        }
        var shown: [CommonFood] = []
        var choices: [String: [SizeChoice]] = [:]
        for key in order.prefix(maxGroups) {
            var group = members[key] ?? []
            var seen = Set<String>()
            group = group.filter { m in m.size.map { seen.insert($0.lowercased()).inserted } ?? true }
            guard group.count > 1 else {
                if let only = group.first { shown.append(only.food) }
                continue
            }
            let primary = group[defaultIndex(group.map { $0.size ?? "" })].food
            let sorted = group.enumerated().sorted {
                let a = rank($0.element.size ?? ""), b = rank($1.element.size ?? "")
                return a != b ? a < b : $0.offset < $1.offset
            }.map(\.element)
            shown.append(primary)
            choices[primary.id] = sorted.map { SizeChoice(label: $0.size ?? "", food: $0.food) }
        }
        return (shown, choices)
    }
}

// MARK: - Chain-aware search

extension FoodSearch {

    static let maxChainGroups = 5
    static let maxOtherRows = 5

    /// The full typed search: curated + USDA rows, and — when the query starts
    /// with a chain — that chain's items first (sizes collapsed), duplicates and
    /// other chains' rows removed, the rest capped.
    static func search(_ raw: String) async -> FoodSearchOutcome {
        // Resolved here (a nonisolated async function) so the first touch of the
        // catalog / index never lands on the main actor.
        await search(raw, catalog: .shared, database: .shared, index: .shared)
    }

    static func search(
        _ raw: String,
        catalog: RestaurantCatalog,
        database: SQLiteFoodDatabase,
        index: CuratedSearchIndex
    ) async -> FoodSearchOutcome {
        guard !FoodSearchQuery(raw).isEmpty else { return FoodSearchOutcome() }
        let plan = index.plan(for: raw, catalog: catalog)
        var found = await combined(FoodSearchQuery(plan.effective), index: index, database: database)
        var corrected = plan.corrected
        guard let (chain, remainder) = plan.chain, !remainder.isEmpty else {
            // A fix that finds nothing must never hide what the typed words would have found.
            var searched = plan.effective
            if corrected != nil, found.isEmpty {
                found = await combined(FoodSearchQuery(raw), index: index, database: database)
                corrected = nil
                searched = raw
            }
            let tierQuery = FoodSearchQuery(searched)
            return FoodSearchOutcome(foods: found, correctedQuery: corrected,
                                     strength: strength(of: found, for: tierQuery, chainHit: false))
        }
        let menu = catalog.menu(for: chain.slug)
        let hits = RestaurantMatcher.filter(menu, query: remainder).map { $0.food.asCommonFood }
        let grouped = SizeVariants.group(hits, maxGroups: maxChainGroups)
        let shownIds = Set(hits.map(\.id))
        // A bare brand row ("Mcdonald's", alias "french fries") adds nothing once
        // the chain's own menu answered; drop usda rows made only of chain words
        // (before any comma — `ServingSanity` names it "Mcdonald's, french fries").
        let chainWords = Set(([chain.name] + chain.aliases).flatMap(FoodSearchQuery.normalizedWords))
        let others = found.filter { f in
            if shownIds.contains(f.id) { return false }
            if !hits.isEmpty, f.id.hasPrefix("usda-") {
                let lead = f.name.split(separator: ",").first.map(String.init) ?? f.name
                let nameWords = FoodSearchQuery.normalizedWords(lead)
                if !nameWords.isEmpty, nameWords.allSatisfy(chainWords.contains) { return false }
            }
            if f.id.hasPrefix("rest:") { return RestaurantChain.slug(ofRestaurantFoodId: f.id) == chain.slug }
            if f.id.hasPrefix("ff-") { return menu.isEmpty && chain.ownsCuratedFastFood(id: f.id) }
            return true
        }
        // No menu hit (e.g. "ghost pepper" split off the Ghost brand): the chain was a
        // false alarm, so don't cap the ordinary results.
        let shown = grouped.foods + others.prefix(hits.isEmpty ? others.count : maxOtherRows)
        return FoodSearchOutcome(foods: shown, sizeChoices: grouped.choices, correctedQuery: corrected,
                                 strength: strength(of: shown, for: FoodSearchQuery(plan.effective),
                                                    chainHit: !hits.isEmpty))
    }

    /// strong = chain menu hit, or the first food ties the query at tier ≤ 1.
    private static func strength(of foods: [CommonFood], for q: FoodSearchQuery, chainHit: Bool) -> MatchStrength {
        guard let first = foods.first else { return .none }
        if chainHit { return .strong }
        if let tier = q.tier(of: first), tier <= 1 { return .strong }
        return .weak
    }
}

/// How a raw query is read: the text actually searched, the chain peeled off
/// it (with the remainder, misspellings fixed), and — only when the spelling
/// changed — the text to show as "Showing results for …".
struct SearchPlan {
    let effective: String
    let chain: (chain: RestaurantChain, remainder: String)?
    let corrected: String?
}

extension CuratedSearchIndex {

    func plan(for raw: String, catalog: RestaurantCatalog) -> SearchPlan {
        let split = catalog.split(raw, isFoodWord: { vocabulary.isFoodWord($0) || RestaurantMatcher.isNonChainWord($0) })
        if let (chain, remainder, fuzzy) = split {
            let original = RestaurantMatcher.words(remainder)
            let menu = catalog.menu(for: chain.slug)
            // This menu's words first ("fires" → Fries at Shake Shack), then the whole vocabulary.
            let fixed = original.map { RestaurantMatcher.menuCorrection(for: $0, in: menu) ?? vocabulary.correction(for: $0) ?? $0 }
            if !fuzzy, fixed == original {
                return SearchPlan(effective: raw, chain: (chain, remainder), corrected: nil)
            }
            let shown = ([chain.name] + fixed).joined(separator: " ")
            return SearchPlan(effective: shown, chain: (chain, fixed.joined(separator: " ")), corrected: shown)
        }
        let original = RestaurantMatcher.words(raw)
        let fixed = original.map { vocabulary.correction(for: $0) ?? $0 }
        guard fixed != original else { return SearchPlan(effective: raw, chain: nil, corrected: nil) }
        let shown = fixed.joined(separator: " ")
        return SearchPlan(effective: shown, chain: nil, corrected: shown)
    }
}

extension RestaurantChain {
    /// "rest:shake-shack:fries" → "shake-shack".
    static func slug(ofRestaurantFoodId id: String) -> String {
        String(id.dropFirst(5).prefix { $0 != ":" })
    }

    /// Curated fast-food ids are `ff-<token>-…` with a house token that is
    /// sometimes an abbreviation ("ff-mcd-", "ff-tb-", "ff-ss-"). A judgement
    /// match: the token equals one of the chain's keys, starts one (≥4 letters),
    /// or is one of the two abbreviations no key carries.
    func ownsCuratedFastFood(id: String) -> Bool {
        let parts = id.split(separator: "-")
        guard parts.count > 1 else { return false }
        let token = String(parts[1])
        if let slugForToken = ["tb": "taco-bell", "ss": "shake-shack"][token] { return slugForToken == slug }
        return matchKeys.contains { $0 == token || (token.count >= 4 && $0.hasPrefix(token)) }
    }
}
