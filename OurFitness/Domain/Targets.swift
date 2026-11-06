// Mifflin-St Jeor BMR + activity multiplier + per-plan suggestions (maintain /
// lose / gain) or the user's own custom targets.
// Pure. Tested.

import Foundation

public enum Targets {

    /// The knobs a suggested plan is allowed to change. Everything else about the
    /// targets — including the heart-health micros below — is the same for everyone.
    /// Each number is a pick inside a published range; the range and source sit
    /// next to it so a retune stays inside the evidence.
    public struct PlanRules: Sendable {
        /// Fraction of maintenance (TDEE) added (+) or removed (−). Used when
        /// `calorieAdjust` is nil.
        public let calorieAdjustPct: Double
        /// Fixed calories added (+) or removed (−) from maintenance.
        public let calorieAdjust: Int?
        /// Protein per kg of body weight.
        public let proteinGPerKg: Double
        public let fatPctOfCals: Double
        /// Default daily steps, under 60 and 60+ (Paluch, Lancet Public Health 2022:
        /// mortality risk keeps falling to ~8,000–10,000 steps under 60 and
        /// ~6,000–8,000 at 60+).
        public let stepsUnder60: Int
        public let steps60Plus: Int
    }

    /// Per-plan knobs. Edit here to retune a suggestion.
    /// - Calories: maintain = TDEE. Lose = 500 below (500–750/day ≈ 1–2 lb/week;
    ///   the gentle end). Gain = 10% above (Iraki et al., Sports 2019: ~10–20%
    ///   surplus, the low end for anyone past the beginner stage).
    /// - Protein: maintain 1.6 g/kg (ISSN, Jäger JISSN 2017: 1.4–2.0 g/kg builds
    ///   and keeps muscle); gain 1.8 g/kg (Iraki 2019: 1.6–2.2 g/kg in a surplus);
    ///   lose 2.0 g/kg (more protein protects muscle in a deficit; ISSN 2017
    ///   2.3–3.1 g/kg of lean mass ≈ this per kg of body weight for most people).
    /// - Fat: 30% of calories for every plan, inside the 20–35% adult range
    ///   (Institute of Medicine AMDR, used by the Dietary Guidelines).
    /// - Steps: the top of each age band's plateau when losing (extra burn), the
    ///   start of it otherwise.
    public static let rules: [TargetPlan: PlanRules] = [
        .maintain: PlanRules(
            calorieAdjustPct: 0, calorieAdjust: nil,
            proteinGPerKg: 1.6, fatPctOfCals: 0.30,
            stepsUnder60: 8_000, steps60Plus: 6_000
        ),
        .lose: PlanRules(
            calorieAdjustPct: 0, calorieAdjust: -500,
            proteinGPerKg: 2.0, fatPctOfCals: 0.30,
            stepsUnder60: 10_000, steps60Plus: 8_000
        ),
        .gain: PlanRules(
            calorieAdjustPct: 0.10, calorieAdjust: nil,
            proteinGPerKg: 1.8, fatPctOfCals: 0.30,
            stepsUnder60: 8_000, steps60Plus: 6_000
        ),
    ]

    /// No suggestion or custom target goes below this.
    public static let calorieFloor = 1_200

    /// Heart-health micros — fiber floor + sodium / added sugar / saturated fat
    /// caps. ONE set for every profile regardless of goal (saturated-fat grams
    /// still scale with each goal's calories). LIVE — see MacroTargets in Models.swift.
    public enum HeartHealth {
        public static let sodiumMgMax = 1_500
        public static let addedSugarGMax = 25
        public static let saturatedFatPctMax = 0.10
        public static let fiberGMin = 35
    }

    /// Mifflin-St Jeor BMR. Output rounded to int.
    public static func bmr(sex: Sex, weightLb: Double, heightIn: Double, age: Int) -> Int {
        let kg = weightLb * Units.kgPerLb
        let cm = heightIn * Units.cmPerInch
        let base = 10 * kg + 6.25 * cm - 5 * Double(age)
        return Int((sex == .male ? base + 5 : base - 161).rounded())
    }

    public struct ProfileVitals: Sendable {
        public let sex: Sex
        public let weightLb: Double
        public let heightIn: Double
        public let age: Int
        public let activity: ActivityLevel
        public init(sex: Sex, weightLb: Double, heightIn: Double, age: Int, activity: ActivityLevel) {
            self.sex = sex; self.weightLb = weightLb; self.heightIn = heightIn
            self.age = age; self.activity = activity
        }
    }

