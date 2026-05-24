// Shared scoring primitives. Both modes' suggestion engines compose these.
// Pure functions. No mode-specific knowledge here — that belongs in Suggestions.swift.

import Foundation

public enum Score {

    /// Returns 0…1 — 1 when value matches target, falling off either side.
    public static func bell(value: Double, target: Double, tolerance: Double) -> Double {
        guard target > 0 else { return 0 }
        let diff = abs(value - target)
        return max(0, 1 - diff / max(tolerance, 1))
    }

    /// Higher values are better, normalized 0…1 against `ceiling`.
    public static func rampUp(_ value: Double, ceiling: Double) -> Double {
        guard ceiling > 0 else { return 0 }
        return min(1, max(0, value / ceiling))
    }

    /// Lower values are better, 1 at 0, 0 at `ceiling`+.
    public static func rampDown(_ value: Double, ceiling: Double) -> Double {
        guard ceiling > 0 else { return 1 }
        return max(0, 1 - value / ceiling)
    }

    /// How well a food's macro slice fits the user's remaining headroom for the day.
    public static func macroFit(_ food: FoodDTO, remaining: RemainingMacros) -> Double {
        let p = food.perServing
        // Reject foods that would blow the remaining calorie budget by >150%.
        if remaining.calories > 0 && Double(p.calories) > Double(remaining.calories) * 1.5 {
            return 0
        }
        let proteinPull: Double = remaining.proteinG > 0
            ? rampUp(Double(p.proteinG), ceiling: Double(remaining.proteinG))
            : 0.5
        let calPull: Double = remaining.calories > 0
            ? bell(value: Double(p.calories),
                   target: Double(remaining.calories) / 2,
                   tolerance: Double(remaining.calories) / 2)
            : 0.5
        return 0.6 * proteinPull + 0.4 * calPull
    }

    /// Reset-only: penalize hitting a cap. 1 if comfortably under, 0 if would breach.
    public static func respectsCap(value: Double, headroom: Int?) -> Double {
        guard let headroom else { return 1 }
        if headroom <= 0 { return 0 }
        return max(0, 1 - value / Double(headroom))
    }

    /// Caloric density per dollar.
    public static func calsPerDollar(_ food: FoodDTO) -> Double {
        Double(food.perServing.calories) / max(0.5, food.costUsd)
    }

    /// Protein per calorie.
    public static func proteinPerCal(_ food: FoodDTO) -> Double {
        guard food.perServing.calories > 0 else { return 0 }
        return Double(food.perServing.proteinG) / Double(food.perServing.calories)
    }
}
