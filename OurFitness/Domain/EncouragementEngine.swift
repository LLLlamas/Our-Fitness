// Encouragement system — message engine (Phase 1).
//
// Pure copy + lightweight math. Given a milestone or a logged event, returns a
// render-ready EncouragementMessage (or nil when nothing meaningful happened, so
// the view layer never spams the user).
//
// One set of messages for everyone. The user's goal only swaps the framing where
// the content genuinely differs: a calorie surplus vs a deficit, and how much
// weight protein carries (muscle growth when gaining, muscle protection when
// losing). Calorie figures are derived from CalorieEstimator — never hardcoded.
//
// Copy rule: spell out acronyms in every user-facing string — "blood pressure"
// not "BP", "muscle protein synthesis" not "MPS", "minimum effective volume" not
// "MEV", "cal" not "kcal".
//
// Rule: never import SwiftData or SwiftUI from this file. Pure Swift only.

import Foundation

public enum EncouragementEngine {

    // MARK: - Steps

    /// Message for a crossed step milestone (3,000 / 5,000 / 8,000 / 10,000).
    /// Neutral wording: step goals differ per user, so no milestone may claim the
    /// day's goal is complete — the goal ring says that.
    public static func stepMilestoneMessage(steps: Int) -> EncouragementMessage {
        switch steps {
        case 3_000:
            return EncouragementMessage(
                headline: "3k steps.",
                detail: "Every thousand steps counts. Studies show each additional thousand steps reduces mortality risk by roughly 12%.",
                scienceLine: "Saint-Maurice et al., JAMA 2020.",
                tone: .celebrate, sfSymbol: "figure.walk")
        case 5_000:
            return EncouragementMessage(
                headline: "5k steps.",
                detail: "5k steps already improves insulin sensitivity. A 10-minute walk after dinner drops blood glucose by about 23 mg/dL.",
                scienceLine: "Stair walking study, ScienceDirect 2021.",
                tone: .celebrate, sfSymbol: "figure.walk")
        case 8_000:
            return EncouragementMessage(
                headline: "8k steps. That's the research sweet spot.",
                detail: "People who consistently hit 8,000 steps show 51% lower all-cause mortality than those at 4,000. You're in that bracket.",
                scienceLine: "Saint-Maurice et al., JAMA 2020.",
                tone: .impressed, sfSymbol: "flame.fill")
        case 10_000:
            return EncouragementMessage(
                headline: "10,000 steps.",
                detail: "Consistent daily walking like this reduces blood pressure, improves blood sugar control, and cuts cardiovascular risk.",
                scienceLine: "Paluch et al. meta-analysis, Lancet Public Health 2022.",
                tone: .celebrate, sfSymbol: "figure.walk")
        default:
            // Not a defined milestone — fall back to a neutral celebrate beat.
            let kLabel = steps >= 1_000 ? "\(steps / 1_000)k steps." : "\(steps) steps."
            return EncouragementMessage(
                headline: kLabel,
                detail: "Keep moving — momentum compounds.",
                tone: .celebrate, sfSymbol: "figure.walk")
        }
    }

    // MARK: - Workout volume

