// Mifflin-St Jeor BMR + activity multiplier + mode-specific adjustments.
// Pure. Tested.

import Foundation

public enum Targets {

    private static let lbToKg = 0.45359237
    private static let inToCm = 2.54

    public struct ModeRules: Sendable {
        public let calorieAdjust: Int
        public let proteinPerLb: Double
        public let fatPctOfCals: Double
        public let stepsDaily: Int
        // Legacy caps (formerly Reset-only). Math retained; UI does not render.
        public let sodiumMgMax: Int?
        public let addedSugarGMax: Int?
        public let saturatedFatPctMax: Double?
        public let fiberGMin: Int?
    }

    /// Per-mode knobs. Edit here to retune either mode's personality.
    public static let rules: [Mode: ModeRules] = [
        .build: ModeRules(
            calorieAdjust: 500,
            proteinPerLb: 1.0,
            fatPctOfCals: 0.27,
            stepsDaily: 8_000,
            sodiumMgMax: nil,
            addedSugarGMax: nil,
            saturatedFatPctMax: nil,
            fiberGMin: nil
        ),
        .circuit: ModeRules(
            calorieAdjust: -400,
            proteinPerLb: 1.1,
            fatPctOfCals: 0.28,
            stepsDaily: 10_000,
            sodiumMgMax: 1_500,
            addedSugarGMax: 25,
            saturatedFatPctMax: 0.10,
            fiberGMin: 35
        ),
    ]

    /// Mifflin-St Jeor BMR. Output rounded to int.
    public static func bmr(sex: Sex, weightLb: Double, heightIn: Double, age: Int) -> Int {
        let kg = weightLb * lbToKg
        let cm = heightIn * inToCm
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
    public static func compute(mode: Mode, vitals v: ProfileVitals) -> MacroTargets {
        // Exhaustive switch keeps this compile-time safe when new Mode cases are added.
        let r: ModeRules
        switch mode {
        case .build:   r = rules[.build]!
        case .circuit: r = rules[.circuit]!
        }
        let calories = max(1200, tdee(v) + r.calorieAdjust)
        let proteinG = Int((v.weightLb * r.proteinPerLb).rounded())
        let fatG = Int((Double(calories) * r.fatPctOfCals / 9).rounded())
        let carbsG = max(0, Int(((Double(calories) - Double(proteinG * 4) - Double(fatG * 9)) / 4).rounded()))

        var t = MacroTargets(
            calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG,
            stepsDaily: r.stepsDaily
        )
        if mode == .circuit {
            t.sodiumMgMax = r.sodiumMgMax
            t.addedSugarGMax = r.addedSugarGMax
            t.fiberGMin = r.fiberGMin
            if let pct = r.saturatedFatPctMax {
                t.saturatedFatGMax = Int((Double(calories) * pct / 9).rounded())
            }
        }
        return t
    }

    // MARK: - Auto-adjust signals

    public enum AdjustmentDirection: String, Sendable {
        case increase, decrease, addCardio, flagDoctor
    }

    public struct TrendAdjustment: Equatable, Sendable {
        public let direction: AdjustmentDirection
        public let amountCal: Int?
        public let reason: String
        public init(direction: AdjustmentDirection, amountCal: Int? = nil, reason: String) {
            self.direction = direction
            self.amountCal = amountCal
            self.reason = reason
        }
    }

    /// Mode-aware suggested adjustment after 14-day weight trend. nil if on track.
    public static func suggestAdjustment(
        mode: Mode,
        weeklyDeltaLb: Double,
        weeksStalledMarkers: Int = 0
    ) -> TrendAdjustment? {
        switch mode {
        case .build:
            if weeklyDeltaLb < 0.15 {
                return TrendAdjustment(direction: .increase, amountCal: 200,
                                       reason: "Weight trending flat — bump calories.")
            }
            if weeklyDeltaLb > 0.75 {
                return TrendAdjustment(direction: .decrease, amountCal: 150,
                                       reason: "Gaining too fast — drop a multiplier.")
            }
            return nil

        case .circuit:
            if weeksStalledMarkers >= 8 {
                return TrendAdjustment(direction: .flagDoctor,
                                       reason: "Markers unchanged for 8 weeks — review with your doctor.")
            }
            if weeklyDeltaLb > -0.15 {
                return TrendAdjustment(direction: .addCardio,
                                       reason: "Weight stalled — add a zone-2 session or trim 150 cal.")
            }
            if weeklyDeltaLb < -1.5 {
                return TrendAdjustment(direction: .increase, amountCal: 150,
                                       reason: "Losing too fast — protect muscle, add calories.")
            }
            return nil
        }
    }
}

public extension ProfileDTO {
    /// Vitals slice consumed by `Targets.compute`. Single source so target math
    /// and the mode-switch preview build the same input from a profile.
    var vitals: Targets.ProfileVitals {
        Targets.ProfileVitals(
            sex: sex, weightLb: weightLb, heightIn: heightIn, age: age, activity: activity
        )
    }
}
