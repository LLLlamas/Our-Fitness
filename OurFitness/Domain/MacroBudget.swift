// Remaining macro / micronutrient budget for a day = targets − today's totals.
// Pure Domain. Powers the Circuit heart-health panel (fiber floor + sodium /
// added-sugar / saturated-fat caps) and "X to go" copy.
//
// Convention (matches RemainingMacros): for CAPS (sodium, added sugar, saturated
// fat) the value is how much room is LEFT under the cap — negative once exceeded.
// For the fiber FLOOR the value is signed distance to the floor — negative until
// the floor is met, positive once cleared. The four micro fields are nil in Build
// mode (no caps configured), so the UI can drive a Circuit-only panel off them.

import Foundation

public enum MacroBudget {

    public static func remaining(totals: DailyTotals, targets: MacroTargets) -> RemainingMacros {
        RemainingMacros(
            calories: targets.calories - totals.calories,
            proteinG: targets.proteinG - totals.proteinG,
            carbsG: targets.carbsG - totals.carbsG,
            fatG: targets.fatG - totals.fatG,
            sodiumMg: targets.sodiumMgMax.map { $0 - totals.sodiumMg },
            addedSugarG: targets.addedSugarGMax.map { $0 - totals.addedSugarG },
            saturatedFatG: targets.saturatedFatGMax.map { $0 - totals.saturatedFatG },
            fiberG: targets.fiberGMin.map { totals.fiberG - $0 }   // negative until floor met
        )
    }
}
