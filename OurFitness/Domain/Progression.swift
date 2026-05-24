// Workout progression schemes. Pure.
// To add a scheme: implement the case in `nextTarget` switch + new enum case.

import Foundation

public enum Progression {

    public struct Target: Equatable, Sendable {
        public var targetWeightLb: Double?
        public var targetReps: Int
        public var notes: String
        public init(targetWeightLb: Double? = nil, targetReps: Int, notes: String) {
            self.targetWeightLb = targetWeightLb
            self.targetReps = targetReps
            self.notes = notes
        }
    }

    /// Compute the next session's target. `history` is most-recent-first.
    public static func nextTarget(
        scheme: ProgressionScheme,
        spec: ProgramSetSpec,
        history: [WorkoutSetDTO]
    ) -> Target {
        switch scheme {
        case .linear:            return linear(spec, history)
        case .doubleProgression: return doubleProgression(spec, history)
        case .rpeBased:          return rpeBased(spec, history)
        }
    }

    /// Heaviest weight at any rep count; ties broken by reps.
    public static func personalRecord(_ history: [WorkoutSetDTO]) -> WorkoutSetDTO? {
        guard !history.isEmpty else { return nil }
        return history.reduce(history[0]) { best, s in
            let sw = s.weightLb ?? 0
            let bw = best.weightLb ?? 0
            if sw > bw { return s }
            if sw == bw && s.reps > best.reps { return s }
            return best
        }
    }

    // MARK: - Strategies

    private static func linear(_ spec: ProgramSetSpec, _ history: [WorkoutSetDTO]) -> Target {
        let top = spec.repsTop
        guard let last = history.first else {
            return Target(targetReps: top, notes: "First session — pick a weight you can hit top of range.")
        }
        if last.reps >= top, (last.weightLb ?? 0) > 0 {
            return Target(
                targetWeightLb: (last.weightLb ?? 0) + 5,
                targetReps: top,
                notes: "Hit top last time — +5 lb."
            )
        }
        return Target(targetWeightLb: last.weightLb, targetReps: top,
                      notes: "Repeat weight, push for top of range.")
    }

    private static func doubleProgression(_ spec: ProgramSetSpec, _ history: [WorkoutSetDTO]) -> Target {
        let (bottom, top) = (spec.repsBottom, spec.repsTop)
        guard let last = history.first else {
            return Target(targetReps: bottom, notes: "First session — start at bottom of range.")
        }
        if last.reps >= top {
            return Target(targetWeightLb: (last.weightLb ?? 0) + 5,
                          targetReps: bottom,
                          notes: "Hit top — +5 lb, reset to bottom.")
        }
        return Target(targetWeightLb: last.weightLb,
                      targetReps: min(top, last.reps + 1),
                      notes: "Add a rep.")
    }

    private static func rpeBased(_ spec: ProgramSetSpec, _ history: [WorkoutSetDTO]) -> Target {
        let top = spec.repsTop
        let cap = spec.rpeCap ?? 8
        guard let last = history.first else {
            return Target(targetReps: top,
                          notes: "First session — find a weight that feels like RPE \(Int(cap) - 1).")
        }
        let rpe = last.rpe ?? cap
        if rpe >= cap {
            return Target(targetWeightLb: last.weightLb,
                          targetReps: top,
                          notes: "Hold weight — last was RPE \(Self.fmt(rpe)) (cap \(Self.fmt(cap))).")
        }
        return Target(targetWeightLb: (last.weightLb ?? 0) + 5,
                      targetReps: top,
                      notes: "Last was RPE \(Self.fmt(rpe)) — room to add weight.")
    }

    private static func fmt(_ d: Double) -> String {
        d.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(d))
            : String(format: "%.1f", d)
    }
}
