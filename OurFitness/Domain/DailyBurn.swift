// MET-based active-calorie estimate for a day, summed from the app's own logs:
// steps + strength/isometric sets + cardio + pilates. Comparable to Apple
// Health's "active energy" (both exclude resting/BMR), so the two can sit side
// by side on the Move card. Pure Domain — all math via CalorieEstimator (MET ×
// bodyWeightKg × hours), never hardcoded per-rep kcal.

import Foundation

public enum DailyBurn {

    public static func metEstimate(
        steps: Int,
        sets: [WorkoutSetDTO],
        cardio: [CardioSessionDTO],
        pilates: [PilatesSessionDTO],
        activities: [ActivitySessionDTO] = [],
        bodyWeightLb: Double
    ) -> Int {
        var total = CalorieEstimator.caloriesForSteps(steps: steps, bodyWeightLb: bodyWeightLb)
        // Sets and cardio store their MET estimate at log time.
        total += sets.reduce(0) { $0 + ($1.caloriesEst ?? 0) }
        // Exclude logged walks — walking is already counted via steps, so adding
        // walk sessions on top would double-count.
        total += cardio.reduce(0) { $0 + ($1.type == .walk ? 0 : ($1.caloriesEst ?? 0)) }
        // Pilates has no stored estimate — derive from duration (MET 3.0).
        total += pilates.reduce(0) {
            $0 + CalorieEstimator.caloriesForPilates(minutes: Double($1.durationMinutes), bodyWeightLb: bodyWeightLb)
        }
        // Live sessions store their MET estimate at log time. The Walking activity
        // overlaps with steps, so exclude it here to avoid double-counting (mirrors
        // the cardio .walk exclusion above).
        total += activities.reduce(0) {
            $0 + ($1.activityId == "activity-walking" ? 0 : ($1.caloriesEst ?? 0))
        }
        return Int(total.rounded())
    }
}
