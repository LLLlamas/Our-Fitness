// Today-vs-yesterday read for the Today tab (pure Swift).
//
// Compares the two days the user can still act on and returns a short, ranked
// list of observations, each with one concrete next step. Every number comes
// from what was logged or synced; a day with no data produces no claim about
// that metric (yesterday's 0 steps from an unsynced phone is "no data", not
// "you didn't move").

import Foundation

public enum DayInsights {

    /// What one day looked like. `foodLogged` separates "ate nothing" from
    /// "logged nothing" — only the latter is knowable.
    public struct Day: Sendable, Equatable {
        public var totals: DailyTotals
        public var foodLogged: Bool
        public var steps: Int
        public var waterFlOz: Double
        public var trained: Bool

        public init(totals: DailyTotals = DailyTotals(), foodLogged: Bool = false,
                    steps: Int = 0, waterFlOz: Double = 0, trained: Bool = false) {
            self.totals = totals
            self.foodLogged = foodLogged
            self.steps = steps
            self.waterFlOz = waterFlOz
            self.trained = trained
        }
    }

    public enum Tone: Sendable, Equatable { case win, nudge }

    public struct Insight: Sendable, Equatable, Identifiable {
        public let id: String
        public let symbol: String
        public let title: String
        public let detail: String
        public let tone: Tone
    }

    /// Roughly 100 steps a minute at a moderate walk (Tudor-Locke et al., Br J
    /// Sports Med 2018 — the moderate-intensity cadence threshold).
    static let stepsPerWalkingMinute = 100

    /// Up to `limit` insights, most actionable first.
    public static func compute(
        today: Day,
        yesterday: Day,
        fitnessGoal: FitnessGoal,
        targets: MacroTargets,
        stepsGoal: Int,
        waterGoalFlOz: Double,
        limit: Int = 3
    ) -> [Insight] {
        var out: [Insight] = []

        // Food — only when yesterday has logs; otherwise say that instead.
        if !yesterday.foodLogged {
            out.append(Insight(
                id: "food-unlogged", symbol: "fork.knife",
                title: "Nothing logged yesterday",
                detail: "Fill it in on Meals › Yesterday so your weekly averages stay accurate.",
                tone: .nudge))
        } else {
            if let cal = calorieInsight(today: today, yesterday: yesterday,
                                        fitnessGoal: fitnessGoal, target: targets.calories) {
                out.append(cal)
            }
            if let protein = proteinInsight(today: today, yesterday: yesterday, target: targets.proteinG) {
                out.append(protein)
            }
        }

        if let steps = stepsInsight(today: today, yesterday: yesterday, goal: stepsGoal) {
            out.append(steps)
        }
        if let water = waterInsight(yesterday: yesterday, goal: waterGoalFlOz) {
            out.append(water)
        }
        if yesterday.trained && !today.trained {
            out.append(Insight(
                id: "train-recover", symbol: "figure.cooldown",
                title: "You trained yesterday",
                detail: "Today suits a different muscle group, a walk or stretching.",
                tone: .win))
        }

        return Array(out.prefix(limit))
    }

    // MARK: - Rules

    static func calorieInsight(today: Day, yesterday: Day,
                               fitnessGoal: FitnessGoal, target: Int) -> Insight? {
        guard target > 0 else { return nil }
        let y = yesterday.totals.calories
        let left = target - today.totals.calories
        switch fitnessGoal {
        case .lose:
            // >10% over.
            guard y * 10 > target * 11 else { return nil }
            let detail = left > 0
                ? "One day doesn't set the trend. \(left) cal left today — aim to land on target."
                : "One day doesn't set the trend. You're at today's target — lighter choices from here."
            return Insight(id: "cal-over", symbol: "chart.line.uptrend.xyaxis",
                           title: "Yesterday ran \(y - target) cal over target",
                           detail: detail, tone: .nudge)
        case .gain:
            // >15% under.
            guard y * 100 < target * 85 else { return nil }
            let detail = left > 0
                ? "Building muscle needs the surplus — add a snack today. \(left) cal to go."
                : "You're already at today's target — nice recovery."
            return Insight(id: "cal-under", symbol: "chart.line.downtrend.xyaxis",
                           title: "Yesterday came in \(target - y) cal under target",
                           detail: detail, tone: .nudge)
        }
    }

    static func proteinInsight(today: Day, yesterday: Day, target: Int) -> Insight? {
        guard target > 0 else { return nil }
        let y = yesterday.totals.proteinG
        let left = target - today.totals.proteinG
        // Under 80% yesterday.
        if y * 10 < target * 8 {
            let detail = left > 0
                ? "\(y) of \(target) g. Build your next meal around protein — \(left) g to go today."
                : "\(y) of \(target) g yesterday, and today's target is already met."
            return Insight(id: "protein-short", symbol: "fish",
                           title: "Protein was short yesterday", detail: detail, tone: .nudge)
        }
        if y >= target, left > 0 {
            return Insight(id: "protein-hit", symbol: "checkmark.seal.fill",
                           title: "Protein target hit yesterday",
                           detail: "Make it two in a row — \(left) g to go today.", tone: .win)
        }
        return nil
    }

    static func stepsInsight(today: Day, yesterday: Day, goal: Int) -> Insight? {
        guard goal > 0, yesterday.steps > 0, today.steps < goal else { return nil }
        let toGo = goal - today.steps
        if yesterday.steps >= goal {
            return Insight(id: "steps-hit", symbol: "figure.walk",
                           title: "Step goal hit yesterday",
                           detail: "\(toGo.formatted()) to go to make it two days running.",
                           tone: .win)
        }
        let minutes = max(5, Int((Double(toGo) / Double(stepsPerWalkingMinute) / 5).rounded(.up)) * 5)
        return Insight(id: "steps-short", symbol: "figure.walk",
                       title: "Yesterday: \(yesterday.steps.formatted()) steps, \((goal - yesterday.steps).formatted()) short",
                       detail: "\(toGo.formatted()) to go today — about a \(minutes)-minute walk.",
                       tone: .nudge)
    }

    static func waterInsight(yesterday: Day, goal: Double) -> Insight? {
        // A 0 is far more likely "didn't log" than "drank nothing" — no claim.
        guard goal > 0, yesterday.waterFlOz > 0, yesterday.waterFlOz < goal * 0.75 else { return nil }
        let pct = Int((yesterday.waterFlOz / goal * 100).rounded())
        return Insight(id: "water-short", symbol: "drop.fill",
                       title: "Water reached \(pct)% of goal yesterday",
                       detail: "Front-load a glass now — the drop button repeats your last pour.",
                       tone: .nudge)
    }
}
