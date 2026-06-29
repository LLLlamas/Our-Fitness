// Encouragement system — message engine (Phase 1).
//
// Pure copy + lightweight math. Given a milestone or a logged event, returns a
// render-ready EncouragementMessage (or nil when nothing meaningful happened, so
// the view layer never spams the user).
//
// Mode shapes the framing: Build leans hypertrophy (muscle growth, strength,
// surplus); Circuit leans cardiometabolic (blood pressure, steps, pilates,
// markers). Calorie figures are derived from CalorieEstimator — never hardcoded.
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
    public static func stepMilestoneMessage(steps: Int, mode: Mode) -> EncouragementMessage {
        let isBuild = mode == .build
        switch steps {
        case 3_000:
            return isBuild
                ? EncouragementMessage(
                    headline: "3k steps.",
                    detail: "Baseline movement. Your muscles are getting blood flow even when you're not in the gym.",
                    tone: .celebrate, sfSymbol: "figure.walk")
                : EncouragementMessage(
                    headline: "3k steps.",
                    detail: "Every thousand steps counts. Studies show each additional thousand steps reduces mortality risk by roughly 12%.",
                    scienceLine: "Saint-Maurice et al., JAMA 2020.",
                    tone: .celebrate, sfSymbol: "figure.walk")
        case 5_000:
            return isBuild
                ? EncouragementMessage(
                    headline: "Halfway there.",
                    detail: "5k steps done. Active recovery keeps muscles primed for tomorrow's training session.",
                    tone: .celebrate, sfSymbol: "figure.walk")
                : EncouragementMessage(
                    headline: "Halfway to your daily goal.",
                    detail: "5k steps already improves insulin sensitivity. A 10-minute walk after dinner drops blood glucose by about 23 mg/dL.",
                    scienceLine: "Stair walking study, ScienceDirect 2021.",
                    tone: .celebrate, sfSymbol: "figure.walk")
        case 8_000:
            return isBuild
                ? EncouragementMessage(
                    headline: "8k. Strong day.",
                    detail: "Beyond active recovery — you're burning real calories on top of training. Keep it up.",
                    tone: .celebrate, sfSymbol: "figure.walk")
                : EncouragementMessage(
                    headline: "8k steps. That's the research sweet spot.",
                    detail: "People who consistently hit 8,000 steps show 51% lower all-cause mortality than those at 4,000. You're in that bracket.",
                    scienceLine: "Saint-Maurice et al., JAMA 2020.",
                    tone: .impressed, sfSymbol: "flame.fill")
        case 10_000:
            return isBuild
                ? EncouragementMessage(
                    headline: "10k done.",
                    detail: "Full step goal. Your cardiovascular system thanks you — this is on top of the gym work.",
                    tone: .celebrate, sfSymbol: "checkmark.circle.fill")
                : EncouragementMessage(
                    headline: "10,000 steps. Daily goal complete.",
                    detail: "That's your primary cardiometabolic lever, hit. Consistent step goals reduce blood pressure, improve blood sugar control, and cut cardiovascular risk.",
                    scienceLine: "Paluch et al. meta-analysis, Lancet Public Health 2022.",
                    tone: .celebrate, sfSymbol: "checkmark.circle.fill")
        default:
            // Not a defined milestone — fall back to a neutral celebrate beat.
            let kLabel = steps >= 1_000 ? "\(steps / 1_000)k steps." : "\(steps) steps."
            return EncouragementMessage(
                headline: kLabel,
                detail: "Keep moving — momentum compounds.",
                tone: .celebrate, sfSymbol: "figure.walk")
        }
    }

    /// Message for approaching the daily step goal. Intended for use when ≥85% there.
    public static func stepApproachingMessage(stepsRemaining: Int, mode: Mode) -> EncouragementMessage {
        if mode == .build {
            return EncouragementMessage(
                headline: "Almost there on steps.",
                detail: "\(stepsRemaining) steps left to hit your daily goal.",
                tone: .approaching, sfSymbol: "figure.walk")
        }
        return EncouragementMessage(
            headline: "So close.",
            detail: "\(stepsRemaining) more steps and your blood pressure and blood sugar goals for the day are complete.",
            tone: .approaching, sfSymbol: "figure.walk")
    }

    // MARK: - Workout volume (Build)

    /// Volume-milestone copy after logging a set. Returns nil at non-milestone
    /// counts so the view layer never spams the user.
    /// `totalSetsThisWeekForMuscle` is the count of sets logged this week for the
    /// exercise's primary muscle group.
    public static func workoutSetMessage(
        exercise: ExerciseDTO,
        repsJustLogged: Int,
        totalSetsThisWeekForMuscle: Int,
        mode: Mode
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

    /// Inline projection shown below an exercise card after a set (Build). Returns
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

    // MARK: - Pilates (Circuit)

    /// Pilates weekly-goal copy. Returns nil until the goal is met (the first
    /// session alone is not a milestone).
    public static func pilatesSessionMessage(
        totalSessionsThisWeek: Int,
        weeklyGoal: Int,
        mode: Mode
    ) -> EncouragementMessage? {
        if weeklyGoal > 0 && totalSessionsThisWeek >= weeklyGoal {
            return EncouragementMessage(
                headline: "Weekly pilates goal hit.",
                detail: "You've done \(totalSessionsThisWeek) sessions this week. Research shows consistent pilates reduces blood pressure by roughly 4–5 points systolic over 8 weeks.",
                scienceLine: "Journal of Human Hypertension meta-analysis, 2024.",
                tone: .celebrate, sfSymbol: "checkmark.circle.fill")
        }
        return nil
    }

    // MARK: - Streaks

    /// Weekly-streak milestone copy (1 / 5 / 10 / 26 / 52 weeks). Returns nil at
    /// any other week count.
    public static func streakMilestoneMessage(weeks: Int, mode: Mode) -> EncouragementMessage? {
        let isBuild = mode == .build
        switch weeks {
        case 1:
            return isBuild
                ? EncouragementMessage(
                    headline: "One full week.",
                    detail: "Consistency is the whole game. One week of showing up is the hardest week — you've done it.",
                    tone: .celebrate, sfSymbol: "flame.fill")
                : EncouragementMessage(
                    headline: "One full week.",
                    detail: "One week of consistent movement. Small consistent steps compound into real cardiometabolic change.",
                    tone: .celebrate, sfSymbol: "flame.fill")
        case 5:
            return isBuild
                ? EncouragementMessage(
                    headline: "5-week streak.",
                    detail: "At this point neural adaptations are locked in and muscle hypertrophy is well underway. You've crossed the threshold where most people quit.",
                    tone: .celebrate, sfSymbol: "flame.fill")
                : EncouragementMessage(
                    headline: "5-week streak.",
                    detail: "Five weeks of consistent movement. Blood pressure adaptations typically begin at the 4-week mark — you're past it.",
                    scienceLine: "Whelton et al., 2002 meta-analysis.",
                    tone: .celebrate, sfSymbol: "flame.fill")
        case 10:
            return isBuild
                ? EncouragementMessage(
                    headline: "10-week streak.",
                    detail: "Visible muscle changes are measurable at this point. The work is showing up in ways the mirror confirms.",
                    scienceLine: "Hypertrophy timeline research: 8–12 weeks for visible adaptation.",
                    tone: .impressed, sfSymbol: "flame.fill")
                : EncouragementMessage(
                    headline: "10-week streak.",
                    detail: "Ten weeks of consistent movement delivers meaningful reductions in blood pressure, resting heart rate, and blood sugar. That's measurable progress.",
                    tone: .impressed, sfSymbol: "flame.fill")
        case 26:
            return EncouragementMessage(
                headline: "Six months.",
                detail: "Half a year of consistent logging. That kind of commitment compounds into real, lasting physiological change.",
                tone: .impressed, sfSymbol: "star.fill")
        case 52:
            return EncouragementMessage(
                headline: "One year.",
                detail: "A full year. Most people don't make it here. You've built a sustainable habit and the body changes to prove it.",
                tone: .impressed, sfSymbol: "star.fill")
        default:
            return nil
        }
    }

    // MARK: - Meal-logging streak

    /// Meal-logging streak milestone copy (3 / 7 / 14 / 30 / 60 / 100 days).
    /// Returns nil at any other day count so the toast layer never spams. This is
    /// the "you logged today, N days running" habit reward — distinct from the
    /// weekly movement streak (`streakMilestoneMessage`).
    public static func mealStreakMessage(days: Int, mode: Mode) -> EncouragementMessage? {
        let isBuild = mode == .build
        switch days {
        case 3:
            return EncouragementMessage(
                headline: "3-day logging streak.",
                detail: isBuild
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
    public static func macroGoalHitMessage(macro: String, mode: Mode) -> EncouragementMessage {
        let isBuild = mode == .build
        switch macro.lowercased() {
        case "protein":
            return isBuild
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
            return isBuild
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
    /// - Mode shapes focus: Build → protein, Circuit → balanced nutrition
    public static func mealLoggingNudge(
        mealsLoggedToday: Int,
        hourOfDay: Int,
        mode: Mode
    ) -> EncouragementMessage? {
        let isBuild = mode == .build

        // Don't nag before 11 AM.
        guard hourOfDay >= 11 else { return nil }

        if mealsLoggedToday == 0 {
            if hourOfDay >= 17 {
                // Late in the day, still nothing logged.
                return isBuild
                    ? EncouragementMessage(
                        headline: "Day almost done — no meals logged.",
                        detail: "Logging helps you hit your protein target. Even a quick entry keeps the data honest.",
                        tone: .nudge, sfSymbol: "fork.knife")
                    : EncouragementMessage(
                        headline: "Day almost done — no meals logged.",
                        detail: "Balanced nutrition is the foundation of Reset. A quick log — even an estimate — keeps you on track.",
                        tone: .nudge, sfSymbol: "fork.knife")
            } else if hourOfDay >= 11 {
                // Mid-day, nothing logged yet.
                return isBuild
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
            return isBuild
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
    public static func macroApproachingMessage(macro: String, remaining: Int, unit: String, mode: Mode) -> EncouragementMessage {
        let isBuild = mode == .build
        switch macro.lowercased() {
        case "protein":
            return isBuild
                ? EncouragementMessage(
                    headline: "\(remaining)g protein left.",
                    detail: "Close to your protein goal. A Greek yogurt adds ~17g, a chicken breast ~53g — small choices that lock in the muscle-building signal.",
                    tone: .approaching, sfSymbol: "figure.walk")
                : EncouragementMessage(
                    headline: "\(remaining)g protein left.",
                    detail: "\(remaining) grams to hit your protein target for the day. Protein keeps you full and preserves muscle during your calorie deficit.",
                    tone: .approaching, sfSymbol: "figure.walk")
        case "calories":
            return isBuild
                ? EncouragementMessage(
                    headline: "\(remaining) cal to your surplus.",
                    detail: "Don't leave your build target on the table — muscle growth requires the calorie surplus.",
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
}
