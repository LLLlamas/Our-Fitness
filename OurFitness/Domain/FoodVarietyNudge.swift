// Gentle food-variety nudges: when a food category appears frequently
// this week, surface the threshold reasoning and a concrete swap.
// Not prescriptive — a friendly observation, not a warning.
// The .lose goal gets lower thresholds (and marker-focused copy) for foods that
// work against LDL / BP — a goal tilt; the nudge itself shows for everyone.
//
// Research:
//   Dietary variety → better nutrient intake + gut microbiome diversity.
//   Kant et al., Am J Clin Nutr 1993; Drescher et al., Eur J Clin Nutr 2007.
//   Per-group thresholds and alternatives drawn from:
//   AHA Dietary Guidelines 2021 (eggs, red meat, processed meat);
//   Mozaffarian & Wu, J Am Coll Cardiol 2011 (omega-3 / triglycerides);
//   NCEP ATP III (saturated fat → LDL); WHO IARC 2015 (processed meat).

import Foundation

public struct FoodVarietyNudge: Sendable {
    public let emoji: String
    public let headline: String       // "Eggs 5× this week"
    public let reason: String         // why the threshold matters
    public let alternative: String    // concrete swap + mechanism
}

public enum FoodVarietyNudges {

    private struct Group {
        let keywords: [String]
        let gainThreshold: Int
        let loseThreshold: Int
        let headline: (Int) -> String
        let reason: String
        let loseReason: String        // marker-focused tilt for the .lose goal
        let alternative: String
        let loseAlternative: String
        let emoji: String
    }

    private static let groups: [Group] = [
        Group(
            keywords: ["egg", "eggs", "scrambled", "fried egg", "boiled egg",
                       "poached egg", "omelette", "omelet"],
            gainThreshold: 7,
            loseThreshold: 5,
            headline: { n in "Eggs \(n)× this week" },
            reason: "Eggs are nutritious but variety keeps nutrient intake broader.",
            loseReason: "AHA suggests ≤1 whole egg/day for those managing cardiovascular risk — dietary cholesterol still matters at higher frequencies.",
            alternative: "Greek yogurt or cottage cheese give you similar protein with less saturated fat.",
            loseAlternative: "Salmon tomorrow — EPA/DHA omega-3 actively lowers triglycerides 15–30% (Mozaffarian & Wu, JACC 2011) and is the direct counter to egg-heavy weeks.",
            emoji: "🥚"
        ),
        Group(
            keywords: ["pepperoni", "salami", "spam", "sausage", "ham",
                       "corndog", "corn dog", "cold cut", "luncheon meat", "deli meat"],
            gainThreshold: 4,
            loseThreshold: 3,
            headline: { n in "Processed meat \(n)× this week" },
            reason: "Processed meats are high in sodium and preservatives; frequent intake adds up.",
            loseReason: "Each 50g/day of processed meat is linked to measurable LDL and BP creep (WHO IARC 2015). Sodium from cured meats is one of the fastest routes to elevated systolic BP.",
            alternative: "Chicken breast or canned tuna give you the same quick-protein without the sodium load.",
            loseAlternative: "Chicken breast or miso soup with tofu — soy isoflavones in miso actively lower LDL 3–5% (Anderson et al., NEJM 1995). Same ease, opposite effect on your markers.",
            emoji: "🥓"
        ),
        Group(
            keywords: ["steak", "sirloin", "ground beef", "beef patty",
                       "burger", "hamburger", "cheeseburger"],
            gainThreshold: 5,
            loseThreshold: 4,
            headline: { n in "Red meat \(n)× this week" },
            reason: "Red meat is fine in moderation — it just accumulates saturated fat quickly across a week.",
            loseReason: "Saturated fat from red meat is the dominant dietary driver of LDL elevation (NCEP ATP III). Eating red meat this often pushes sat-fat well above AHA's 6%-of-calories ceiling for cardiovascular health.",
            alternative: "Ground turkey or grilled chicken hit the same protein target with a fraction of the sat-fat.",
            loseAlternative: "Salmon or a seaweed salad tomorrow — omega-3 EPA/DHA directly counters LDL oxidation and lowers triglycerides. The swap is the most targeted single meal you can make this week.",
            emoji: "🥩"
        ),
        Group(
            keywords: ["fries", "french fries", "chips"],
            gainThreshold: 4,
            loseThreshold: 3,
            headline: { n in "Fries \(n)× this week" },
            reason: "Deep-fried foods add saturated fat quickly and spike the glycemic load of a meal.",
            loseReason: "Frying oils raise LDL and the refined-starch glycemic spike impairs insulin sensitivity — both are heart-health markers worth protecting.",
            alternative: "Baked potato or air-popped popcorn give you the same satisfying crunch.",
            loseAlternative: "Zucchini noodles or a cucumber-tomato salad — potassium from both actively lowers BP (DASH evidence), which is the other lever fries work against.",
            emoji: "🍟"
        ),
    ]

    /// Returns up to 2 nudges based on the last 7 days of food logs.
    /// Returns empty when no category has reached its threshold.
    public static func nudges(from logs: [FoodLogEntryDTO], fitnessGoal: FitnessGoal) -> [FoodVarietyNudge] {
        let weekDays = Set(Dates.lastNDays(7))
        let weekLogs = logs.filter { weekDays.contains($0.date) }

        return Array(groups.compactMap { group -> FoodVarietyNudge? in
            let threshold = fitnessGoal == .lose ? group.loseThreshold : group.gainThreshold
            let count = weekLogs.filter { log in
                let name = (log.customName ?? "").lowercased()
                return group.keywords.contains { name.contains($0) }
            }.count
            guard count >= threshold else { return nil }
            return FoodVarietyNudge(
                emoji: group.emoji,
                headline: group.headline(count),
                reason: fitnessGoal == .lose ? group.loseReason : group.reason,
                alternative: fitnessGoal == .lose ? group.loseAlternative : group.alternative
            )
        }.prefix(2))
    }
}
