// Step-count derived metrics. Pure.
// One row per user per day; treat missing days as 0.

import Foundation

public enum Steps {

    private static func byDate(_ steps: [StepCountDTO]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: steps.map { ($0.date, $0.steps) })
    }

    /// Step count for a specific dayKey, or 0 if missing.
    public static func stepsForDay(_ steps: [StepCountDTO], day: String) -> Int {
        steps.first(where: { $0.date == day })?.steps ?? 0
    }

    /// Average over the last N days (missing days count as 0).
    public static func average(_ steps: [StepCountDTO], days: Int, end: Date = Date()) -> Int {
        guard days > 0 else { return 0 }
        let map = byDate(steps)
        let window = Dates.lastNDays(days, end: end)
        let sum = window.reduce(0) { $0 + (map[$1] ?? 0) }
        return Int((Double(sum) / Double(days)).rounded())
    }

    /// % of the last N days that hit `goal`.
    public static func hitRate(
        _ steps: [StepCountDTO], goal: Int, days: Int = 14, end: Date = Date()
    ) -> Double {
        guard days > 0, goal > 0 else { return 0 }
        let map = byDate(steps)
        let window = Dates.lastNDays(days, end: end)
        let hits = window.reduce(0) { $0 + ((map[$1] ?? 0) >= goal ? 1 : 0) }
        return Double(hits) / Double(days)
    }

    /// Series of {date, value} for plotting. Dense — fills missing days with 0.
    public static func series(_ steps: [StepCountDTO], days: Int, end: Date = Date()) -> [Trends.Point] {
        let map = byDate(steps)
        return Dates.lastNDays(days, end: end).map { Trends.Point(date: $0, value: Double(map[$0] ?? 0)) }
    }
}
