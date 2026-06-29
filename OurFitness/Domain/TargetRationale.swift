// Turns a profile (+ optional latest health markers) into personalized,
// plain-language explanations of WHY each nutrition / movement target is what
// it is — anchored to the user's OWN numbers and their Mode's goal.
//
//   Build   = slowly add muscle & mass        (calorie surplus, high protein)
//   Reset   = lose weight & improve the heart-health numbers
//             (cholesterol, blood pressure, blood sugar) via a modest deficit,
//             steps, and cardio.
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

    // MARK: - Goal framing (Mode → plain English)

    /// One-line plain-English goal for the mode. No acronyms.
    public static func goalLine(for mode: Mode) -> String {
        switch mode {
        case .build:
            return "You're in Build mode — the goal is to slowly add muscle and mass."
        case .circuit:
            return "You're in Reset mode — the goal is to lose weight and improve your heart-health numbers (cholesterol, blood pressure, blood sugar)."
        }
    }

    /// Very short goal tag, e.g. for a chip or section subtitle.
    public static func goalTag(for mode: Mode) -> String {
        switch mode {
        case .build:   return "slowly add muscle"
        case .circuit: return "lose fat · improve heart health"
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
        switch p.mode {
        case .build:
            return "You burn about \(c.tdee) calories on a normal day (your maintenance). To slowly add muscle, your goal eats roughly \(mag) calories above that — a controlled surplus. Aim to gain about a quarter to half a pound a week; gaining faster mostly adds fat, not muscle."
        case .circuit:
            return "You burn about \(c.tdee) calories on a normal day (your maintenance). To lose fat, your goal eats roughly \(mag) calories below that. That pace takes off about half a pound to a pound a week while protecting your muscle."
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
        switch p.mode {
        case .build:   role = "gives your body the material to build new muscle"
        case .circuit: role = "protects your muscle while you lose fat"
        }
        return String(
            format: "Your %dg protein target is about %.1fg for every pound you weigh — enough that it %@. Protein also keeps you full and costs the most energy to digest: your body burns 20–30%% of protein's calories just breaking it down.",
            g, perLb, role
        )
    }

    // MARK: - Carbs

    public static func carbsWhy(for p: ProfileDTO) -> String {
        "Carbs are whatever calories are left after protein and fat. They're your main fuel for training and for your brain. Your \(p.computedTargets.carbsG)g target simply fills the rest of your daily calories."
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
        "Fat is set to about \(fatPctOfCalories(for: p))% of your calories (\(p.computedTargets.fatG)g). Some fat is essential — your body needs it to make hormones and to absorb vitamins A, D, E, and K. Eating very low-fat can modestly lower testosterone, so this stays at a sensible floor."
    }

    // MARK: - Reset cardiometabolic targets (fiber floor + sodium / added-sugar / saturated-fat caps)
    //
    // These four only apply in Reset mode (the caps are nil in Build). Copy ties
    // each to the heart-health numbers Reset exists to improve. Sources: soluble
    // fibre lowers LDL (Whitehead, AJCN 2014); DASH + lower sodium lowers blood
    // pressure (Sacks, NEJM 2001); added sugar and triglycerides (Te Morenga, BMJ
    // 2012); saturated-fat swap lowers LDL (Hooper, Cochrane 2020).

    /// Why your fiber floor is what it is. Reads the computed `fiberGMin`.
    public static func fiberWhy(for p: ProfileDTO) -> String {
        let g = p.computedTargets.fiberGMin ?? 35
        return "Aim for at least \(g)g of fiber a day. Soluble fiber from oats, beans, and fruit binds cholesterol in your gut so less of the 'bad' LDL kind gets into your blood. It also slows how fast sugar hits your bloodstream and keeps you full on fewer calories."
    }

    /// Why your sodium cap is what it is. Reads the computed `sodiumMgMax`.
    public static func sodiumWhy(for p: ProfileDTO) -> String {
        let mg = p.computedTargets.sodiumMgMax ?? 1500
        return "Try to stay under about \(mg) mg of sodium a day. Less salt means less water your body holds onto and lower blood pressure — often a drop of several points on its own. Most sodium hides in restaurant and packaged food, not the salt shaker."
    }

    /// Why your added-sugar cap is what it is. Reads the computed `addedSugarGMax`.
    public static func addedSugarWhy(for p: ProfileDTO) -> String {
        let g = p.computedTargets.addedSugarGMax ?? 25
        return "Try to keep added sugar under about \(g)g a day. Added sugar spikes your blood sugar and raises triglycerides (the fat circulating in your blood) without filling you up — cutting it is one of the fastest ways to move those numbers."
    }

    /// Why your saturated-fat cap is what it is. Reads the computed `saturatedFatGMax`.
    public static func saturatedFatWhy(for p: ProfileDTO) -> String {
        let g = p.computedTargets.saturatedFatGMax ?? 22
        return "Try to keep saturated fat under about \(g)g a day (roughly a tenth of your calories). Swapping some saturated fat — fatty meat, butter, cheese — for unsaturated fat like olive oil, nuts, and fish lowers the 'bad' LDL cholesterol."
    }

    // MARK: - Steps

    /// Plain-language "why this step goal", honest about what walking does and
    /// doesn't do on its own. Sources: Saint-Maurice (JAMA 2020) & Ding (Lancet
    /// Public Health 2025) for mortality; Hanson & Jones (BJSM 2015) for the
    /// blood-pressure effect and the weaker cholesterol/glucose response.
    public static func stepsWhy(mode: Mode, goal: Int) -> String {
        switch mode {
        case .build:
            return "Your \(goal.formatted())-step goal keeps you active on top of lifting. Most of the health payoff from walking shows up by about 7,000–8,000 steps a day — every extra 1,000–2,000 steps lowers your risk of dying early, and the calories burned support your recovery without eating into your surplus."
        case .circuit:
            return "Your \(goal.formatted())-step goal is the movement engine for Reset. Walking reliably brings blood pressure down a few points and is your most repeatable daily calorie burn. Most of the benefit lands by about 7,000–8,000 steps — going higher keeps adding a little more. (Cholesterol and blood sugar respond best when you pair steps with cardio and the food tips.)"
        }
    }

    // MARK: - Health markers (Progress)

    /// Plain-English "what your number means + what moves it", personalized to
    /// the user's latest value and tied to the mode goal. Returns nil for
    /// markers without a logged value (caller can fall back to the range line).
    ///
    /// Reference cut-points: ACC/AHA 2017 (blood pressure); NCEP ATP III labels
    /// (lipids); ADA 2024 (glucose/A1c). Diet effects: soluble fibre lowers LDL
    /// (Whitehead, AJCN 2014); DASH + lower sodium lowers blood pressure (Sacks,
    /// NEJM 2001).
    public static func markerMeaning(kind: HealthMarkerKind, value: Double, mode: Mode) -> String {
        let status = HealthRanges.status(for: kind, value: value)
        let v = Int(value.rounded())
        switch kind {
        case .ldl:
            let where_ = statusWord(status, optimal: "in the healthy range", borderline: "a little high", high: "high")
            return "Your LDL (the 'bad' cholesterol that clogs arteries) of \(v) is \(where_). To move it down: more soluble fibre (oats, beans), less saturated fat, and fatty fish. Regular cardio helps too."
        case .hdl:
            let where_ = statusWord(status, optimal: "protective", borderline: "okay", high: "low")
            return "Your HDL (the 'good' cholesterol that clears the bad kind out) of \(v) is \(where_). Steady cardio nudges it up a couple of points over a couple of months."
        case .triglycerides:
            let where_ = statusWord(status, optimal: "in the healthy range", borderline: "a little high", high: "high")
            return "Your triglycerides (fat circulating in your blood) of \(v) are \(where_). Cutting added sugar and refined carbs and doing regular cardio lowers them about 10–20%."
        case .totalCholesterol:
            let where_ = statusWord(status, optimal: "desirable", borderline: "a little high", high: "high")
            return "Your total cholesterol of \(v) is \(where_). It's the sum of the good and bad kinds — the LDL and HDL split matters more than this one number."
        case .bpSystolic, .bpDiastolic:
            let where_ = statusWord(status, optimal: "in the healthy range", borderline: "slightly elevated", high: "high")
            return "Your blood pressure reading of \(v) is \(where_). Daily walking, less salt, and more potassium (bananas, sweet potato, spinach) bring it down — often by 5 points or more together."
        case .fastingGlucose:
            let where_ = statusWord(status, optimal: "normal", borderline: "in the pre-diabetes range", high: "high")
            return "Your fasting blood sugar of \(v) is \(where_). A single walk improves how your body handles sugar for the next day or two; consistent steps and fat loss help the most."
        case .a1c:
            let where_ = statusWord(status, optimal: "normal", borderline: "in the pre-diabetes range", high: "high")
            return String(format: "Your A1c (your average blood sugar over ~3 months) of %.1f is %@. Daily movement and losing excess fat are the biggest levers.", value, where_)
        case .restingHR:
            let where_ = statusWord(status, optimal: "healthy", borderline: "borderline", high: "worth watching")
            return "Your resting heart rate of \(v) beats per minute is \(where_). It's how hard your heart works at rest — regular cardio lowers it over weeks, and a lower resting rate is linked to living longer."
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
