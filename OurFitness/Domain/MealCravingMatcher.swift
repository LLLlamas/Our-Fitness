// Free-text craving → meal suggester (pure Swift, no SwiftUI/SwiftData).
//
// Given a sentence like "not that hungry but I need at least 500 calories and a
// little protein, maybe something salty", this ranks the curated
// `SuggestedMeals` corpus by how well each meal matches the craving's flavour,
// keywords, calorie target, protein hint, and the user's own eating history.
//
// This is the deterministic fallback for `MealIdeaService` (when Apple
// Intelligence is unavailable) — "otherwise recommend according to previously
// logged meals". All macro numbers come from the curated corpus, never invented.
//
// Accuracy model (why "something salty" no longer returns sweet shakes / fruit):
//   • Each flavour has STRONG (defining) and WEAK (incidental) signal words. A
//     flavour only counts when a meal has ≥1 strong OR ≥2 weak signals, so a single
//     incidental word (e.g. one "cheese") can't flag a sweet dish as salty.
//   • Score scales with signal density: strong = 3, weak = 1, capped.
//   • ANTAGONIST suppression: a requested flavour is penalised by the strength of
//     its opposite in the same meal (salty ↔ sweet/chocolatey/fruity, warm ↔ cold,
//     light ↔ comfort). A chocolate-banana shake therefore scores ~0 for "salty".
//   • Affinity (foods the user logs/favourites) is capped and GATED: when an
//     explicit flavour/keyword is asked, it only nudges meals that already match the
//     craving — it can never drag an irrelevant favourite to the top.

import Foundation

public enum MealCravingMatcher {

    /// A ranked meal match with a human reason describing why it fits.
    public struct CravingMatch: Sendable, Identifiable {
        public let meal: SuggestedMeal
        public let reason: String
        public var id: String { meal.id }
    }

    /// Rank the mode's curated meals against a free-text craving. Honours the
    /// profile's allergen restrictions, biases toward foods the user logs/favourites,
    /// and parses simple constraints (calorie target, protein hint, flavour) from
    /// the text. `now` is injectable so history windows are deterministic in tests.
    public static func matches(
        for profile: ProfileDTO,
        craving: String,
        totals: DailyTotals,
        recentLogs: [FoodLogEntryDTO] = [],
        favoriteFoodIds: Set<String> = [],
        limit: Int = 5,
        now: Date = Date()
    ) -> [CravingMatch] {
        let pool = SuggestedMeals.suggestions(for: profile.mode)
            .filter { !hasRestrictedAllergen($0, restrictions: profile.restrictions) }

        let q = craving.lowercased()
        let flavors = flavorClasses(triggeredBy: q)
        let tokens = keywordTokens(in: q)
        let calorieGoal = calorieTarget(in: q)
        let protein = proteinHint(in: q)

        // Foods the user actually eats — explicit favourites ∪ recent most-logged.
        var loved = favoriteFoodIds
        loved.formUnion(FoodAffinity.mostLoggedIds(recentLogs, limit: 8, end: now))

        // If nothing parseable was said, defer to the standard macro-gap ranking so
        // the user still gets sensible, personalised suggestions.
        let nothingAsked = tokens.isEmpty && flavors.isEmpty && calorieGoal == nil && protein == .none
        if nothingAsked {
            return SuggestedMeals
                .ranked(for: profile, totals: totals, recentLogs: recentLogs,
                        favoriteFoodIds: favoriteFoodIds, limit: limit)
                .map { CravingMatch(meal: $0, reason: macroNote(for: $0)) }
        }

        // When the user names a flavour or content word, that becomes a hard gate:
        // a meal must clear a positive craving relevance to appear at all. This is
        // what stops affinity-only or opposite-flavour meals from surfacing.
        let constrained = !tokens.isEmpty || !flavors.isEmpty

        let scored = pool
            .map { meal -> (meal: SuggestedMeal, score: Double, flavorsHit: [Flavor]) in
                let (s, hits) = score(meal, tokens: tokens, flavors: flavors,
                                      calorieGoal: calorieGoal, protein: protein,
                                      loved: loved, constrained: constrained, mode: profile.mode)
                return (meal, s, hits)
            }
            .filter { $0.score > 0 }
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                return a.meal.name < b.meal.name
            }

