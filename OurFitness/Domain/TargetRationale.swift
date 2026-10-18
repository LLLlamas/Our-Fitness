// Turns a profile (+ optional latest health markers) into personalized,
// plain-language explanations of WHY each nutrition / movement target is what
// it is — anchored to the user's OWN numbers and their fitness goal.
//
//   .gain = slowly add muscle & mass        (calorie surplus, high protein)
//   .lose = lose weight via a modest deficit, steps, and cardio.
//   Heart-health targets (fiber, sodium, added sugar, saturated fat) apply to
//   everyone regardless of goal.
//
// Pure Swift. No SwiftUI / SwiftData. All numbers are derived from Targets /
// CalorieEstimator so the copy can never drift from the math the app uses.
//
// Copy rules (match CLAUDE.md): say "calories"/"cal" not "kcal"; spell out
// acronyms ("blood pressure" not "BP"); keep anatomical terms paired with a
// plain-English gloss in parentheses elsewhere in the app.
//
// Science note: claims here are intentionally softened to match current
// evidence. Sources are cited inline at each statement.
//
// Fully unit-tested (TargetRationaleTests).

import Foundation

public enum TargetRationale {

    // MARK: - Goal framing (FitnessGoal → plain English)

    /// One-line plain-English goal. No acronyms.
    public static func goalLine(for fitnessGoal: FitnessGoal) -> String {
        switch fitnessGoal {
        case .gain:
            return "Your goal: build muscle."
        case .lose:
            return "Your goal: lose weight."
        }
    }

    // MARK: - Calories

    public struct CalorieBreakdown: Equatable, Sendable {
        /// Calories your body burns at complete rest (Mifflin-St Jeor).
        public let bmr: Int
        /// Maintenance: what you burn on a normal day (BMR × activity).
        public let tdee: Int
        /// Your daily calorie goal.
        public let target: Int
        /// target − tdee. Positive = surplus, negative = deficit.
        public let delta: Int
        public let activityLabel: String
        public var isSurplus: Bool { delta > 0 }
    }

    public static func calories(for p: ProfileDTO) -> CalorieBreakdown {
        let v = p.vitals
        let bmr  = Targets.bmr(sex: v.sex, weightLb: v.weightLb, heightIn: v.heightIn, age: v.age)
        let tdee = Targets.tdee(v)
        let target = p.computedTargets.calories
        return CalorieBreakdown(
            bmr: bmr, tdee: tdee, target: target,
            delta: target - tdee, activityLabel: v.activity.label
        )
    }

    /// Plain-language "why your calorie target is what it is", tied to the goal.
    /// Sources: Mifflin-St Jeor (Frankenfield, J Am Diet Assoc 2005);
    /// gain/loss rates (Garthe, IJSNEM 2013; Helms, JISSN 2014).
    public static func calorieWhy(for p: ProfileDTO) -> String {
        let c = calories(for: p)
        let mag = abs(c.delta)
        switch p.fitnessGoal {
        case .gain:
            return "You burn about \(c.tdee) calories a day. Your goal adds roughly \(mag) on top to build muscle."
        case .lose:
            return "You burn about \(c.tdee) calories a day. Your goal is roughly \(mag) below that to lose fat."
        }
    }

    // MARK: - Protein

    public static func proteinPerLb(for p: ProfileDTO) -> Double {
        guard p.weightLb > 0 else { return 0 }
        return Double(p.computedTargets.proteinG) / p.weightLb
    }

    /// Sources: ISSN protein position stand (Jäger, JISSN 2017); thermic effect
    /// of protein 20–30% (Westerterp, Nutr Metab 2004).
    public static func proteinWhy(for p: ProfileDTO) -> String {
        let g = p.computedTargets.proteinG
        let perLb = proteinPerLb(for: p)
        let role: String
        switch p.fitnessGoal {
        case .gain:   role = "gives your body the material to build new muscle"
        case .lose: role = "protects your muscle while you lose fat"
        }
        return String(
            format: "Your %dg protein target is about %.1fg per pound — enough that it %@.",
            g, perLb, role
        )
    }

    // MARK: - Carbs

    public static func carbsWhy(for p: ProfileDTO) -> String {
        "Your \(p.computedTargets.carbsG)g of carbs fills the calories left after protein and fat."
    }

    // MARK: - Fat

    /// Fat as a whole-number % of the calorie target.
    public static func fatPctOfCalories(for p: ProfileDTO) -> Int {
        let cals = p.computedTargets.calories
        guard cals > 0 else { return 0 }
        return Int((Double(p.computedTargets.fatG) * 9.0 / Double(cals) * 100).rounded())
    }

    /// Source: low-fat diets and testosterone (Whittaker & Wu, JSBMB 2021).
    public static func fatWhy(for p: ProfileDTO) -> String {
        "Fat is about \(fatPctOfCalories(for: p))% of your calories (\(p.computedTargets.fatG)g) — enough for hormones and vitamins."
    }

