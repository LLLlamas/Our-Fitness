// Mifflin-St Jeor BMR + activity multiplier + goal-specific adjustments.
// Pure. Tested.

import Foundation

public enum Targets {

    /// The knobs a fitness goal is allowed to change. Everything else about the
    /// targets — including the heart-health micros below — is the same for everyone.
    public struct GoalRules: Sendable {
        public let calorieAdjust: Int
        public let proteinPerLb: Double
        public let fatPctOfCals: Double
        public let stepsDaily: Int
    }

    /// Per-goal knobs. Edit here to retune either goal.
    public static let rules: [FitnessGoal: GoalRules] = [
        .gain: GoalRules(
            calorieAdjust: 500,
            proteinPerLb: 1.0,
            fatPctOfCals: 0.27,
            stepsDaily: 8_000
        ),
        .lose: GoalRules(
            calorieAdjust: -400,
            proteinPerLb: 1.1,
            fatPctOfCals: 0.28,
            stepsDaily: 10_000
        ),
    ]

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

    /// Compute macro + steps targets from profile. Idempotent.
    public static func compute(fitnessGoal: FitnessGoal, vitals v: ProfileVitals) -> MacroTargets {
        // Exhaustive switch keeps this compile-time safe when new goal cases are added.
        let r: GoalRules
        switch fitnessGoal {
        case .gain: r = rules[.gain]!
        case .lose: r = rules[.lose]!
        }
        let calories = max(1200, tdee(v) + r.calorieAdjust)
        let proteinG = Int((v.weightLb * r.proteinPerLb).rounded())
        let fatG = Int((Double(calories) * r.fatPctOfCals / 9).rounded())
        let carbsG = max(0, Int(((Double(calories) - Double(proteinG * 4) - Double(fatG * 9)) / 4).rounded()))

        var t = MacroTargets(
            calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG,
            stepsDaily: r.stepsDaily
        )
        t.sodiumMgMax = HeartHealth.sodiumMgMax
        t.addedSugarGMax = HeartHealth.addedSugarGMax
        t.fiberGMin = HeartHealth.fiberGMin
        t.saturatedFatGMax = Int((Double(calories) * HeartHealth.saturatedFatPctMax / 9).rounded())
        return t
    }
}

public extension ProfileDTO {
    /// Vitals slice consumed by `Targets.compute`. Single source so target math
    /// and the goal-switch preview build the same input from a profile.
    var vitals: Targets.ProfileVitals {
        Targets.ProfileVitals(
            sex: sex, weightLb: weightLb, heightIn: heightIn, age: age, activity: activity
        )
    }
}
