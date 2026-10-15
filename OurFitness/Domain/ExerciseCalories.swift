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
    public static func caloriesForSet(
        exercise: ExerciseDTO,
        reps: Int,
        holdSeconds: Int?,
        bodyWeightLb: Double
    ) -> Double {
        if let seconds = holdSeconds {
            return caloriesForIsometric(
                seconds: Double(seconds),
                met: ExerciseInfo.meta(for: exercise).met,
                bodyWeightLb: bodyWeightLb
            )
        }
        if exercise.kind == .duration {
            return caloriesForDuration(
                minutes: Double(reps), loadLb: exercise.loadLb, bodyWeightLb: bodyWeightLb
            )
        }
        if exercise.loadLb != nil {
            return caloriesForReps(reps: reps, loadLb: exercise.loadLb, bodyWeightLb: bodyWeightLb)
        }
        return caloriesForReps(reps: reps, exercise: exercise, bodyWeightLb: bodyWeightLb)
    }
}