    // MARK: - Heart-health targets (fiber floor + sodium / added-sugar / saturated-fat caps)
    //
    // These four apply to every profile regardless of goal. Copy ties each to the
    // heart-health numbers (cholesterol, blood pressure, blood sugar). Sources: soluble
    // fibre lowers LDL (Whitehead, AJCN 2014); DASH + lower sodium lowers blood
    // pressure (Sacks, NEJM 2001); added sugar and triglycerides (Te Morenga, BMJ
    // 2012); saturated-fat swap lowers LDL (Hooper, Cochrane 2020).

    /// Why your fiber floor is what it is. Reads the computed `fiberGMin`.
    public static func fiberWhy(for p: ProfileDTO) -> String {
        let g = p.computedTargets.fiberGMin ?? 35
        return "Aim for at least \(g)g a day. Fiber helps lower cholesterol."
    }

    /// Why your sodium cap is what it is. Reads the computed `sodiumMgMax`.
    public static func sodiumWhy(for p: ProfileDTO) -> String {
        let mg = p.computedTargets.sodiumMgMax ?? 1500
        return "Stay under about \(mg) mg a day. Less sodium helps lower blood pressure."
    }

    /// Why your added-sugar cap is what it is. Reads the computed `addedSugarGMax`.
    public static func addedSugarWhy(for p: ProfileDTO) -> String {
        let g = p.computedTargets.addedSugarGMax ?? 25
        return "Keep added sugar under about \(g)g a day. It spikes blood sugar without filling you up."
    }

    /// Why your saturated-fat cap is what it is. Reads the computed `saturatedFatGMax`.
    public static func saturatedFatWhy(for p: ProfileDTO) -> String {
        let g = p.computedTargets.saturatedFatGMax ?? 22
        return "Keep saturated fat under about \(g)g a day (a tenth of your calories). Less of it lowers LDL cholesterol."
    }

    // MARK: - Steps

    /// Plain-language "why this step goal", honest about what walking does and
    /// doesn't do on its own. Sources: Saint-Maurice (JAMA 2020) & Ding (Lancet
    /// Public Health 2025) for mortality; Hanson & Jones (BJSM 2015) for the
    /// blood-pressure effect and the weaker cholesterol/glucose response.
    public static func stepsWhy(fitnessGoal: FitnessGoal, goal: Int) -> String {
        switch fitnessGoal {
        case .gain:
            return "Your \(goal.formatted())-step goal keeps you active on top of lifting. Most of the health payoff arrives by about 7,000–8,000 steps."
        case .lose:
            return "Your \(goal.formatted())-step goal is your most repeatable daily burn. Most of the health payoff arrives by about 7,000–8,000 steps."
        }
    }

    // MARK: - Health markers (Progress)

    /// Plain-English "what your number means + what moves it", personalized to
    /// the user's latest value. Goal-neutral copy. Returns nil for
    /// markers without a logged value (caller can fall back to the range line).
    ///
    /// Reference cut-points: ACC/AHA 2017 (blood pressure); NCEP ATP III labels
    /// (lipids); ADA 2024 (glucose/A1c). Diet effects: soluble fibre lowers LDL
    /// (Whitehead, AJCN 2014); DASH + lower sodium lowers blood pressure (Sacks,
    /// NEJM 2001).
    public static func markerMeaning(kind: HealthMarkerKind, value: Double, fitnessGoal: FitnessGoal) -> String {
        let status = HealthRanges.status(for: kind, value: value)
        let v = Int(value.rounded())
        switch kind {
        case .ldl:
            let where_ = statusWord(status, optimal: "in the healthy range", borderline: "a little high", high: "high")
            return "Your LDL ('bad' cholesterol) of \(v) is \(where_)."
        case .hdl:
            let where_ = statusWord(status, optimal: "protective", borderline: "okay", high: "low")
            return "Your HDL ('good' cholesterol) of \(v) is \(where_)."
        case .triglycerides:
            let where_ = statusWord(status, optimal: "in the healthy range", borderline: "a little high", high: "high")
            return "Your triglycerides (blood fat) of \(v) are \(where_)."
        case .totalCholesterol:
            let where_ = statusWord(status, optimal: "desirable", borderline: "a little high", high: "high")
            return "Your total cholesterol of \(v) is \(where_)."
        case .bpSystolic, .bpDiastolic:
            let where_ = statusWord(status, optimal: "in the healthy range", borderline: "slightly elevated", high: "high")
            return "Your blood pressure reading of \(v) is \(where_)."
        case .fastingGlucose:
            let where_ = statusWord(status, optimal: "normal", borderline: "in the pre-diabetes range", high: "high")
            return "Your fasting blood sugar of \(v) is \(where_)."
        case .a1c:
            let where_ = statusWord(status, optimal: "normal", borderline: "in the pre-diabetes range", high: "high")
            return String(format: "Your A1c (average blood sugar over ~3 months) of %.1f is %@.", value, where_)
        case .restingHR:
            let where_ = statusWord(status, optimal: "healthy", borderline: "borderline", high: "worth watching")
            return "Your resting heart rate of \(v) beats per minute is \(where_)."
        }
    }

    private static func statusWord(_ s: HealthRanges.RangeStatus, optimal: String, borderline: String, high: String) -> String {
        switch s {
        case .optimal:    return optimal
        case .borderline: return borderline
        case .high:       return high
        case .unknown:    return optimal
        }
    }
}
