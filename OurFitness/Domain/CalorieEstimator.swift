// MET-based calorie estimates for rep- and duration-based exercises.
// Formula: kcal = METs × bodyWeightKg × hours.

import Foundation

public enum CalorieEstimator {

    /// Assumed tempo when converting rep counts to duration. Most parenting-
    /// flavored lifts (baby/stroller bumps) sit around the 3-second mark
    /// concentric-to-eccentric; faster tempos would under-report kcal.
    public static let secondsPerRep: Double = 3.0

    private static let kgPerLb: Double = 0.453592

    public static func caloriesForReps(
        reps: Int,
        loadLb: Double?,
        bodyWeightLb: Double
    ) -> Double {
        let hours = (Double(reps) * secondsPerRep) / 3600.0
        let mets = loadLb != nil ? 4.0 : 3.5
        return kcal(mets: mets, bodyWeightLb: bodyWeightLb, hours: hours)
    }

    public static func caloriesForDuration(
        minutes: Double,
        loadLb: Double?,
        bodyWeightLb: Double
    ) -> Double {
        let hours = minutes / 60.0
        let mets = loadLb != nil ? 4.5 : 3.5
        return kcal(mets: mets, bodyWeightLb: bodyWeightLb, hours: hours)
    }

    private static func kcal(mets: Double, bodyWeightLb: Double, hours: Double) -> Double {
        let kg = bodyWeightLb * kgPerLb
        return mets * kg * hours
    }
}
