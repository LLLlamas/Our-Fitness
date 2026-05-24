// Per-mode meal suggestion: filter → score → rank.
// Same shape for both modes; weights and filters differ.

import Foundation

public enum Suggestions {

    private static let slotCategories: [Slot: Set<FoodCategory>] = [
        .pre:         [.drink, .snack, .smoothie],
        .breakfast:   [.breakfast, .smoothie, .bowl],
        .postWorkout: [.smoothie, .breakfast, .main, .bowl],
        .lunch:       [.main, .bowl, .soup],
        .snack:       [.snack, .drink, .smoothie],
        .dinner:      [.main, .bowl, .soup],
        .other:       Set(FoodCategory.allCases),
    ]

    public struct Options: Sendable {
        public var budgetTight: Bool
        public var limit: Int
        public init(budgetTight: Bool = false, limit: Int = 5) {
            self.budgetTight = budgetTight
            self.limit = limit
        }
        public static let `default` = Options()
    }

    public static func suggest(
        library: [FoodDTO],
        mode: Mode,
        restrictions: [String],
        lowAppetite: Bool,
        slot: Slot,
        remaining: RemainingMacros,
        options: Options = .default
    ) -> [ScoredFood] {
        let candidates = library.filter { food in
            guard food.modeFit.contains(mode) else { return false }
            if restrictions.contains(where: { food.allergens.contains($0) }) { return false }
            guard let allowed = slotCategories[slot], allowed.contains(food.category) else { return false }
            if mode == .reset, wouldBreachCap(food, remaining: remaining) { return false }
            if options.budgetTight, food.costTier == .high { return false }
            return true
        }

        let scored: [ScoredFood] = candidates.map { food in
            let (score, reasons) = scorer(for: mode)(food, lowAppetite, remaining)
            return ScoredFood(food: food, score: score, reasons: reasons)
        }

        return Array(scored.sorted { $0.score > $1.score }.prefix(options.limit))
    }

    /// Remaining headroom for the day. Mode-aware: only emits Reset caps in reset mode.
    public static func computeRemaining(
        totals: DailyTotals,
        targets: MacroTargets
    ) -> RemainingMacros {
        RemainingMacros(
            calories: targets.calories - totals.calories,
            proteinG: targets.proteinG - totals.proteinG,
            carbsG: targets.carbsG - totals.carbsG,
            fatG: targets.fatG - totals.fatG,
            sodiumMg: targets.sodiumMgMax.map { $0 - totals.sodiumMg },
            addedSugarG: targets.addedSugarGMax.map { $0 - totals.addedSugarG },
            saturatedFatG: targets.saturatedFatGMax.map { $0 - totals.saturatedFatG },
            fiberG: targets.fiberGMin.map { $0 - totals.fiberG }
        )
    }

    // MARK: - Private

    private static func wouldBreachCap(_ food: FoodDTO, remaining: RemainingMacros) -> Bool {
        let p = food.perServing
        if let s = remaining.sodiumMg,        p.sodiumMg > s        { return true }
        if let s = remaining.addedSugarG,     p.addedSugarG > s     { return true }
        if let s = remaining.saturatedFatG,   p.saturatedFatG > s   { return true }
        return false
    }

    private typealias Scorer = (FoodDTO, Bool, RemainingMacros) -> (Double, [String])

    private static func scorer(for mode: Mode) -> Scorer {
        switch mode {
        case .build: return buildScore
        case .reset: return resetScore
        }
    }

    private static func buildScore(_ food: FoodDTO, lowAppetite: Bool, _ remaining: RemainingMacros) -> (Double, [String]) {
        var reasons: [String] = []
        let fit = Score.macroFit(food, remaining: remaining)
        let density = Score.rampUp(Double(food.perServing.calories), ceiling: 900)
        let value = Score.rampUp(Score.calsPerDollar(food), ceiling: 400)
        let liquid = (lowAppetite && food.category == .smoothie) ? 1.0 : 0.0
        let appetite = (lowAppetite && food.appetiteFriendly) ? 0.5 : 0.0

        if density > 0.7 { reasons.append("calorie-dense") }
        if liquid > 0    { reasons.append("liquid — easy when appetite is low") }
        if value > 0.6   { reasons.append("great calories-per-dollar") }
        if fit > 0.7     { reasons.append("fills today's gap") }

        let score = 0.35 * fit + 0.25 * density + 0.15 * value + 0.15 * liquid + 0.10 * appetite
        return (score, reasons)
    }

    private static func resetScore(_ food: FoodDTO, _ lowAppetite: Bool, _ remaining: RemainingMacros) -> (Double, [String]) {
        var reasons: [String] = []
        let p = food.perServing
        let fit = Score.macroFit(food, remaining: remaining)
        let fiber = Score.rampUp(Double(p.fiberG), ceiling: 12)
        let lowSodium = Score.rampDown(Double(p.sodiumMg), ceiling: 600)
        let lowSugar = Score.rampDown(Double(p.addedSugarG), ceiling: 15)
        let proteinDensity = Score.rampUp(Score.proteinPerCal(food) * 1000, ceiling: 100)
        let sodiumCap = Score.respectsCap(value: Double(p.sodiumMg), headroom: remaining.sodiumMg)
        let sugarCap = Score.respectsCap(value: Double(p.addedSugarG), headroom: remaining.addedSugarG)
        let satFatCap = Score.respectsCap(value: Double(p.saturatedFatG), headroom: remaining.saturatedFatG)

        if fiber > 0.6         { reasons.append("fiber-rich") }
        if lowSodium > 0.7     { reasons.append("low sodium") }
        if proteinDensity > 0.7 { reasons.append("lean protein") }
        if food.tags.contains("omega-3") { reasons.append("omega-3") }
        if food.tags.contains("dash")         { reasons.append("DASH-friendly") }
        else if food.tags.contains("mediterranean") { reasons.append("Mediterranean") }

        let score = 0.25 * fit + 0.20 * fiber + 0.15 * lowSodium + 0.10 * lowSugar
                  + 0.15 * proteinDensity + 0.05 * sodiumCap + 0.05 * sugarCap + 0.05 * satFatCap
        return (score, reasons)
    }
}