    /// Volume-milestone copy after logging a set. Returns nil at non-milestone
    /// counts so the view layer never spams the user.
    /// `totalSetsThisWeekForMuscle` is the count of sets logged this week for the
    /// exercise's primary muscle group.
    public static func workoutSetMessage(
        exercise: ExerciseDTO,
        repsJustLogged: Int,
        totalSetsThisWeekForMuscle: Int
    ) -> EncouragementMessage? {
        let muscle = exercise.muscleGroups.first ?? "this muscle group"
        switch totalSetsThisWeekForMuscle {
        case 4:
            return EncouragementMessage(
                headline: "Growth signal on.",
                detail: "4 sets this week for \(muscle) — that's the minimum effective volume for muscle growth. The adaptation signal is live.",
                scienceLine: "RP Strength; Schoenfeld, J Strength Cond Res, 2010.",
                tone: .scienceTip, sfSymbol: "bolt.fill")
        case 6:
            return EncouragementMessage(
                headline: "6 sets this week.",
                detail: "\(muscle) is getting solid stimulus. Research shows visible muscle changes start appearing after 8–12 weeks of consistent volume like this.",
                scienceLine: "Schoenfeld BJ et al., J Strength Cond Res, 2017 (dose–response meta-analysis).",
                tone: .scienceTip, sfSymbol: "bolt.fill")
        case 10:
            return EncouragementMessage(
                headline: "10 sets this week.",
                detail: "You're deep in the hypertrophy sweet spot for \(muscle). This is the volume range where most muscle growth happens.",
                scienceLine: "RP Strength: 10–20 sets/muscle/week = maximum adaptive volume.",
                tone: .celebrate, sfSymbol: "flame.fill")
        case 12:
            return EncouragementMessage(
                headline: "12 sets. Elite volume.",
                detail: "That's upper-range hypertrophy volume for \(muscle). Keep quality high — each set at this frequency compounds.",
                tone: .impressed, sfSymbol: "flame.fill")
        default:
            return nil
        }
    }

    // MARK: - Projections

    /// Inline projection shown below an exercise card after a set. Returns
    /// nil for trivial estimates so the strip stays meaningful.
    public static func repProjection(
        exercise: ExerciseDTO,
        repsLogged: Int,
        totalCaloriesToday: Double,
        bodyWeightLb: Double
    ) -> String? {
        let calsBurned = CalorieEstimator.caloriesForReps(
            reps: repsLogged, exercise: exercise, bodyWeightLb: bodyWeightLb
        )
        guard calsBurned > 1.0 else { return nil }
        return "~\(Int(calsBurned)) cal this set · \(Int(totalCaloriesToday + calsBurned)) cal total today"
    }

    /// Projection shown below the step card. Returns nil once the goal is reached.
    public static func stepProjection(
        stepsToday: Int,
        goalSteps: Int,
        bodyWeightLb: Double
    ) -> String? {
        let stepsRemaining = max(0, goalSteps - stepsToday)
        guard stepsRemaining > 0 else { return nil }
        let calsBurned = CalorieEstimator.caloriesForSteps(steps: stepsToday, bodyWeightLb: bodyWeightLb)
        let calsAtGoal = CalorieEstimator.caloriesForSteps(steps: goalSteps, bodyWeightLb: bodyWeightLb)
        let calsRemaining = max(0, calsAtGoal - calsBurned)
        return "\(stepsRemaining) more steps · ~\(Int(calsRemaining)) cal to goal"
    }

    // MARK: - Meal-logging streak

    /// Meal-logging streak milestone copy (3 / 7 / 14 / 30 / 60 / 100 days).
    /// Returns nil at any other day count so the toast layer never spams. This is
    /// the "you logged today, N days running" habit reward. Only the 3-day copy
    /// varies by goal (surplus vs deficit).
    public static func mealStreakMessage(days: Int, fitnessGoal: FitnessGoal) -> EncouragementMessage? {
        let isGaining = fitnessGoal == .gain
        switch days {
        case 3:
            return EncouragementMessage(
                headline: "3-day logging streak.",
                detail: isGaining
                    ? "Three days of tracking. Knowing what you eat is the first lever on hitting your protein and your surplus."
                    : "Three days of tracking. Seeing what you eat is the first step to a steady, sustainable deficit.",
                tone: .celebrate, sfSymbol: "flame.fill")
        case 7:
            return EncouragementMessage(
                headline: "One week of logging.",
                detail: "Seven days straight. People who track consistently are far more likely to reach their goal — and you've cleared the habit's hardest week.",
                scienceLine: "Self-monitoring is one of the strongest predictors of weight outcomes (Burke et al., J Acad Nutr Diet 2011).",
                tone: .impressed, sfSymbol: "flame.fill")
        case 14:
            return EncouragementMessage(
                headline: "Two weeks logged.",
                detail: "Two full weeks without a gap. Your log is now rich enough to spot patterns and fine-tune your targets.",
                tone: .impressed, sfSymbol: "flame.fill")
        case 30:
            return EncouragementMessage(
                headline: "30-day logging streak.",
                detail: "A full month of tracking. This is the consistency that turns a goal into a result.",
                tone: .impressed, sfSymbol: "star.fill")
        case 60:
            return EncouragementMessage(
                headline: "60 days logged.",
                detail: "Two months of unbroken tracking. That's elite consistency — the data and the habit are both working for you now.",
                tone: .impressed, sfSymbol: "star.fill")
        case 100:
            return EncouragementMessage(
                headline: "100-day logging streak.",
                detail: "One hundred days. Tracking isn't a chore anymore — it's just part of who you are.",
                tone: .impressed, sfSymbol: "star.fill")
        default:
            return nil
        }
    }