        let chosen = scored.prefix(limit)
        // Nothing scored positively (e.g. an unmatched keyword) — fall back to the
        // macro-gap ranking rather than returning nothing.
        if chosen.isEmpty {
            return SuggestedMeals
                .ranked(for: profile, totals: totals, recentLogs: recentLogs,
                        favoriteFoodIds: favoriteFoodIds, limit: limit)
                .map { CravingMatch(meal: $0, reason: macroNote(for: $0)) }
        }

        return chosen.map { entry in
            CravingMatch(meal: entry.meal, reason: reason(for: entry.meal, flavorsHit: entry.flavorsHit))
        }
    }

    // MARK: - Scoring

    private static func score(
        _ meal: SuggestedMeal,
        tokens: Set<String>,
        flavors: [Flavor],
        calorieGoal: CalorieGoal?,
        protein: ProteinHint,
        loved: Set<String>,
        constrained: Bool,
        mode: Mode
    ) -> (Double, [Flavor]) {
        let text = searchable(meal)

        // Craving relevance = literal keyword hits + flavour fit (strength − antagonist).
        // Tracked separately from calorie/protein/affinity so it can act as the gate.
        var cravingScore = 0.0

        // Direct keyword overlap — the strongest relevance signal. (Flavour-trigger
        // words are excluded from `tokens`, so they're never double-counted here.)
        for t in tokens where text.contains(t) { cravingScore += 3 }

        // Flavour match: strength-weighted, with opposite-flavour suppression.
        var flavorsHit: [Flavor] = []
        for flavor in flavors {
            let fs = flavorScore(text, flavor)
            if fs > 0 {
                cravingScore += fs
                flavorsHit.append(flavor)
            }
        }

        // GATE: a stated flavour/keyword with no positive craving relevance is out,
        // before calorie/protein/affinity can resurrect it.
        if constrained && cravingScore <= 0 { return (0, []) }

        var s = cravingScore

        // Calorie fit.
        if let goal = calorieGoal {
            let cal = meal.perServing.calories
            switch goal.bound {
            case .floor:
                s += cal >= goal.value ? 4 : -3
            case .ceiling:
                s += cal <= goal.value ? 4 : -3
            case .around:
                let off = abs(Double(cal - goal.value)) / Double(max(goal.value, 1))
                s += max(0, 4 * (1 - off))     // full credit at exact, fading out by 100% off
            }
        }

        // Protein hint.
        switch protein {
        case .more:
            s += min(4, Double(meal.perServing.proteinG) / 8.0)
        case .little:
            // Reward a modest, not heavy, protein load.
            s += (meal.perServing.proteinG >= 4 && meal.perServing.proteinG <= 25) ? 2 : 0
        case .none:
            break
        }

        // Mode tilt: nudge within the (already mode-filtered) pool toward each mode's
        // macro priorities — Build favours protein + calorie density, Circuit favours
        // fibre + leaner picks. Small adds so the craving's flavour/keyword stays the
        // primary signal; only reached after the gate.
        let ps = meal.perServing
        switch mode {
        case .build:
            s += min(1.5, Double(ps.proteinG) / 30.0)
            s += min(1.0, Double(ps.calories) / 700.0)
        case .circuit:
            s += min(1.5, Double(ps.fiberG) / 8.0)
            s += ps.calories <= 450 ? 0.8 : 0
        }

        // Affinity: meals built around loved foods get a boost. When the craving
        // names a flavour/keyword, the boost is small and gated to already-relevant
        // meals (cravingScore > 0) so it re-orders within the matches rather than
        // overriding them. With no flavour stated, it can lead (old behaviour).
        if !loved.isEmpty {
            let hits = Set(meal.ingredientTemplates.map(\.foodId)).filter { loved.contains($0) }.count
            if hits > 0 {
                if constrained {
                    if cravingScore > 0 { s += min(2.0, Double(hits)) }
                } else {
                    s += min(4, 1.5 * Double(hits))
                }
            }
        }

        return (s, flavorsHit)
    }

    /// Strength-weighted score for one flavour on a meal, after antagonist
    /// suppression. 0 unless the meal has ≥1 strong or ≥2 weak signals.
    private static func flavorScore(_ text: String, _ flavor: Flavor) -> Double {
        let d = density(text, flavor)
        guard d.strong >= 1 || d.weak >= 2 else { return 0 }
        let base = min(8.0, d.raw)
        let opposing = (antagonists[flavor.label] ?? []).compactMap { flavorsByLabel[$0] }
        let antagonist = 0.75 * (opposing.map { density(text, $0).raw }.max() ?? 0)
        return max(0, base - antagonist)
    }

    /// Distinct strong/weak signal hits and their weighted density (strong 3, weak 1).
    private static func density(_ text: String, _ flavor: Flavor) -> (strong: Int, weak: Int, raw: Double) {
        let ns = flavor.strong.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
        let nw = flavor.weak.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
        return (ns, nw, 3.0 * Double(ns) + Double(nw))
    }

    private static func searchable(_ meal: SuggestedMeal) -> String {
        var parts = [meal.name.lowercased(), meal.description.lowercased()]
        for t in meal.ingredientTemplates {
            parts.append(t.foodId.lowercased())
            if let c = t.customName { parts.append(c.lowercased()) }
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Reason copy

    private static func reason(for meal: SuggestedMeal, flavorsHit: [Flavor]) -> String {
        let descriptor: String
        if !flavorsHit.isEmpty {
            descriptor = flavorsHit.map(\.label).joined(separator: " & ").capitalizedFirst
        } else {
            descriptor = "Good match"
        }
        return "\(descriptor) · \(macroNote(for: meal))"
    }

    private static func macroNote(for meal: SuggestedMeal) -> String {
        "~\(meal.perServing.calories) cal, \(meal.perServing.proteinG)g protein"
    }

    // MARK: - Parsing the craving

    private static let stopwords: Set<String> = [
        "a", "about", "actually", "afternoon", "an", "and", "anything", "are", "around", "bit",
        "breakfast", "brunch", "but", "cal", "calorie", "calories", "could", "crave", "craves",
        "craving", "definitely", "dinner", "eat", "evening", "fairly", "feel", "feeling", "fix",
        "food", "for", "get", "gimme", "give", "going", "gonna", "gotta", "grab", "have", "high",
        "honestly", "hungry", "i", "i'm", "ish", "just", "kcal", "kind", "kinda", "least", "lemme",
        "less", "like", "little", "low", "lunch", "make", "maybe", "meal", "mealtime", "mood",
        "more", "morning", "need", "not", "now", "okay", "over", "please", "prefer", "preferably",
        "pretty", "probably", "protein", "quite", "real", "really", "right", "should", "snack",
        "some", "something", "somewhat", "sort", "sorta", "stuff", "super", "than", "that", "the",
        "thing", "things", "this", "today", "tonight", "tonite", "too", "totally", "under", "very",
        "wanna", "want", "what", "whatever", "with", "would", "yeah", "you",
    ]

    /// Every word that is a flavour trigger, so they're excluded from keyword tokens
    /// (the flavour system already scores them — counting them as keywords too would
    /// double-count and let a meal's own "salty"/"sweet" description inflate it).
    private static let triggerWords: Set<String> = Set(
        flavors.flatMap { $0.triggers }
            .flatMap { $0.split { !$0.isLetter }.map(String.init) }
            .filter { $0.count >= 3 }
    )

    /// Distinct content words (length ≥ 3, not stopwords, not flavour triggers,
    /// not pure numbers).
    private static func keywordTokens(in text: String) -> Set<String> {
        let raw = text.split { !($0.isLetter) }.map(String.init)
        return Set(raw.filter { $0.count >= 3 && !stopwords.contains($0) && !triggerWords.contains($0) })
    }

    private enum Bound { case floor, ceiling, around }
    private struct CalorieGoal { let value: Int; let bound: Bound }

    /// First "<number> cal" / "<number> calories" mention; the surrounding words
    /// decide whether it's a floor ("at least"), ceiling ("under"), or target.
    private static func calorieTarget(in text: String) -> CalorieGoal? {
        guard text.contains("cal") else { return nil }
        let pattern = "(\\d{2,4})\\s*(?:k?cal|calorie)"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range),
              let r = Range(m.range(at: 1), in: text),
              let value = Int(text[r]) else { return nil }

        let bound: Bound
        if text.contains("at least") || text.contains("more than") || text.contains("over ")
            || text.contains("minimum") || text.contains("at minimum") {
            bound = .floor
        } else if text.contains("under") || text.contains("less than") || text.contains("at most")
            || text.contains("no more than") {
            bound = .ceiling
        } else {
            bound = .around
        }
        return CalorieGoal(value: value, bound: bound)
    }

    private enum ProteinHint { case more, little, none }

    private static func proteinHint(in text: String) -> ProteinHint {
        guard text.contains("protein") else { return .none }
        if text.contains("little") || text.contains("some") || text.contains("bit")
            || text.contains("light") {
            return .little
        }
        return .more
    }

    // MARK: - Flavour vocabulary

    /// A flavour/quality class. `triggers` are words a user types in a craving.
    /// `strong` signals are defining markers of the flavour in a meal; `weak` signals
    /// are incidental (count for less, and need two to flag a flavour on their own).
    /// Data-driven so the corpus is easy to extend.
    private struct Flavor {
        let label: String
        let triggers: [String]
        let strong: [String]
        let weak: [String]
    }

    private static let flavors: [Flavor] = [
        Flavor(label: "salty",
               triggers: ["salt", "salty", "savory", "savoury"],
               strong: ["chip", "fries", "pretzel", "jerky", "bacon", "salami", "sausage", "deli", "ham", "feta", "parmesan", "miso", "soy sauce", "pickle", "anchov", "prosciutto", "nacho", "olives"],
               weak: ["cheddar", "swiss", "mozzarella", "pepperoni", "popcorn", "cracker", "broth", "soup", "ramen", "fried", "edamame", "seaweed", "soy"]),
        Flavor(label: "sweet",
               triggers: ["sweet", "dessert", "sugary", "treat"],
               strong: ["chocolate", "candy", "cookie", "cake", "honey", "syrup", "pancake", "french toast", "muffin", "brownie", "fudge", "caramel", "maple", "date"],
               weak: ["banana", "mango", "berry", "berries", "fruit", "apple", "granola", "oat", "yogurt", "smoothie"]),
        Flavor(label: "savory",
               triggers: ["savory", "savoury", "hearty", "meaty", "filling"],
               strong: ["chicken", "beef", "steak", "turkey", "salmon", "tuna", "pork", "lamb", "shrimp", "egg", "tofu", "tempeh", "lentil", "bean", "curry", "gravy", "burger", "meatloaf", "scallop", "cod", "tilapia"],
               weak: ["rice", "pasta", "bowl", "potato", "stir", "noodle", "quinoa", "wrap", "sandwich"]),
        Flavor(label: "light",
               triggers: ["light", "fresh", "refreshing", "not that hungry", "not very hungry"],
               strong: ["salad", "greens", "veggie", "vegetable", "cucumber"],
               weak: ["soup", "broth", "smoothie", "fruit", "yogurt", "light", "bright"]),
        Flavor(label: "spicy",
               triggers: ["spicy", "hot ", "chili", "fiery", "kick"],
               strong: ["spicy", "spiced", "chili", "sriracha", "jalape", "buffalo", "hot sauce", "cayenne", "harissa", "fiery"],
               weak: ["pepper", "curry", "salsa"]),
        Flavor(label: "creamy",
               triggers: ["creamy", "smooth", "rich"],
               strong: ["cream", "yogurt", "avocado", "hummus", "cottage cheese", "peanut butter", "tahini", "tzatziki", "ricotta"],
               weak: ["milk", "smoothie"]),
        Flavor(label: "comfort",
               // "comfort"/"hearty"/"cozy" are the descriptor words the corpus actually
               // uses ("Italian comfort", "Hearty pasta", "Cozy red lentils") — they carry
               // the recall here; the specific dish names below are rare but harmless.
               triggers: ["comfort", "comforting", "cozy", "cosy", "homey", "homely", "nostalgic", "craving comfort", "feel better"],
               strong: ["comfort", "hearty", "cozy", "mac", "macaroni", "mashed", "grilled cheese", "pot pie", "meatloaf", "gravy", "dumpling", "risotto", "casserole", "pasta bake"],
               weak: ["stew", "classic", "homemade", "mashed potato", "baked potato"]),
        Flavor(label: "crunchy",
               triggers: ["crunch", "crunchy", "crispy", "crisp", "snappy", "munch", "munchy"],
               strong: ["chip", "chips", "fries", "crisp", "crispy", "pretzel", "cracker", "granola", "crouton"],
               weak: ["nuts", "almond", "celery", "carrot", "cucumber", "apple", "toast", "popcorn", "seaweed"]),
        Flavor(label: "cheesy",
               triggers: ["cheese", "cheesy", "queso", "extra cheese"],
               strong: ["cheese", "cheesy", "cheddar", "mozzarella", "parmesan", "feta", "queso", "nacho", "quesadilla", "grilled cheese"],
               weak: ["pizza", "mac", "macaroni", "swiss"]),
        Flavor(label: "chocolatey",
               triggers: ["chocolate", "chocolatey", "chocolaty", "cocoa", "cacao", "choc", "mocha"],
               strong: ["chocolate", "cocoa", "cacao", "mocha", "brownie", "fudge", "nutella"],
               weak: []),
        Flavor(label: "fruity",
               triggers: ["fruity", "tropical", "berry", "berries"],
               // "cherries" not "cherr": "cherr" also matches "cherry-tomatoes"/"cherry
               // tomatoes", which would wrongly tag savory tomato dishes as fruity.
               strong: ["strawberr", "blueberr", "raspberr", "mango", "pineapple", "watermelon", "peach", "plum", "grape", "kiwi", "papaya", "cherries"],
               weak: ["banana", "fruit", "berry", "berries", "orange"]),
        Flavor(label: "warm",
               triggers: ["warm", "hot meal", "hot dish", "heated", "piping hot", "steaming", "cozy meal"],
               strong: ["soup", "stew", "ramen", "broth", "oatmeal", "grilled", "baked", "roasted", "scramble", "curry", "stir", "steamed"],
               weak: ["toast"]),
        Flavor(label: "cold",
               triggers: ["cold", "chilled", "cooling", "frozen", "chill"],
               strong: ["smoothie", "frozen", "iced", "chilled", "sushi"],
               weak: ["salad", "yogurt", "cottage cheese", "cucumber", "watermelon"]),
        Flavor(label: "umami",
               triggers: ["umami", "savory rich", "savoury rich", "brothy", "deep flavor", "deep flavour", "umami bomb"],
               strong: ["miso", "soy sauce", "mushroom", "beef", "steak", "salmon", "tuna", "bacon", "parmesan", "seaweed", "nori"],
               weak: ["broth", "tomato", "tofu", "edamame"]),
        Flavor(label: "tangy",
               triggers: ["tangy", "sour", "tart", "zesty", "citrus", "acidic", "zingy", "vinegary"],
               strong: ["lemon", "lime", "salsa", "pickle", "vinegar", "vinaigrette", "citrus", "balsamic"],
               weak: ["yogurt", "tomato", "feta", "orange", "plum"]),
        Flavor(label: "vegetarian",
               triggers: ["vegetarian", "veggie", "no meat", "meatless", "plant based", "plant-based"],
               strong: ["veggie", "vegetable", "salad", "lentil", "bean", "tofu", "quinoa", "egg"],
               weak: ["cheese", "yogurt", "oatmeal", "cottage cheese", "seaweed", "cucumber", "tomato", "zucchini", "smoothie", "oats", "greens"]),
        Flavor(label: "vegan",
               triggers: ["vegan", "dairy free", "dairy-free", "no animal"],
               strong: ["lentil", "bean", "tofu", "quinoa", "oat milk", "edamame", "tempeh"],
               weak: ["avocado", "greens", "seaweed", "cucumber", "tomato", "zucchini", "broccoli", "spinach"]),
        Flavor(label: "low carb",
               triggers: ["low carb", "lowcarb", "keto", "low-carb", "carb free", "no carbs", "fewer carbs"],
               strong: ["salad", "egg", "chicken", "salmon", "tuna", "beef", "steak", "turkey", "tofu"],
               weak: ["greens", "cucumber", "zucchini", "seaweed", "avocado", "cottage cheese", "broccoli", "spinach"]),
        Flavor(label: "high fiber",
               triggers: ["high fiber", "high fibre", "fiber", "fibre", "filling fiber", "gut health", "roughage"],
               strong: ["lentil", "bean", "oatmeal", "oats", "quinoa", "broccoli", "farro", "barley", "chia"],
               weak: ["avocado", "berries", "brown rice", "veggie", "vegetable", "greens", "seaweed", "spinach", "granola"]),
        Flavor(label: "quick",
               triggers: ["quick", "grab and go", "grab-and-go", "no cook", "no-cook", "minimal effort", "speedy", "lazy"],
               strong: ["smoothie", "shake", "no cook", "no-cook"],
               weak: ["yogurt", "wrap", "sandwich", "toast", "sushi", "cottage cheese", "scramble", "bowl", "fruit", "banana", "granola", "oatmeal"]),
    ]

    private static let flavorsByLabel: [String: Flavor] =
        Dictionary(uniqueKeysWithValues: flavors.map { ($0.label, $0) })

    /// Requested flavour → opposing flavours whose presence suppresses the match.
    /// Keeps salty/sweet (and warm/cold, light/comfort) from co-firing on a dish
    /// that's dominated by the opposite, while leaving genuine dual dishes (salty
    /// feta + sweet watermelon) merely ranked lower, not excluded.
    private static let antagonists: [String: [String]] = [
        "salty": ["sweet", "chocolatey", "fruity"],
        "sweet": ["salty"],
        "chocolatey": ["salty"],
        "fruity": ["salty"],
        "light": ["comfort"],
        "comfort": ["light"],
        "warm": ["cold"],
        "cold": ["warm"],
    ]

    private static func flavorClasses(triggeredBy text: String) -> [Flavor] {
        flavors.filter { f in f.triggers.contains(where: { text.contains($0) }) }
    }

    // MARK: - Allergens (mirrors SuggestedMeals)

    private static func hasRestrictedAllergen(
        _ meal: SuggestedMeal, restrictions: [String]
    ) -> Bool {
        guard !restrictions.isEmpty, !meal.allergens.isEmpty else { return false }
        let norm = restrictions.map { $0.lowercased() }
        return meal.allergens.contains { tag in
            norm.contains { $0.contains(tag) || tag.contains($0) }
        }
    }
}

private extension String {
    /// Uppercases only the first character — keeps "salty & savory" → "Salty & savory".
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
