// MET-based active-calorie estimate for a day, summed from the app's own logs:
// steps + strength/isometric sets + cardio + pilates. Comparable to Apple
// Health's "active energy" (both exclude resting/BMR), so the two can sit side
// by side on the Move card. Pure Domain — all math via CalorieEstimator (MET ×
// bodyWeightKg × hours), never hardcoded per-rep kcal.

import Foundation

public enum DailyBurn {

    /// The day's burn split by source. `metEstimate` is `total`; the Move card
    /// needs the parts, so the walk-exclusion rules live here once instead of
    /// being re-derived in the view.
    ///
    /// Values are raw (unrounded) calories. Round at the display boundary — the
    /// Move card rounds each source separately for its per-row figures, so
    /// rounding here would bake one choice in for every caller.
    public struct Breakdown: Equatable, Sendable {
        /// Step burn (MET 4.3). Counted in the day total, not in `trainingKcal`.
        public let stepsKcal: Double
        /// Strength / isometric sets, from their stored log-time estimate.
        public let setsKcal: Double
        /// Cardio sessions, logged walks excluded (already counted via steps).
        public let cardioKcal: Double
        /// Pilates, derived from duration (MET 3.0) — it stores no estimate.
        public let pilatesKcal: Double
        /// Live sessions, the Walking activity excluded (same reason as cardio).
        public let activitiesKcal: Double

        /// Everything the user explicitly logged as a session — the burn Apple's
        /// sensors generally miss. Excludes steps.
        public var trainingKcal: Double { setsKcal + cardioKcal + pilatesKcal + activitiesKcal }

        /// Steps + training, matching Apple Health's "active energy" scope.
        public var totalKcal: Double { stepsKcal + trainingKcal }

        /// `totalKcal` rounded — identical to `metEstimate` for the same inputs.
        public var total: Int { Int(totalKcal.rounded()) }
    }

    /// Per-source split of the day's burn. Additive: `metEstimate` delegates here
    /// so the two can never disagree.
    public static func breakdown(
        steps: Int,
        sets: [WorkoutSetDTO],
        cardio: [CardioSessionDTO],
        pilates: [PilatesSessionDTO],
        activities: [ActivitySessionDTO] = [],
        bodyWeightLb: Double
    ) -> Breakdown {
        Breakdown(
            stepsKcal: CalorieEstimator.caloriesForSteps(steps: steps, bodyWeightLb: bodyWeightLb),
            // Sets and cardio store their MET estimate at log time.
            setsKcal: sets.reduce(0) { $0 + ($1.caloriesEst ?? 0) },
            // Exclude logged walks — walking is already counted via steps, so adding
            // walk sessions on top would double-count.
            cardioKcal: cardio.reduce(0) { $0 + ($1.type == .walk ? 0 : ($1.caloriesEst ?? 0)) },
            // Pilates has no stored estimate — derive from duration (MET 3.0).
            pilatesKcal: pilates.reduce(0) {
                $0 + CalorieEstimator.caloriesForPilates(minutes: Double($1.durationMinutes), bodyWeightLb: bodyWeightLb)
            },
            // Live sessions store their MET estimate at log time. The Walking activity
            // overlaps with steps, so exclude it here to avoid double-counting (mirrors
            // the cardio .walk exclusion above).
            activitiesKcal: activities.reduce(0) {
                $0 + ($1.activityId == ActivityCatalog.walkingId ? 0 : ($1.caloriesEst ?? 0))
            }
        )
    }

    public static func metEstimate(
        steps: Int,
        sets: [WorkoutSetDTO],
        cardio: [CardioSessionDTO],
        pilates: [PilatesSessionDTO],
        activities: [ActivitySessionDTO] = [],
        bodyWeightLb: Double
    ) -> Int {
        breakdown(
            steps: steps, sets: sets, cardio: cardio, pilates: pilates,
            activities: activities, bodyWeightLb: bodyWeightLb
        ).total
    }
}
