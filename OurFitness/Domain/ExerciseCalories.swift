// The one calorie estimator that needs a named exercise.
//
// Split out of CalorieEstimator.swift so that file can stay dependency-free and
// compile into the watch target. This overload reaches for ExerciseDTO and
// ExerciseInfo (~1,800 lines of Domain between them), which the watch has no use
// for — it quick-logs circuit movements through the flat-MET
// caloriesForReps(reps:loadLb:) instead.
//
// Same enum, same call-site spelling: CalorieEstimator.caloriesForReps(reps:exercise:).
// Nothing changed for existing callers.

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
}
