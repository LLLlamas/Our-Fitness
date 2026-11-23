// The Train tab's reps target: how far today's (or this week's) reps are toward
// the user's goal. Pure Swift, unit-tested with a pinned `now`
// (OurFitnessTests/RepTargetTests.swift).
//
// Reps, not sets: every +1 tap on the Train list is saved as its own 1-rep set,
// so a set count would inflate. Reps come from `TrainingHistory` (rep exercises
// only — holds and minutes never count).
//
// The default goal is seeded from the user's OWN last ISO week. With no reps
// last week there is no default (nil) and the card asks the user to set one —
// never an invented number.

import Foundation

public enum RepTarget {

    public enum Period: String, CaseIterable, Sendable {
        case day
        case week
    }

    /// −/+ step on the goal row, and the smallest goal allowed.
    public static func step(for period: Period) -> Int {
        period == .day ? 5 : 25
    }

    /// Upper bound so a held + can't run away; far above any real day or week.
    public static func maxGoal(for period: Period) -> Int {
        period == .day ? 2_000 : 10_000
    }

    /// Reps counted toward the target: today's, or this ISO week's so far.
    public static func reps(
        _ sets: [WorkoutSetDTO],
        exercises: [ExerciseDTO],
        period: Period,
        now: Date = Date()
    ) -> Int {
        switch period {
        case .day:
            return TrainingHistory.repsOnDay(sets, exercises: exercises, dayKey: Dates.dayKey(now))
        case .week:
            return TrainingHistory.repsInWeek(sets, exercises: exercises, weeksAgo: 0, now: now)
        }
    }

    /// Default goal from last ISO week, rounded to the period's step (at least
    /// one step). Week = last week's reps. Day = last week's reps per day
    /// actually trained (rest days don't drag a training-day goal down).
    /// nil when last week had no reps.
    public static func suggestedGoal(
        _ sets: [WorkoutSetDTO],
        exercises: [ExerciseDTO],
        period: Period,
        now: Date = Date()
    ) -> Int? {
        let lastWeek = TrainingHistory.repsInWeek(sets, exercises: exercises, weeksAgo: 1, now: now)
        guard lastWeek > 0 else { return nil }
        switch period {
        case .week:
            return rounded(lastWeek, period: .week)
        case .day:
            let monday = Dates.startOfISOWeek(now, weeksAgo: 1)
            let trainedDays = (0..<7).filter { offset in
                guard let d = Dates.isoCalendar.date(byAdding: .day, value: offset, to: monday)
                else { return false }
                return TrainingHistory.repsOnDay(sets, exercises: exercises, dayKey: Dates.dayKey(d)) > 0
            }.count
            guard trainedDays > 0 else { return nil }
            let perDay = Double(lastWeek) / Double(trainedDays)
            return rounded(Int(perDay.rounded()), period: .day)
        }
    }

    /// Stored goal wins (0 = never set); else last week's; else nil ("set a goal").
    public static func resolve(stored: Int, suggested: Int?) -> Int? {
        stored > 0 ? stored : suggested
    }

    /// One −/+ tap. From "no goal" the first + starts at one step; − does nothing.
    public static func adjusted(_ goal: Int?, by direction: Int, period: Period) -> Int? {
        let s = step(for: period)
        guard let goal else { return direction > 0 ? s : nil }
        return min(maxGoal(for: period), max(s, goal + direction * s))
    }

    /// Ring fill, 0...1. nil goal = empty ring.
    public static func fraction(reps: Int, goal: Int?) -> Double {
        guard let goal, goal > 0 else { return 0 }
        return min(1, Double(max(0, reps)) / Double(goal))
    }

    static func rounded(_ value: Int, period: Period) -> Int {
        let s = step(for: period)
        let r = Int((Double(value) / Double(s)).rounded()) * s
        return min(maxGoal(for: period), max(s, r))
    }
}
