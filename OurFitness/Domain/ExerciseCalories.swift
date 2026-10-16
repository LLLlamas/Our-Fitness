// The calorie estimators that need a named exercise.
//
// Split out of CalorieEstimator.swift so that file can stay dependency-free and
// compile into the watch target. This overload reaches for ExerciseDTO and
// ExerciseInfo (~1,800 lines of Domain between them), which the watch has no use
// for — it quick-logs fixed-load movements through the flat-MET
// caloriesForReps(reps:loadLb:) instead.
//
// Same enum, same call-site spelling: CalorieEstimator.caloriesForReps(reps:exercise:).

import Foundation

extension CalorieEstimator {

    /// Exercise-specific rep estimate. Uses the named-exercise MET and tempo from
    /// ExerciseInfo, falling back to category defaults when the name is unknown.
    public static func caloriesForReps(
        reps: Int,
        exercise: ExerciseDTO,
        bodyWeightLb: Double
    ) -> Double {
        let info = ExerciseInfo.meta(for: exercise)
        let hours = (Double(reps) * info.secondsPerRep) / 3600.0
        return kcal(mets: info.met, bodyWeightLb: bodyWeightLb, hours: hours)
    }

    /// THE per-set estimate — every logging surface and the set editor go through
    /// this, so a logged set and its later correction land on the same figure.
    /// Dispatches on the exercise's SHAPE, never on the user's goal:
    ///   • `holdSeconds` set → isometric hold at the exercise's researched MET
    ///   • `.duration` kind → `reps` carries minutes; flat load-aware duration MET
    ///   • fixed `loadLb` (e.g. Lifted Baby) → flat load-aware per-rep MET
    ///   • otherwise → the exercise's researched MET and tempo
    /// All estimators are activity-only (MET − 1); never hand-roll the product here.
    ///
    /// `loadLb` is the load THE ROW was done at (its stamped `weightLb`), for a
    /// fixed-load exercise whose current `loadLb` may have been edited since.
    /// nil = the exercise's current load, so every existing caller (and the
    /// watch) is unchanged. It is honoured only when the exercise itself has a
    /// fixed load — it can never turn an unloaded movement into a loaded one.
    /// Today the flat estimators read only the load's PRESENCE, so the figure
    /// does not move with its value; the parameter keeps a re-priced old row
    /// pointed at its own load if a weight-aware estimator ever lands.
    public static func caloriesForSet(
        exercise: ExerciseDTO,
        reps: Int,
        holdSeconds: Int?,
        bodyWeightLb: Double,
        loadLb: Double? = nil
    ) -> Double {
        let fixedLoad: Double? = exercise.loadLb == nil ? nil : (loadLb ?? exercise.loadLb)
        if let seconds = holdSeconds {
            return caloriesForIsometric(
                seconds: Double(seconds),
                met: ExerciseInfo.meta(for: exercise).met,
                bodyWeightLb: bodyWeightLb
            )
        }
        if exercise.kind == .duration {
            return caloriesForDuration(
                minutes: Double(reps), loadLb: fixedLoad, bodyWeightLb: bodyWeightLb
            )
        }
        if fixedLoad != nil {
            return caloriesForReps(reps: reps, loadLb: fixedLoad, bodyWeightLb: bodyWeightLb)
        }
        return caloriesForReps(reps: reps, exercise: exercise, bodyWeightLb: bodyWeightLb)
    }
}

extension ExerciseDTO {
    /// The load a fixed-load row carries: the row's own `weightLb` when it has a
    /// usable one, else the exercise's current `loadLb`. nil when the row is not
    /// a fixed-load row (no `loadLb` on the exercise, or a hold — holds never get
    /// a weight), in which case callers keep whatever weight they were given.
    ///
    /// THE definition behind both halves of "history keeps the weight each rep
    /// was done at": logging stamps `exercise.fixedLoadLb(forRowWeight: nil, …)`,
    /// and re-pricing an edited row passes its stamped weight so a later change
    /// to `loadLb` can't leak backwards.
    public func fixedLoadLb(forRowWeight rowWeightLb: Double?, holdSeconds: Int?) -> Double? {
        guard let current = loadLb, holdSeconds == nil else { return nil }
        if let w = rowWeightLb, w > 0, w.isFinite { return w }
        return current
    }
}
