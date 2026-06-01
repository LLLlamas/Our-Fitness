// Weekly+ nutrition aggregation over the (already append-only persisted) food log.
// Pure Domain. Food log entries persist per day via FoodLogEntryModel; these
// helpers roll them up into per-day totals and trend series, mirroring Steps.

import Foundation

public enum NutritionHistory {

    public struct DayTotals: Identifiable, Sendable, Equatable {
        public let id: String        // dayKey, also used as chart x
        public let day: String
        public let totals: DailyTotals
    }

    /// Per-day totals for the last `days`, oldest first (empty days included as zero).
    public static func byDay(_ entries: [FoodLogEntryDTO], days: Int, end: Date = Date()) -> [DayTotals] {
        var grouped: [String: [FoodLogEntryDTO]] = [:]
        for e in entries { grouped[e.date, default: []].append(e) }
        return Dates.lastNDays(days, end: end).map { key in
            DayTotals(id: key, day: key, totals: DailyTotals.totals(from: grouped[key] ?? []))
        }
    }

    /// Daily calorie series for charts / the weekly strip.
    public static func calorieSeries(_ entries: [FoodLogEntryDTO], days: Int, end: Date = Date()) -> [Trends.Point] {
        byDay(entries, days: days, end: end).map { Trends.Point(date: $0.day, value: Double($0.totals.calories)) }
    }

    /// Average across only the days that had at least one entry in the window.
    public static func averagePerLoggedDay(_ entries: [FoodLogEntryDTO], days: Int, end: Date = Date()) -> DailyTotals {
        let rows = byDay(entries, days: days, end: end).map(\.totals).filter { $0.calories > 0 }
        guard !rows.isEmpty else { return .zero }
        let n = rows.count
        // Rounded integer division so small macros (e.g. fiber) don't truncate to 0.
        func mean(_ sum: Int) -> Int { (sum + n / 2) / n }
        var avg = DailyTotals()
        avg.calories      = mean(rows.reduce(0) { $0 + $1.calories })
        avg.proteinG      = mean(rows.reduce(0) { $0 + $1.proteinG })
        avg.carbsG        = mean(rows.reduce(0) { $0 + $1.carbsG })
        avg.fatG          = mean(rows.reduce(0) { $0 + $1.fatG })
        avg.fiberG        = mean(rows.reduce(0) { $0 + $1.fiberG })
        avg.sodiumMg      = mean(rows.reduce(0) { $0 + $1.sodiumMg })
        avg.addedSugarG   = mean(rows.reduce(0) { $0 + $1.addedSugarG })
        avg.saturatedFatG = mean(rows.reduce(0) { $0 + $1.saturatedFatG })
        return avg
    }

    /// Count of days with at least one entry in the window.
    public static func daysLogged(_ entries: [FoodLogEntryDTO], days: Int, end: Date = Date()) -> Int {
        byDay(entries, days: days, end: end).filter { $0.totals.calories > 0 }.count
    }
}