    // MARK: - Macros

    /// Copy for hitting a macro target (100% of goal).
    public static func macroGoalHitMessage(macro: String, fitnessGoal: FitnessGoal) -> EncouragementMessage {
        let isGaining = fitnessGoal == .gain
        switch macro.lowercased() {
        case "protein":
            return isGaining
                ? EncouragementMessage(
                    headline: "Protein goal hit.",
                    detail: "Every gram above your target has diminishing returns for muscle protein synthesis. Quality of remaining meals matters more than quantity now.",
                    scienceLine: "Leucine threshold for muscle protein synthesis: ~2.5–3g per meal.",
                    tone: .celebrate, sfSymbol: "checkmark.circle.fill")
                : EncouragementMessage(
                    headline: "Protein goal hit.",
                    detail: "Protein target locked in. High protein in a calorie deficit protects muscle while you lose body fat.",
                    tone: .celebrate, sfSymbol: "checkmark.circle.fill")
        case "calories":
            return isGaining
                ? EncouragementMessage(
                    headline: "Calorie goal hit.",
                    detail: "Calorie surplus secured. You've given your body the fuel to build — pair it with sleep and the work pays off.",
                    tone: .celebrate, sfSymbol: "flame.fill")
                : EncouragementMessage(
                    headline: "Calorie goal hit.",
                    detail: "Right on target. A steady, moderate calorie deficit protects muscle while reducing body fat.",
                    tone: .celebrate, sfSymbol: "checkmark.circle.fill")
        default:
            return EncouragementMessage(
                headline: "\(macro.capitalized) goal hit.",
                detail: "On track for the day.",
                tone: .celebrate, sfSymbol: "checkmark")
        }
    }

    // MARK: - Time-based nudges

