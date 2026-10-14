// MET-based calorie estimates for rep-based, duration-based, and step-based activity.
//
// Formula: kcal = (MET − 1) × bodyWeightKg × hours.
//
// Why the −1: a MET is a multiple of RESTING metabolism, so MET × kg × hours is
// GROSS expenditure — it includes the calories the body would have spent lying
// still for the same stretch of time. Everything these helpers feed is labelled
// "active" / "burn" and sits next to Apple Health's active energy, which is net
// of resting. Subtracting the 1.0 resting MET is the standard gross→net
// conversion, and it's what makes that side-by-side comparison honest.
//
// If a caller ever needs the GROSS figure — a TDEE-style total where resting is
// not accounted for separately — add a gross entry point rather than dropping
// the −1 here. Nothing needs one today: Targets.swift computes TDEE
// independently (Mifflin-St Jeor BMR × activity multiplier) and consumes none of
// these functions.
//
// Sources:
//   Ainsworth BE et al. "2011 Compendium of Physical Activities." Med Sci Sports Exerc, 2011.
//   Tudor-Locke C et al. "How many steps/day are enough?" Sports Med, 2004.
//   ACSM's Guidelines for Exercise Testing and Prescription, 11th ed., 2022.

import Foundation

public enum CalorieEstimator {

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
        return activeKcal(mets: mets, bodyWeightLb: bodyWeightLb, hours: hours)
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
        return activeKcal(mets: info.met, bodyWeightLb: bodyWeightLb, hours: hours)
    }

    /// Duration-based estimate (parenting lifts with a known load, pilates, cardio).
    public static func caloriesForDuration(
        minutes: Double,
        loadLb: Double?,
        bodyWeightLb: Double
    ) -> Double {
        let hours = minutes / 60.0
        let mets = loadLb != nil ? 4.5 : 3.5
        return activeKcal(mets: mets, bodyWeightLb: bodyWeightLb, hours: hours)
    }

    /// Pilates-specific estimate. MET 3.0 per Ainsworth code 06010 (pilates, general).
    public static func caloriesForPilates(minutes: Double, bodyWeightLb: Double) -> Double {
        activeKcal(mets: 3.0, bodyWeightLb: bodyWeightLb, hours: minutes / 60.0)
    }

    /// Timed live-session estimate (basketball, soccer, swimming, etc.). The MET
    /// comes from the chosen `Activity` in `ActivityCatalog`; minutes is the
    /// ACTUAL elapsed time of the session. Deterministic — never AI-adjusted.
    public static func caloriesForActivity(met: Double, minutes: Double, bodyWeightLb: Double) -> Double {
        activeKcal(mets: met, bodyWeightLb: bodyWeightLb, hours: minutes / 60.0)
    }

    /// Isometric hold estimate (plank, dead hang, wall sit, etc.).
    ///
    /// Derivation: isometric contractions are metabolically moderate. The plank and
    /// similar anti-extension holds sit at ~3.5–4.0 METs in the literature (Ainsworth
    /// code 02110 — calisthenics, general, 3.5 MET; McGill 2007 VO₂ data for plank
    /// gives ~3.8 MET at bodyweight; see also Calatayud et al., J Hum Kinet, 2014 for
    /// plank O₂ cost). Default 3.8 is conservative and appropriate for a bodyweight
    /// plank; loaded isometrics (dead hang, weighted hold) pull higher.
    ///
    /// Validation: a 60 s plank at 150 lb is (3.8 − 1) × 68.04 kg × (60/3600) h
    /// ≈ 3.2 cal of activity energy. Small by design — one minute of moderate work
    /// is one minute of moderate work.
    ///
    /// Pass `exercise`-specific MET from ExerciseInfo when available; this default
    /// applies when called directly.
    public static func caloriesForIsometric(seconds: Double, met: Double = 3.8, bodyWeightLb: Double) -> Double {
        activeKcal(mets: met, bodyWeightLb: bodyWeightLb, hours: seconds / 3600.0)
    }

    /// Step-count calorie estimate.
    ///
    /// Derivation: walking at 3.5 mph (MET 4.3 per Ainsworth 2011) covers
    /// 3.5 × 5,280 = 18,480 ft/hour; an average stride of 30 in (2.5 ft) turns that
    /// into 18,480 / 2.5 = 7,392 steps/hour, i.e. 2,112 steps per mile.
    /// kcal = (MET − 1) × kg × hours = 3.3 × kg × (steps / 7392).
    ///
    /// At 180 lb, 10,000 steps is 1.353 h over 4.73 miles → 3.3 × 81.6466 × 1.353
    /// ≈ 364 cal of activity energy, about 77 cal per mile. The same model's GROSS
    /// figure (4.3 METs) is ≈ 475 cal, or ≈ 100 cal/mile — THAT is the number the
    /// familiar "~100 cal per mile" rule of thumb quotes, because the rule counts
    /// the resting energy spent during the walk. We report the activity-only
    /// share, so ours is lower by design.
    public static func caloriesForSteps(steps: Int, bodyWeightLb: Double) -> Double {
        let stepsPerHour: Double = 7_392
        let hours = Double(steps) / stepsPerHour
        return activeKcal(mets: 4.3, bodyWeightLb: bodyWeightLb, hours: hours)
    }

    /// Activity-only ("net") energy: the gross MET product minus the 1.0 resting
    /// MET the compendium bakes into every value. Clamped at zero so a
    /// sub-resting MET can never produce a negative burn.
    private static func activeKcal(mets: Double, bodyWeightLb: Double, hours: Double) -> Double {
        grossKcal(mets: max(0, mets - 1.0), bodyWeightLb: bodyWeightLb, hours: hours)
    }

    /// Raw compendium product — GROSS expenditure, resting included. Private on
    /// purpose: every user-facing figure in the app is an active-energy figure.
    private static func grossKcal(mets: Double, bodyWeightLb: Double, hours: Double) -> Double {
        let kg = bodyWeightLb * Units.kgPerLb
        return mets * kg * hours
    }
}
