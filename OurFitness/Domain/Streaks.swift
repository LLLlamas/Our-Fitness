// Adherence streaks. A day counts if calorie intake ≥ 80% of target.
// Pure.

import Foundation

public enum Streaks {

    private static let adherenceFloor: Double = 0.8

    public static func dailyCalories(_ logs: [FoodLogEntryDTO]) -> [String: Int] {
        var out: [String: Int] = [:]
        for e in logs {
            out[e.date, default: 0] += e.perServing.calories
        }
        return out
    }

    /// Consecutive days ending at `endDate` with cals ≥ floor × target.
    /// Today is grace-zone: if today is short, the streak is preserved
    /// (we count from yesterday backward) — it just doesn't extend yet.
    public static func currentStreak(
        _ logs: [FoodLogEntryDTO],
        calorieTarget: Int,
        endDate: Date = Date()
    ) -> Int {
        guard calorieTarget > 0 else { return 0 }
        let totals = dailyCalories(logs)
        let floor = Double(calorieTarget) * adherenceFloor

        var n = 0
        let cal = Calendar.current
        var cursor = cal.startOfDay(for: endDate)
        let todayKey = Dates.dayKey(endDate)

        while true {
            let key = Dates.dayKey(cursor)
            let cals = totals[key] ?? 0
            if Double(cals) >= floor {
                n += 1
            } else if key == todayKey {
                // grace: today not yet hit — slide to yesterday without breaking
            } else {
                break
            }
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return n
    }

    /// 0…1 — share of last N days at adherence floor.
    public static func adherencePct(
        _ logs: [FoodLogEntryDTO],
        calorieTarget: Int,
        days: Int = 14,
        endDate: Date = Date()
    ) -> Double {
        guard calorieTarget > 0, days > 0 else { return 0 }
        let totals = dailyCalories(logs)
        let floor = Double(calorieTarget) * adherenceFloor
        let window = Dates.lastNDays(days, end: endDate)
        let hits = window.reduce(0) { acc, k in acc + (Double(totals[k] ?? 0) >= floor ? 1 : 0) }
        return Double(hits) / Double(days)
    }

    // MARK: - Logging streak

    /// Number of food-log entries per day-key (any calorie value counts).
    public static func loggedDayCounts(_ logs: [FoodLogEntryDTO]) -> [String: Int] {
        var out: [String: Int] = [:]
        for e in logs { out[e.date, default: 0] += 1 }
        return out
    }

    /// Consecutive days ending at `endDate` on which the user logged at least
    /// `minEntriesPerDay` meals — the "did you log today" habit streak (distinct
    /// from `currentStreak`, which is calorie-adherence). Today is grace-zone: an
    /// unlogged today preserves the streak from yesterday rather than breaking it.
    public static func loggingStreak(
        _ logs: [FoodLogEntryDTO],
        minEntriesPerDay: Int = 1,
        endDate: Date = Date()
    ) -> Int {
        let counts = loggedDayCounts(logs)
        var n = 0
        let cal = Calendar.current
        var cursor = cal.startOfDay(for: endDate)
        let todayKey = Dates.dayKey(endDate)
        while true {
            let key = Dates.dayKey(cursor)
            if (counts[key] ?? 0) >= minEntriesPerDay {
                n += 1
            } else if key == todayKey {
                // grace: today not logged yet — preserve streak from yesterday
            } else {
                break
            }
            if n >= 365 { break }   // runaway guard, capped at one year
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return n
    }
}