    /// Gentle meal-logging nudge based on time of day and how many meals have
    /// been logged. Returns nil when no nudge is warranted — avoid calling
    /// repeatedly without checking the return value.
    ///
    /// Rules:
    /// - Returns nil if mealsLoggedToday > 1 (already on track; 1-meal case gets
    ///   a mid-day tip but not an evening one)
    /// - Returns nil before 11 AM (let people ease into the day)
    /// - The goal shapes focus: gaining → protein, losing → calories + protein
    public static func mealLoggingNudge(
        mealsLoggedToday: Int,
        hourOfDay: Int,
        fitnessGoal: FitnessGoal
    ) -> EncouragementMessage? {
        let isGaining = fitnessGoal == .gain

        // Don't nag before 11 AM.
        guard hourOfDay >= 11 else { return nil }

        if mealsLoggedToday == 0 {
            if hourOfDay >= 17 {
                // Late in the day, still nothing logged.
                return isGaining
                    ? EncouragementMessage(
                        headline: "Day almost done — no meals logged.",
                        detail: "Logging helps you hit your protein target. Even a quick entry keeps the data honest.",
                        tone: .nudge, sfSymbol: "fork.knife")
                    : EncouragementMessage(
                        headline: "Day almost done — no meals logged.",
                        detail: "Seeing what you eat is what keeps a steady deficit on track. A quick log — even an estimate — counts.",
                        tone: .nudge, sfSymbol: "fork.knife")
            } else if hourOfDay >= 11 {
                // Mid-day, nothing logged yet.
                return isGaining
                    ? EncouragementMessage(
                        headline: "Haven't logged yet today.",
                        detail: "Protein timing matters for muscle growth — logging meals keeps you on track to hit your daily target.",
                        tone: .nudge, sfSymbol: "fork.knife")
                    : EncouragementMessage(
                        headline: "Haven't logged yet today.",
                        detail: "Logging even one meal helps you see where you stand on calories and protein for the day.",
                        tone: .nudge, sfSymbol: "fork.knife")
            }
        } else if mealsLoggedToday == 1, hourOfDay >= 11, hourOfDay <= 13 {
            // One meal logged around midday — light encouragement to keep going.
            return isGaining
                ? EncouragementMessage(
                    headline: "Good start — keep logging.",
                    detail: "One meal in. Keep tracking to make sure your protein target is reachable by end of day.",
                    tone: .nudge, sfSymbol: "fork.knife")
                : EncouragementMessage(
                    headline: "Good start — keep logging.",
                    detail: "One meal tracked. Logging the rest of the day helps you balance calories and hit your nutrition goal.",
                    tone: .nudge, sfSymbol: "fork.knife")
        }

        return nil
    }

    /// Hydration nudge based on time of day and progress toward the water goal.
    /// Returns nil when no nudge is warranted.
    ///
    /// Rules:
    /// - Returns nil if currentOz >= goalOz * 0.5 (half the goal met — no nag needed)
    /// - Returns nil outside 10 AM – 8 PM (quiet hours)
    public static func waterNudge(
        currentOz: Double,
        goalOz: Double,
        hourOfDay: Int
    ) -> EncouragementMessage? {
        // Quiet hours.
        guard hourOfDay >= 10, hourOfDay <= 20 else { return nil }
        // Already past half the goal — no nudge needed.
        guard goalOz > 0, currentOz < goalOz * 0.5 else { return nil }

        let pct = goalOz > 0 ? Int((currentOz / goalOz) * 100) : 0
        let remaining = Int(goalOz - currentOz)

        if hourOfDay >= 12, hourOfDay <= 14, pct < 25 {
            // Midday and less than a quarter done.
            return EncouragementMessage(
                headline: "Hydration check.",
                detail: "You're at \(pct)% of your water goal. Staying hydrated supports joint lubrication, metabolic function, and sustained energy — research suggests mild dehydration can dull both physical performance and mood.",
                scienceLine: "ACSM hydration guidelines; Popkin et al., Nutr Rev 2010.",
                tone: .nudge, sfSymbol: "drop.fill")
        } else if hourOfDay >= 16, hourOfDay <= 18 {
            // Afternoon catch-up window — still under 50% (already gated above).
            return EncouragementMessage(
                headline: "Catch up on water.",
                detail: "\(remaining) oz to go. Afternoon is a good window to catch up — hydration supports your metabolism and helps your body use the nutrients from today's meals.",
                scienceLine: "ACSM hydration guidelines; Popkin et al., Nutr Rev 2010.",
                tone: .nudge, sfSymbol: "drop.fill")
        }

        return nil
    }

