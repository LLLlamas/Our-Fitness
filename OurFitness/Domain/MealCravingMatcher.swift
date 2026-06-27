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
        let tokens = keywordTokens(in: q)
        let flavors = flavorClasses(triggeredBy: q)
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

        let scored = pool
            .map { meal -> (meal: SuggestedMeal, score: Double, flavorsHit: [Flavor]) in
                let (s, hits) = score(meal, tokens: tokens, flavors: flavors,
                                      calorieGoal: calorieGoal, protein: protein, loved: loved)
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
        loved: Set<String>
    ) -> (Double, [Flavor]) {
        let text = searchable(meal)
        var s = 0.0

        // Direct keyword overlap — the strongest relevance signal.
        for t in tokens where text.contains(t) { s += 3 }

        // Flavour match: a craving flavour whose signal words appear in the meal.
        var flavorsHit: [Flavor] = []
        for flavor in flavors where flavor.signals.contains(where: { text.contains($0) }) {
            s += 4
            flavorsHit.append(flavor)
        }

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

        // Affinity: meals built around loved foods get a capped boost.
        if !loved.isEmpty {
            let hits = Set(meal.ingredientTemplates.map(\.foodId)).filter { loved.contains($0) }.count
            s += min(4, 1.5 * Double(hits))
        }

        return (s, flavorsHit)
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
        "food", "for", "get", "gimme", "give", "going", "gonna", "gotta", "grab", "have",
        "honestly", "hungry", "i", "i'm", "ish", "just", "kcal", "kind", "kinda", "least", "lemme",
        "less", "like", "little", "lunch", "make", "maybe", "meal", "mealtime", "mood", "more",
        "morning", "need", "not", "now", "okay", "over", "please", "prefer", "preferably",
        "pretty", "probably", "protein", "quite", "real", "really", "right", "should", "snack",
        "some", "something", "somewhat", "sort", "sorta", "stuff", "super", "than", "that", "the",
        "thing", "things", "this", "today", "tonight", "tonite", "totally", "under", "very",
        "wanna", "want", "what", "whatever", "with", "would", "yeah", "you",
    ]

    /// Distinct content words (length ≥ 3, not stopwords, not pure numbers).
    private static func keywordTokens(in text: String) -> Set<String> {
        let raw = text.split { !($0.isLetter) }.map(String.init)
        return Set(raw.filter { $0.count >= 3 && !stopwords.contains($0) })
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

    /// A flavour/quality class: `triggers` are words a user types in a craving;
    /// `signals` are words found in a meal (name/description/ingredients) that mark
    /// it as having this flavour. Data-driven so the corpus is easy to extend.
    private struct Flavor {
        let label: String
        let triggers: [String]
        let signals: [String]
    }

    private static let flavors: [Flavor] = [
        Flavor(label: "salty",
               triggers: ["salt", "salty", "savory", "savoury"],
               signals: ["chip", "fries", "pretzel", "jerky", "bacon", "cheese", "soy", "miso", "pickle", "popcorn", "cracker", "deli", "ham", "olive", "soup", "ramen", "broth", "nuts", "peanut", "feta", "salami", "sausage", "taco", "burrito", "pizza", "fried", "edamame"]),
        Flavor(label: "sweet",
               triggers: ["sweet", "dessert", "sugary", "treat"],
               signals: ["chocolate", "candy", "cookie", "cake", "berry", "berries", "honey", "yogurt", "yoghurt", "smoothie", "pancake", "syrup", "banana", "mango", "fruit", "oat", "granola", "muffin", "date", "apple", "peanut butter"]),
        Flavor(label: "savory",
               triggers: ["savory", "savoury", "hearty", "meaty", "filling"],
               signals: ["chicken", "beef", "steak", "egg", "rice", "pasta", "bowl", "burrito", "potato", "lentil", "bean", "turkey", "salmon", "tuna", "curry", "stir", "wrap", "sandwich", "burger", "tofu"]),
        Flavor(label: "light",
               triggers: ["light", "fresh", "refreshing", "not that hungry", "not very hungry"],
               signals: ["salad", "veggie", "vegetable", "greens", "soup", "broth", "smoothie", "fruit", "yogurt", "cucumber"]),
        Flavor(label: "spicy",
               triggers: ["spicy", "hot ", "chili", "fiery", "kick"],
               signals: ["spicy", "chili", "sriracha", "pepper", "jalape", "curry", "buffalo"]),
        Flavor(label: "creamy",
               triggers: ["creamy", "smooth", "rich"],
               signals: ["yogurt", "cream", "smoothie", "avocado", "cheese", "milk", "peanut butter", "hummus"]),
        Flavor(label: "comfort",
               triggers: ["comfort", "comforting", "cozy", "cosy", "homey", "homely", "nostalgic", "craving comfort", "feel better"],
               signals: ["mac", "macaroni", "mashed", "grilled cheese", "pot pie", "meatloaf", "gravy", "dumpling", "risotto", "casserole", "noodle", "pasta bake"]),
        Flavor(label: "crunchy",
               triggers: ["crunch", "crunchy", "crispy", "crisp", "snappy", "munch", "munchy"],
               signals: ["chip", "chips", "fries", "crisp", "crispy", "pretzel", "cracker", "granola", "nuts", "almond", "celery", "carrot", "cucumber", "apple", "toast", "popcorn", "crouton", "seaweed"]),
        Flavor(label: "cheesy",
               triggers: ["cheese", "cheesy", "queso", "extra cheese"],
               signals: ["cheese", "cheesy", "cheddar", "mozzarella", "parmesan", "parmigiano", "feta", "cottage cheese", "queso", "nacho", "quesadilla", "grilled cheese", "pizza", "mac", "macaroni"]),
        Flavor(label: "chocolatey",
               triggers: ["chocolate", "chocolatey", "chocolaty", "cocoa", "cacao", "choc", "mocha"],
               signals: ["chocolate", "cocoa", "cacao", "mocha", "brownie", "fudge", "nutella"]),
        Flavor(label: "fruity",
               triggers: ["fruity", "tropical", "berry", "berries"],
               signals: ["strawberr", "blueberr", "raspberr", "mango", "pineapple", "watermelon", "peach", "plum", "grape", "orange", "kiwi", "papaya", "berry", "berries"]),
        Flavor(label: "warm",
               triggers: ["warm", "hot meal", "hot dish", "heated", "piping hot", "steaming", "cozy meal"],
               signals: ["soup", "stew", "ramen", "broth", "oatmeal", "grilled", "baked", "roasted", "scramble", "scrambled", "curry", "stir", "steamed", "miso soup", "chicken soup", "toast"]),
        Flavor(label: "cold",
               triggers: ["cold", "chilled", "cooling", "icy", "frozen", "chill"],
               signals: ["salad", "smoothie", "yogurt", "yoghurt", "cottage cheese", "cucumber", "watermelon", "frozen", "iced", "sushi", "seaweed salad", "fruit"]),
        Flavor(label: "umami",
               triggers: ["umami", "savory rich", "savoury rich", "brothy", "deep flavor", "deep flavour", "umami bomb"],
               signals: ["miso", "soy", "mushroom", "beef", "steak", "salmon", "tuna", "bacon", "parmesan", "seaweed", "nori", "broth", "tomato", "tofu", "edamame"]),
        Flavor(label: "tangy",
               triggers: ["tangy", "sour", "tart", "zesty", "citrus", "acidic", "zingy", "vinegary"],
               signals: ["lemon", "lime", "yogurt", "yoghurt", "greek yogurt", "tomato", "salsa", "pickle", "vinegar", "feta", "citrus", "orange", "plum", "raspberr", "cottage cheese", "balsamic"]),
        Flavor(label: "vegetarian",
               triggers: ["vegetarian", "veggie", "no meat", "meatless", "plant based", "plant-based"],
               signals: ["veggie", "vegetable", "salad", "lentil", "bean", "tofu", "quinoa", "oatmeal", "yogurt", "egg", "cheese", "greens", "cottage cheese", "seaweed", "cucumber", "tomato", "zucchini", "smoothie", "oats"]),
        Flavor(label: "vegan",
               triggers: ["vegan", "dairy free", "dairy-free", "no animal"],
               signals: ["lentil", "bean", "tofu", "quinoa", "oat milk", "edamame", "avocado", "greens", "seaweed", "cucumber", "tomato", "zucchini", "broccoli", "spinach"]),
        Flavor(label: "low carb",
               triggers: ["low carb", "lowcarb", "keto", "low-carb", "carb free", "no carbs", "fewer carbs"],
               signals: ["salad", "egg", "chicken", "salmon", "tuna", "beef", "steak", "turkey", "tofu", "greens", "cucumber", "zucchini", "seaweed", "avocado", "cottage cheese", "broccoli", "spinach"]),
        Flavor(label: "high fiber",
               triggers: ["high fiber", "high fibre", "fiber", "fibre", "filling fiber", "gut health", "roughage"],
               signals: ["lentil", "bean", "oatmeal", "oats", "quinoa", "broccoli", "berries", "brown rice", "avocado", "veggie", "vegetable", "greens", "seaweed", "spinach", "granola", "whole wheat"]),
        Flavor(label: "quick",
               triggers: ["quick", "grab and go", "grab-and-go", "no cook", "no-cook", "minimal effort", "speedy", "lazy"],
               signals: ["smoothie", "shake", "yogurt", "yoghurt", "cottage cheese", "wrap", "sandwich", "scramble", "toast", "sushi", "bowl", "fruit", "banana", "granola", "oatmeal"]),
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
