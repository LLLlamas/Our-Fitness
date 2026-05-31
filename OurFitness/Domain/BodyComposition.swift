// Body composition calculations: BMI, fat mass, lean mass, and US Navy
// circumference body fat estimation.
//
// Sources:
//   CDC / NIH standard BMI formula.
//   Hodgdon & Beckett (1984): US Navy circumference BF method.
//   Gallagher et al. (2000): body fat category thresholds by sex/age.
//   ACSM's Guidelines for Exercise Testing and Prescription, 11th ed. (2022).

import Foundation

public enum BodyComposition {

    // MARK: - BMI

    /// Weight in lb, height in inches → BMI (US Imperial formula).
    public static func bmi(weightLb: Double, heightIn: Double) -> Double {
        guard heightIn > 0 else { return 0 }
        return (weightLb / (heightIn * heightIn)) * 703.0
    }

    public static func bmiCategory(_ bmi: Double) -> (label: String, detail: String) {
        switch bmi {
        case ..<18.5:
            return ("Underweight",
                    "Below the healthy range. Prioritise nutrient-dense eating and progressive strength training.")
        case 18.5..<25.0:
            return ("Healthy",
                    "Healthy weight for most adults. Maintain with consistent activity and quality food.")
        case 25.0..<30.0:
            return ("Overweight",
                    "Modestly elevated risk. Activity quality and diet quality compound independently of the number on the scale.")
        default:
            return ("Obese",
                    "Elevated cardiovascular risk. Daily steps, adequate protein, and consistent sleep are the three highest-leverage inputs.")
        }
    }

    // MARK: - Fat mass / lean mass

    /// Pounds of body fat from a logged body weight and body fat %.
    public static func fatMassLb(weightLb: Double, bodyFatPct: Double) -> Double {
        weightLb * (bodyFatPct / 100.0)
    }

    /// Pounds of lean mass (everything that is not fat).
    public static func leanMassLb(weightLb: Double, bodyFatPct: Double) -> Double {
        weightLb - fatMassLb(weightLb: weightLb, bodyFatPct: bodyFatPct)
    }

    // MARK: - Body fat categories

    public static func bodyFatCategory(pct: Double, sex: Sex) -> (label: String, detail: String) {
        switch sex {
        case .male:
            switch pct {
            case ..<6:    return ("Essential", "Below the athletic floor — may impair hormones and recovery.")
            case 6..<14:  return ("Athletic", "Lean with visible definition. Typical for trained athletes.")
            case 14..<18: return ("Fitness", "Healthy with definition at lower end.")
            case 18..<25: return ("Acceptable", "Normal healthy adult range.")
            default:      return ("High", "Elevated cardiometabolic risk.")
            }
        case .female:
            switch pct {
            case ..<14:   return ("Essential", "Below the healthy floor for women.")
            case 14..<21: return ("Athletic", "Very lean, athletic range.")
            case 21..<25: return ("Fitness", "Healthy with definition.")
            case 25..<32: return ("Acceptable", "Normal healthy adult range.")
            default:      return ("High", "Elevated cardiometabolic risk.")
            }
        }
    }

    // MARK: - US Navy circumference BF estimate

    /// Estimates body fat % from tape-measure circumferences.
    ///
    /// Men: measure waist at the navel; neck at its narrowest.
    /// Women: waist at narrowest; hips at widest; neck at narrowest.
    ///
    /// Accurate to ±3–4 percentage points when measurements are taken correctly.
    /// Returns nil when inputs are missing or would produce invalid log arguments.
    public static func navyBodyFatPct(
        sex: Sex,
        heightIn: Double,
        waistIn: Double,
        neckIn: Double,
        hipIn: Double? = nil
    ) -> Double? {
        guard heightIn > 0, waistIn > 0, neckIn > 0 else { return nil }
        let pct: Double
        switch sex {
        case .male:
            let diff = waistIn - neckIn
            guard diff > 0 else { return nil }
            pct = 86.010 * log10(diff) - 70.041 * log10(heightIn) + 36.76
        case .female:
            guard let hip = hipIn, hip > 0 else { return nil }
            let sum = waistIn + hip - neckIn
            guard sum > 0 else { return nil }
            pct = 163.205 * log10(sum) - 97.684 * log10(heightIn) - 78.387
        }
        return max(3.0, min(60.0, pct))
    }

    // MARK: - Guidance copy

    /// Shown in the Body Fat detail sheet. Teaches users how to get a number to log.
    public static let measurementGuide: String = """
    How to measure your body fat %:

    1. Tape measure (US Navy method) — measure waist at the navel and neck at its narrowest point. Women also measure hips at the widest. This app can estimate it once you log those measurements. Accurate to ±3–4%.

    2. DEXA scan — gold standard. A 10-minute scan at a sports medicine clinic (typically $50–150). Reports total fat, lean, and bone mass split by region.

    3. Smart scale (bioimpedance) — Withings, Garmin, InBody. Convenient but swings ±5% with hydration. Use for the trend, not the absolute number.

    4. Skinfold calipers — accurate with a trained measurer. Jackson-Pollock 3-site takes 5 minutes and is accurate to ±3%.

    Pick one method and stay consistent. The trend over months matters far more than any single reading.
    """
}