    public static func tdee(_ v: ProfileVitals) -> Int {
        let b = Double(bmr(sex: v.sex, weightLb: v.weightLb, heightIn: v.heightIn, age: v.age))
        return Int((b * v.activity.multiplier).rounded())
    }

    /// Compute a suggested plan's macro + steps targets from vitals. Idempotent.
    /// `.custom` has no rules of its own; it falls back to maintenance.
    public static func compute(plan: TargetPlan, vitals v: ProfileVitals) -> MacroTargets {
        let r = rules[plan] ?? rules[.maintain]!
        let maintenance = Double(tdee(v))
        let adjust = r.calorieAdjust.map(Double.init) ?? maintenance * r.calorieAdjustPct
        let calories = max(calorieFloor, Int((maintenance + adjust).rounded()))
        let proteinG = Int((v.weightLb * Units.kgPerLb * r.proteinGPerKg).rounded())
        let fatG = Int((Double(calories) * r.fatPctOfCals / 9).rounded())
        let steps = v.age >= 60 ? r.steps60Plus : r.stepsUnder60
        var t = withHeartHealth(MacroTargets(
            calories: calories, proteinG: proteinG,
            carbsG: carbsFilling(calories: calories, proteinG: proteinG, fatG: fatG),
            fatG: fatG, stepsDaily: steps
        ))
        t.plan = rules[plan] == nil ? .maintain : plan
        return t
    }

    /// Legacy entry point: a profile whose stored targets predate `plan` keeps
    /// recomputing under its goal's matching suggestion.
    public static func compute(fitnessGoal: FitnessGoal, vitals v: ProfileVitals) -> MacroTargets {
        compute(plan: fitnessGoal.defaultPlan, vitals: v)
    }

    /// The user's own calories / protein / fat as targets. Carbs fill what's left;
    /// calories respect the floor; heart-health micros are added as for any plan.
    public static func custom(calories: Int, proteinG: Int, fatG: Int, stepsDaily: Int) -> MacroTargets {
        let cals = max(calorieFloor, calories)
        let p = max(0, proteinG), f = max(0, fatG)
        var t = withHeartHealth(MacroTargets(
            calories: cals, proteinG: p,
            carbsG: carbsFilling(calories: cals, proteinG: p, fatG: f),
            fatG: f, stepsDaily: stepsDaily
        ))
        t.plan = .custom
        return t
    }

    /// What `current` targets become after a vitals change: a suggested plan
    /// re-derives from the new vitals; `.custom` keeps the user's calories and
    /// macros (refreshing only the heart-health micros); targets stored before
    /// plans existed follow `fitnessGoal`. Used by `Repos.recomputeTargets` and
    /// the edit-vitals preview so the two can't disagree.
    public static func recompute(_ current: MacroTargets, fitnessGoal: FitnessGoal, vitals v: ProfileVitals) -> MacroTargets {
        switch current.plan {
        case .custom?:
            return custom(calories: current.calories, proteinG: current.proteinG,
                          fatG: current.fatG, stepsDaily: current.stepsDaily)
        case let plan?:
            return compute(plan: plan, vitals: v)
        case nil:
            return compute(fitnessGoal: fitnessGoal, vitals: v)
        }
    }

    /// The soft-tilt goal a set of targets implies: below maintenance tilts toward
    /// weight loss, anything else toward keeping / building muscle.
    public static func fitnessGoal(for t: MacroTargets, tdee: Int) -> FitnessGoal {
        if let g = t.plan?.fitnessGoal { return g }
        return t.calories < tdee ? .lose : .gain
    }

    /// Carbs fill the calories protein and fat leave.
    public static func carbsFilling(calories: Int, proteinG: Int, fatG: Int) -> Int {
        max(0, Int(((Double(calories) - Double(proteinG * 4) - Double(fatG * 9)) / 4).rounded()))
    }

    private static func withHeartHealth(_ base: MacroTargets) -> MacroTargets {
        var t = base
        t.sodiumMgMax = HeartHealth.sodiumMgMax
        t.addedSugarGMax = HeartHealth.addedSugarGMax
        t.fiberGMin = HeartHealth.fiberGMin
        t.saturatedFatGMax = Int((Double(t.calories) * HeartHealth.saturatedFatPctMax / 9).rounded())
        return t
    }
}

public extension ProfileDTO {
    /// Vitals slice consumed by `Targets.compute`. Single source so target math
    /// and the Settings target previews build the same input from a profile.
    var vitals: Targets.ProfileVitals {
        Targets.ProfileVitals(
            sex: sex, weightLb: weightLb, heightIn: heightIn, age: age, activity: activity
        )
    }
}
