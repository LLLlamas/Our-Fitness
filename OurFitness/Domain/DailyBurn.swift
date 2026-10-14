// Active-calorie estimate for a day, summed from the app's own logs: steps +
// strength/isometric sets + cardio + pilates + live sessions. Comparable to
// Apple Health's "active energy" — both are net of resting metabolism, because
// every figure here routes through `CalorieEstimator`, which subtracts the 1.0
// resting MET from the compendium value ((MET − 1) × bodyWeightKg × hours).
// Pure Domain — never a hardcoded per-rep kcal.
//
// Sessions whose movement the step count ALREADY contains are excluded rather
// than added on top; see `stepOverlappingActivityIds` / `stepOverlappingCardio`.

import Foundation

public enum DailyBurn {

    /// Live-session activities that are foot-borne, so iPhone/Watch already
    /// counted their steps and `stepsKcal` already charged for them. Adding the
    /// session estimate too would bill the same movement twice.
    ///
    /// `Activity.tracksDistance` is NOT the right signal here: cycling tracks
    /// distance but registers no steps, so excluding it would lose the ride
    /// entirely. The test suite pins every id below to a real catalog entry.
    ///
    /// Trade-off (same one walking has always carried): those steps are valued
    /// at the walking MET, so a logged run contributes less than its true cost.
    /// Under-counting once beats counting twice.
    public static let stepOverlappingActivityIds: Set<String> = [
        ActivityCatalog.walkingId,
        "activity-running",
        "activity-hiking",
    ]

    /// Legacy `CardioSessionDTO` types with the same step overlap. Bike, swim and
    /// elliptical produce no steps, so they stay counted.
    public static let stepOverlappingCardio: Set<CardioType> = [.walk, .run]

    /// The day's burn split by source. `metEstimate` is `total`; the Move card
    /// needs the parts, so the step-overlap exclusions live here once instead of
    /// being re-derived in the view.
    ///
    /// Values are raw (unrounded) calories. Round at the display boundary — the
    /// Move card rounds each source separately for its per-row figures, so
    /// rounding here would bake one choice in for every caller.
    public struct Breakdown: Equatable, Sendable {
        /// Step burn (MET 4.3, net 3.3). Counted in the day total, not in `trainingKcal`.
        public let stepsKcal: Double
        /// Strength / isometric sets, from their stored log-time estimate.
        public let setsKcal: Double
        /// Cardio sessions; walks and runs excluded (already counted via steps).
        public let cardioKcal: Double
        /// Pilates, derived from duration (MET 3.0, net 2.0) — it stores no estimate.
        public let pilatesKcal: Double
        /// Live sessions; the foot-borne activities excluded (same reason as cardio).
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
            // Exclude logged walks and runs — those steps are already in the step
            // count, so adding the session on top would double-count.
            cardioKcal: cardio.reduce(0) {
                $0 + (stepOverlappingCardio.contains($1.type) ? 0 : ($1.caloriesEst ?? 0))
            },
            // Pilates has no stored estimate — derive from duration (MET 3.0).
            pilatesKcal: pilates.reduce(0) {
                $0 + CalorieEstimator.caloriesForPilates(minutes: Double($1.durationMinutes), bodyWeightLb: bodyWeightLb)
            },
            // Live sessions store their MET estimate at log time. Walking, running
            // and hiking overlap with the step count, so exclude them here (mirrors
            // the cardio exclusion above).
            activitiesKcal: activities.reduce(0) {
                $0 + (stepOverlappingActivityIds.contains($1.activityId) ? 0 : ($1.caloriesEst ?? 0))
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
