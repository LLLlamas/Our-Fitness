// Gentle food-variety nudges: when a food category appears frequently
// this week, surface a one-line suggestion to mix it up. Not prescriptive —
// a friendly observation, not a warning. Thresholds are loose by design.
// Circuit thresholds are lower for foods that work against LDL / BP goals.
//
// Research:
//   Dietary variety is independently associated with better nutrient intake
//   and gut microbiome diversity: Kant et al., Am J Clin Nutr 1993;
//   Drescher et al., Eur J Clin Nutr 2007.
//   Circuit-specific thresholds drawn from AHA guidance on eggs (≤1/day
//   for cardiovascular risk), processed-meat sodium + nitrates, and
//   red-meat saturated fat accumulation: AHA Dietary Guidelines 2021.

import Foundation

public struct FoodVarietyNudge: Sendable {
    public let emoji: String
    public let message: String
}

public enum FoodVarietyNudges {

    private struct Group {
        let keywords: [String]
        let buildThreshold: Int
        let circuitThreshold: Int
        let message: (Int) -> String
        let emoji: String
    }

    private static let groups: [Group] = [
        Group(
            keywords: ["egg", "eggs", "scrambled", "fried egg", "boiled egg",
                       "poached egg", "omelette", "omelet"],
            buildThreshold: 7,
            circuitThreshold: 5,
            message: { n in
                "Eggs \(n)× this week — cottage cheese, salmon, or Greek yogurt make great swaps tomorrow."
            },
            emoji: "🥚"
        ),
        Group(
            keywords: ["pepperoni", "salami", "spam", "sausage", "ham",
                       "corndog", "corn dog", "cold cut", "luncheon meat", "deli meat"],
            buildThreshold: 4,
            circuitThreshold: 3,
            message: { n in
                "Processed meat \(n)× this week — chicken, fish, or eggs could mix things up."
            },
            emoji: "🥓"
        ),
        Group(
            keywords: ["steak", "sirloin", "ground beef", "beef patty",
                       "burger", "hamburger", "cheeseburger"],
            buildThreshold: 5,
            circuitThreshold: 4,
            message: { n in
                "Red meat \(n)× this week — salmon tomorrow would give your LDL a break."
            },
            emoji: "🥩"
        ),
        Group(
            keywords: ["fries", "french fries", "chips"],
            buildThreshold: 4,
            circuitThreshold: 3,
            message: { n in
                "Fries \(n)× this week — a salad or zucchini noodles would switch things up nicely."
            },
            emoji: "🍟"
        ),
    ]

    /// Returns up to 2 nudges based on the last 7 days of food logs.
    /// Returns empty when no category has reached its threshold.
    public static func nudges(from logs: [FoodLogEntryDTO], mode: Mode) -> [FoodVarietyNudge] {
        let weekDays = Set(Dates.lastNDays(7))
        let weekLogs = logs.filter { weekDays.contains($0.date) }

        return Array(groups.compactMap { group -> FoodVarietyNudge? in
            let threshold = mode == .circuit ? group.circuitThreshold : group.buildThreshold
            let count = weekLogs.filter { log in
                let name = (log.customName ?? "").lowercased()
                return group.keywords.contains { name.contains($0) }
            }.count
            guard count >= threshold else { return nil }
            return FoodVarietyNudge(emoji: group.emoji, message: group.message(count))
        }.prefix(2))
    }
}
