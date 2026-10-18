import Foundation

/// Per-exercise strength progress, one headline number per exercise shape:
///
/// - **Loaded lifts** (`ExerciseDTO.tracksPerSetWeight`, a weight on every set):
///   an *estimated* one-rep max from Epley's formula (Epley 1985):
///   `weight × (1 + reps / 30)`. It is a coarse estimate, so it is only taken
///   from sets of 1–12 reps, where it is least misleading; heavier sets of more
///   reps are ignored rather than extrapolated.
/// - **Bodyweight / fixed-load reps** (one-tap exercises): the most reps logged
///   in a single day. A day, not a set, because the inline +1 button logs one
///   rep per tap, so a "best single set" would read 1 for anyone who taps.
/// - **Duration exercises** (loaded carries, logged in minutes): the most
///   minutes logged in a single day.
/// - **Isometric holds**: the longest single hold in seconds.
///
/// None of the non-loaded figures is an estimate: each is a plain maximum of what was logged.
public enum StrengthProgress {

    /// Highest rep count an estimate is taken from.
    public static let maxReps = 12
    /// "Gain" compares today's best with the best set from before this window.
    public static let windowDays = 28

    /// What a `Lift`'s headline number measures.
    public enum Metric: Equatable, Sendable {
        /// Estimated one-rep max, pounds.
        case estimatedMax
        /// Most reps logged in one day.
        case bestReps
        /// Most minutes logged in one day (duration exercises).
        case bestMinutes
        /// Longest single hold, seconds (isometrics).
        case bestHold

        /// Unit word for the non-weight metrics; nil when the number is a weight.
        public var unitLabel: String? {
            switch self {
            case .estimatedMax: return nil
            case .bestReps:     return "reps"
            case .bestMinutes:  return "min"
            case .bestHold:     return "sec"
            }
        }
    }

    public struct Lift: Equatable, Identifiable, Sendable {
        public var id: String { exerciseId }
        public let exerciseId: String
        public let name: String
        public let metric: Metric
        /// The headline number in the metric's unit (lb, reps, min or sec).
        public let headline: Double
        /// Best headline from before the window; nil if the exercise is newer than that or wasn't trained inside the window.
        public let previousHeadline: Double?
        /// Best estimated one-rep max across every counted set (lb). Loaded lifts only; 0 otherwise.
        public let estimatedMaxLb: Double
        /// The set that produced it. Loaded lifts only; 0 otherwise.
        public let bestWeightLb: Double
        public let bestReps: Int
        /// Best estimate from before the window. Loaded lifts only.
        public let previousMaxLb: Double?
        public let lastTrained: Date

        /// Change in the estimate over the window; nil when there is nothing older to compare to. Loaded lifts only.
        public var gainLb: Double? { metric == .estimatedMax ? previousMaxLb.map { estimatedMaxLb - $0 } : nil }
        /// Change in the headline over the window, in the metric's unit; nil when there is nothing older to compare to.
        public var change: Double? { previousHeadline.map { headline - $0 } }
    }

    public static func estimatedOneRepMax(weightLb: Double, reps: Int) -> Double {
        // A single is its own max; Epley only extrapolates from 2+ reps.
        reps <= 1 ? weightLb : weightLb * (1 + Double(reps) / 30)
    }

    /// Exercises with at least one countable set, most recently trained first.
    public static func lifts(
        sets: [WorkoutSetDTO],
        exercises: [ExerciseDTO],
        now: Date,
        calendar: Calendar = .current
    ) -> [Lift] {
        let cutoff = calendar.date(byAdding: .day, value: -windowDays, to: now) ?? now
        let byId = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var loadedSets: [String: [WorkoutSetDTO]] = [:]
        var otherSets: [String: [WorkoutSetDTO]] = [:]
        for s in sets {
            guard let ex = byId[s.exerciseId] else { continue }
            if ex.tracksPerSetWeight {
                guard let w = s.weightLb, w > 0, (1...maxReps).contains(s.reps) else { continue }
                loadedSets[s.exerciseId, default: []].append(s)
            } else if ex.category != .cardio && ex.category != .mobility {
                otherSets[s.exerciseId, default: []].append(s)
            }
        }

        var out: [Lift] = loadedSets.compactMap { id, rows -> Lift? in
            guard let ex = byId[id],
                  let best = rows.max(by: { est($0) < est($1) }),
                  let last = rows.map(\.timestamp).max() else { return nil }
            // Nothing trained inside the window → no "change over 4 weeks" to claim.
            let older = last >= cutoff ? rows.filter { $0.timestamp < cutoff }.map(est).max() : nil
            return Lift(
                exerciseId: id, name: ex.name, metric: .estimatedMax,
                headline: est(best), previousHeadline: older,
                estimatedMaxLb: est(best),
                bestWeightLb: best.weightLb ?? 0, bestReps: best.reps,
                previousMaxLb: older, lastTrained: last
            )
        }

        let cutoffDay = calendar.startOfDay(for: cutoff)
        for (id, rows) in otherSets {
            guard let ex = byId[id] else { continue }
            let metric: Metric = ex.isIsometric ? .bestHold : (ex.kind == .duration ? .bestMinutes : .bestReps)
            // (day, value) pairs: a hold is its own value; reps/minutes add up per day.
            var perDay: [Date: Double] = [:]
            var last: Date?
            for s in rows {
                let value: Double
                if metric == .bestHold {
                    guard let secs = s.holdSeconds, secs > 0 else { continue }
                    value = Double(secs)
                } else {
                    guard s.reps > 0 else { continue }
                    value = Double(s.reps)
                }
                let day = calendar.startOfDay(for: s.timestamp)
                perDay[day] = metric == .bestHold ? max(perDay[day] ?? 0, value) : (perDay[day] ?? 0) + value
                if last.map({ s.timestamp > $0 }) ?? true { last = s.timestamp }
            }
            guard let lastTrained = last, let best = perDay.values.max() else { continue }
            let older = lastTrained >= cutoff ? perDay.filter { $0.key < cutoffDay }.values.max() : nil
            out.append(Lift(
                exerciseId: id, name: ex.name, metric: metric,
                headline: best, previousHeadline: older,
                estimatedMaxLb: 0, bestWeightLb: 0, bestReps: 0,
                previousMaxLb: nil, lastTrained: lastTrained
            ))
        }

        return out.sorted { ($0.lastTrained, $1.name) > ($1.lastTrained, $0.name) }
    }

    private static func est(_ s: WorkoutSetDTO) -> Double {
        estimatedOneRepMax(weightLb: s.weightLb ?? 0, reps: s.reps)
    }
}
