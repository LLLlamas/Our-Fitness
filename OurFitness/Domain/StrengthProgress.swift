import Foundation

/// Per-lift strength progress for loaded rep exercises (the ones that log a
/// weight on every set — `ExerciseDTO.tracksPerSetWeight`).
///
/// The headline figure is an *estimated* one-rep max from Epley's formula
/// (Epley 1985): `weight × (1 + reps / 30)`. It is a coarse estimate, so it is
/// only taken from sets of 1–12 reps, where it is least misleading; heavier
/// sets of more reps are ignored rather than extrapolated.
public enum StrengthProgress {

    /// Highest rep count an estimate is taken from.
    public static let maxReps = 12
    /// "Gain" compares the best estimate inside this window with the best from before it.
    public static let windowDays = 28

    public struct Lift: Equatable, Identifiable, Sendable {
        public var id: String { exerciseId }
        public let exerciseId: String
        public let name: String
        /// Best estimated one-rep max across every counted set (lb).
        public let estimatedMaxLb: Double
        /// The set that produced it.
        public let bestWeightLb: Double
        public let bestReps: Int
        /// Best estimate from before the window; nil if the lift is newer than that or wasn't trained inside the window.
        public let previousMaxLb: Double?
        /// Best estimate from inside the window; nil when the lift wasn't trained in it.
        public let recentMaxLb: Double?
        public let lastTrained: Date

        /// Change over the window: the best estimate inside it minus the best from
        /// before it. Negative when the recent best sits below the older one — a
        /// decline reads as a decline, not "no change". Nil when there is nothing
        /// older to compare to or nothing recent (newer lift / not trained in the window).
        public var gainLb: Double? {
            guard let previous = previousMaxLb, let recent = recentMaxLb else { return nil }
            return recent - previous
        }
    }

    public static func estimatedOneRepMax(weightLb: Double, reps: Int) -> Double {
        // A single is its own max; Epley only extrapolates from 2+ reps.
        reps <= 1 ? weightLb : weightLb * (1 + Double(reps) / 30)
    }

    /// Loaded lifts that have at least one countable set, most recently trained first.
    public static func lifts(
        sets: [WorkoutSetDTO],
        exercises: [ExerciseDTO],
        now: Date,
        calendar: Calendar = .current
    ) -> [Lift] {
        let cutoff = calendar.date(byAdding: .day, value: -windowDays, to: now) ?? now
        let loaded = Dictionary(
            exercises.filter(\.tracksPerSetWeight).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var byExercise: [String: [WorkoutSetDTO]] = [:]
        for s in sets where loaded[s.exerciseId] != nil {
            guard let w = s.weightLb, w > 0, (1...maxReps).contains(s.reps) else { continue }
            byExercise[s.exerciseId, default: []].append(s)
        }

        return byExercise.compactMap { id, rows -> Lift? in
            guard let ex = loaded[id],
                  let best = rows.max(by: { est($0) < est($1) }),
                  let last = rows.map(\.timestamp).max() else { return nil }
            // Nothing trained inside the window → no "change over 4 weeks" to claim.
            let recent = rows.filter { $0.timestamp >= cutoff }.map(est).max()
            let older = recent == nil ? nil : rows.filter { $0.timestamp < cutoff }.map(est).max()
            return Lift(
                exerciseId: id, name: ex.name,
                estimatedMaxLb: est(best),
                bestWeightLb: best.weightLb ?? 0, bestReps: best.reps,
                previousMaxLb: older, recentMaxLb: recent, lastTrained: last
            )
        }
        .sorted { ($0.lastTrained, $1.name) > ($1.lastTrained, $0.name) }
    }

    private static func est(_ s: WorkoutSetDTO) -> Double {
        estimatedOneRepMax(weightLb: s.weightLb ?? 0, reps: s.reps)
    }
}
