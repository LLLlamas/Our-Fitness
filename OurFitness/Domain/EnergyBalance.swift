// Per-day energy in vs out, for the Progress tab's calorie-intake card and
// the intake-vs-burn detail sheet.
//
//   intake = calories logged from food (DailyTotals.totals)
//   burned = ACTIVE calories out (steps + logged training), via DailyBurn —
//            so the exclusions (logged walks, the Walking live-activity) match
//            the Today/Move card exactly. Resting metabolism / BMR is NOT here.
//
// Pure Domain — all math through DailyTotals + DailyBurn (which route through
// CalorieEstimator: MET × bodyWeightKg × hours). Never imports SwiftUI/SwiftData.

import Foundation

public enum EnergyBalance {

    public struct DayBalance: Identifiable, Sendable, Equatable {
        public let id: String      // dayKey, also used as the chart x-value
        public let day: String     // same yyyy-MM-dd key (kept named for readability)
        public let intake: Int     // calories in (food logs)
        public let burned: Int     // ACTIVE calories out (steps + training; excludes resting/BMR)

        public var net: Int { intake - burned }

        public init(day: String, intake: Int, burned: Int) {
            self.id = day
            self.day = day
            self.intake = intake
            self.burned = burned
        }
    }

    /// One `DayBalance` per calendar day over the last `days` ending `end`,
    /// oldest-first. Days with no food and no activity are still emitted as zero,
    /// so the chart shows a dense, gap-free timeline.
    ///
    /// Bucketing keys:
    ///   - `foodLogs.date` and `steps.date` are already "yyyy-MM-dd" day keys.
    ///   - `sets.timestamp`, `cardio.date`, `pilates.date`, `activities.date`
    ///     are `Date`s — bucketed with `Dates.dayKey(_:)`.
    public static func byDay(
        days: Int,
        end: Date = Date(),
        foodLogs: [FoodLogEntryDTO],
        steps: [StepCountDTO],
        sets: [WorkoutSetDTO],
        cardio: [CardioSessionDTO],
        pilates: [PilatesSessionDTO],
        activities: [ActivitySessionDTO],
        bodyWeightLb: Double
    ) -> [DayBalance] {
        let keys = Dates.lastNDays(days, end: end)
        guard !keys.isEmpty else { return [] }
        let window = Set(keys)

        // Group each source by its day key, keeping only days inside the window.
        let foodByDay = Dictionary(grouping: foodLogs.filter { window.contains($0.date) }, by: \.date)
        let stepsByDay: [String: Int] = steps
            .filter { window.contains($0.date) }
            .reduce(into: [:]) { acc, s in acc[s.date, default: 0] += s.steps }
        let setsByDay = Dictionary(grouping: sets.filter { window.contains(Dates.dayKey($0.timestamp)) }, by: { Dates.dayKey($0.timestamp) })
        let cardioByDay = Dictionary(grouping: cardio.filter { window.contains(Dates.dayKey($0.date)) }, by: { Dates.dayKey($0.date) })
        let pilatesByDay = Dictionary(grouping: pilates.filter { window.contains(Dates.dayKey($0.date)) }, by: { Dates.dayKey($0.date) })
        let activitiesByDay = Dictionary(grouping: activities.filter { window.contains(Dates.dayKey($0.date)) }, by: { Dates.dayKey($0.date) })

        return keys.map { key in
            let intake = DailyTotals.totals(from: foodByDay[key] ?? []).calories
            let burned = DailyBurn.metEstimate(
                steps: stepsByDay[key] ?? 0,
                sets: setsByDay[key] ?? [],
                cardio: cardioByDay[key] ?? [],
                pilates: pilatesByDay[key] ?? [],
                activities: activitiesByDay[key] ?? [],
                bodyWeightLb: bodyWeightLb
            )
            return DayBalance(day: key, intake: intake, burned: burned)
        }
    }

    /// Card-facing averages: mean intake and mean burn over the days that had ANY
    /// activity (intake or burn > 0), so a stretch of empty/unlogged days doesn't
    /// drag the average toward zero. Returns (0, 0) when nothing was logged.
    public static func averages(_ rows: [DayBalance]) -> (intake: Int, burned: Int) {
        let active = rows.filter { $0.intake > 0 || $0.burned > 0 }
        guard !active.isEmpty else { return (0, 0) }
        let intake = active.reduce(0) { $0 + $1.intake }
        let burned = active.reduce(0) { $0 + $1.burned }
        return (
            Int((Double(intake) / Double(active.count)).rounded()),
            Int((Double(burned) / Double(active.count)).rounded())
        )
    }
}
