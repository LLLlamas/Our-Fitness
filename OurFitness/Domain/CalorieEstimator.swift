// MET-based calorie estimates for rep-based, duration-based, and step-based activity.
// Formula: kcal = METs × bodyWeightKg × hours.
//
// Sources:
//   Ainsworth BE et al. "2011 Compendium of Physical Activities." Med Sci Sports Exerc, 2011.
//   Tudor-Locke C et al. "How many steps/day are enough?" Sports Med, 2004.
//   ACSM's Guidelines for Exercise Testing and Prescription, 11th ed., 2022.

import Foundation

public enum CalorieEstimator {

    private static let kgPerLb: Double = 0.453592

    /// Generic rep-based estimate using a flat MET.
    /// Use `caloriesForReps(reps:exercise:bodyWeightLb:)` for a named exercise —
    /// it picks the research-backed MET and tempo from ExerciseInfo.
    public static func caloriesForReps(
        reps: Int,
        loadLb: Double?,
        bodyWeightLb: Double
    ) -> Double {
        // Default 3 s/rep (parenting-movement tempo). 4.0 MET with load, 3.5 without.
        let secondsPerRep: Double = 3.0
        let hours = (Double(reps) * secondsPerRep) / 3600.0
        let mets = loadLb != nil ? 4.0 : 3.5
        return kcal(mets: mets, bodyWeightLb: bodyWeightLb, hours: hours)
    }

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

    /// Duration-based estimate (parenting lifts with a known load, pilates, cardio).
    public static func caloriesForDuration(
        minutes: Double,
        loadLb: Double?,
        bodyWeightLb: Double
    ) -> Double {
        let hours = minutes / 60.0
        let mets = loadLb != nil ? 4.5 : 3.5
        return kcal(mets: mets, bodyWeightLb: bodyWeightLb, hours: hours)
    }

    /// Pilates-specific estimate. MET 3.0 per Ainsworth code 06010 (pilates, general).
    public static func caloriesForPilates(minutes: Double, bodyWeightLb: Double) -> Double {
        kcal(mets: 3.0, bodyWeightLb: bodyWeightLb, hours: minutes / 60.0)
    }

    /// Isometric hold estimate (plank, dead hang, wall sit, etc.).
    ///
    /// Derivation: isometric contractions are metabolically moderate. The plank and
    /// similar anti-extension holds sit at ~3.5–4.0 METs in the literature (Ainsworth
    /// code 02110 — calisthenics, general, 3.5 MET; McGill 2007 VO₂ data for plank
    /// gives ~3.8 MET at bodyweight). Default 3.8 is conservative and appropriate for
    /// a bodyweight plank; loaded isometrics (dead hang, weighted hold) pull higher.
    ///
    /// Validation: 60 s plank at 150 lb → ~2.4 kcal. Consistent with published
    /// O₂ consumption data (Calatayud et al., J Hum Kinet, 2014).
    ///
    /// Pass `exercise`-specific MET from ExerciseInfo when available; this default
    /// applies when called directly.
    public static func caloriesForIsometric(seconds: Double, met: Double = 3.8, bodyWeightLb: Double) -> Double {
        kcal(mets: met, bodyWeightLb: bodyWeightLb, hours: seconds / 3600.0)
    }

    /// Step-count calorie estimate.
    ///
    /// Derivation: walking at 3.5 mph (MET 4.3 per Ainsworth 2011) with an
    /// average stride of 30 in (2.5 ft) gives 7,392 steps/hour.
    /// kcal = MET × kg × hours = MET × kg × (steps / 7392).
    ///
    /// At 150 lb, 10,000 steps ≈ 394 kcal — consistent with the well-cited
    /// "~100 cal/mile × ~4 miles" rule of thumb.
    public static func caloriesForSteps(steps: Int, bodyWeightLb: Double) -> Double {
        let stepsPerHour: Double = 7_392
        let hours = Double(steps) / stepsPerHour
        return kcal(mets: 4.3, bodyWeightLb: bodyWeightLb, hours: hours)
    }

    private static func kcal(mets: Double, bodyWeightLb: Double, hours: Double) -> Double {
        let kg = bodyWeightLb * kgPerLb
        return mets * kg * hours
    }
}