    /// Copy for approaching a macro target. Intended for use when ≥85% there.
    public static func macroApproachingMessage(macro: String, remaining: Int, unit: String, fitnessGoal: FitnessGoal) -> EncouragementMessage {
        let isGaining = fitnessGoal == .gain
        switch macro.lowercased() {
        case "protein":
            return isGaining
                ? EncouragementMessage(
                    headline: "\(remaining)g protein left.",
                    detail: "Close to your protein goal. A Greek yogurt adds ~17g, a chicken breast ~53g — small choices that lock in the muscle-building signal.",
                    tone: .approaching, sfSymbol: "figure.walk")
                : EncouragementMessage(
                    headline: "\(remaining)g protein left.",
                    detail: "\(remaining) grams to hit your protein target for the day. Protein keeps you full and preserves muscle during your calorie deficit.",
                    tone: .approaching, sfSymbol: "figure.walk")
        case "calories":
            return isGaining
                ? EncouragementMessage(
                    headline: "\(remaining) cal to your surplus.",
                    detail: "Don't leave your target on the table — muscle growth requires the calorie surplus.",
                    tone: .approaching, sfSymbol: "flame")
                : EncouragementMessage(
                    headline: "\(remaining) cal to your target.",
                    detail: "Almost at your calorie goal for the day.",
                    tone: .approaching, sfSymbol: "flame")
        default:
            return EncouragementMessage(
                headline: "\(remaining)\(unit) to \(macro) goal.",
                detail: "Almost there.",
                tone: .approaching, sfSymbol: "checkmark")
        }
    }

    // MARK: - Stall nudges (copy for `StallDetector.Stall`)

    /// A gentle, science-anchored prompt when the user has stalled. Softened claims
    /// only — this never prescribes. Pairs with `StallDetector.detect`.
    public static func stallMessage(_ stall: StallDetector.Stall, fitnessGoal: FitnessGoal) -> EncouragementMessage {
        switch stall {
        case .stepsGap(let days):
            return EncouragementMessage(
                headline: "\(days) days light on steps",
                detail: fitnessGoal == .lose
                    ? "Walking is your most repeatable lever for blood pressure and blood sugar. A short walk today restarts the habit."
                    : "A daily walk keeps recovery and appetite steady without cutting into your training. Even 10 minutes counts.",
                scienceLine: "Each extra ~1,000 daily steps is linked to roughly 10–12% lower early-death risk (Paluch meta-analysis, 2022).",
                tone: .nudge, sfSymbol: "figure.walk")
        case .workoutGap(let days):
            return EncouragementMessage(
                headline: "\(days) days since your last set",
                detail: fitnessGoal == .lose
                    ? "A couple of short strength sessions a week protect muscle while you lean out. A quick one now keeps the habit alive."
                    : "Muscle responds to frequency — a short session now keeps your progress compounding.",
                tone: .nudge, sfSymbol: "dumbbell")
        case .pilatesGap(let days):
            return EncouragementMessage(
                headline: "\(days) days since Pilates",
                detail: "Core and mobility work keeps the daily movements feeling easy. Even 10 minutes counts.",
                tone: .nudge, sfSymbol: "figure.pilates")
        case .weightStall(let weeks):
            return EncouragementMessage(
                headline: "Weight's been flat ~\(weeks)w",
                detail: "Plateaus are normal. Nudging steps or cardio up a little — or tightening sodium — usually gets it moving again.",
                scienceLine: "Adding daily walking reliably restarts a plateau and lowers systolic blood pressure a few points.",
                tone: .nudge, sfSymbol: "scalemass")
        case .markerStall(let kind, let weeks):
            return EncouragementMessage(
                headline: "\(markerPlainName(kind)) hasn't moved in ~\(weeks)w",
                detail: "Pair daily steps with the food tips and re-test in a few weeks — these numbers respond slowly, but they do respond.",
                tone: .nudge, sfSymbol: "heart.text.square")
        }
    }

    /// Plain-English marker name for copy (no acronyms left bare).
    private static func markerPlainName(_ kind: HealthMarkerKind) -> String {
        switch kind {
        case .bpSystolic, .bpDiastolic: return "Blood pressure"
        case .ldl:                      return "LDL cholesterol"
        case .hdl:                      return "HDL cholesterol"
        case .triglycerides:            return "Triglycerides"
        case .totalCholesterol:         return "Cholesterol"
        case .a1c:                      return "A1c"
        case .fastingGlucose:           return "Fasting glucose"
        case .restingHR:                return "Resting heart rate"
        }
    }
}
