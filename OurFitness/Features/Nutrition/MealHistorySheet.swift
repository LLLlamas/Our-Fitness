// Scrollable meal history: one row per day that has logs, newest first, showing
// what was eaten that day. Tapping a row jumps the Meals log to that day.
//
// This replaced the calendar DatePicker sheet (a grid makes you hunt blindly
// through empty dates) and is the ONE day-history list in the app: both the
// Meals tab's history button and NutritionTrendSheet render `MealHistoryList`.
// Don't add a second one.

import SwiftUI

// MARK: - Row model

/// One logged day: totals from `NutritionHistory.byDay` plus the meal names for
/// that day (display only — the figures all come from Domain).
struct MealHistoryDay: Identifiable {
    let id: String          // dayKey, YYYY-MM-DD
    let totals: DailyTotals
    let mealNames: [String]

    /// Newest-first rows for every logged day. The window sizing, empty-day
    /// filtering and 400-day ceiling live in `NutritionHistory.loggedDays` so
    /// the hostless test suite can reach them; this only attaches meal names.
    /// `maxDays` caps the window (nil = everything back to the oldest entry).
    static func rows(from logs: [FoodLogEntryDTO], maxDays: Int? = nil) -> [MealHistoryDay] {
        var namesByDay: [String: [String]] = [:]
        for e in logs.sorted(by: { $0.timestamp < $1.timestamp }) {
            namesByDay[e.date, default: []].append(e.customName ?? "Meal")
        }

        return NutritionHistory.loggedDays(logs, maxDays: maxDays)
            .map { MealHistoryDay(id: $0.id, totals: $0.totals, mealNames: namesByDay[$0.id] ?? []) }
    }

    /// "Today" / "Yesterday" / "Mon, Oct 12".
    var label: String {
        if id == Dates.dayKey() { return "Today" }
        let yesterday = Dates.dayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        if id == yesterday { return "Yesterday" }
        guard let d = Dates.date(fromDayKey: id) else { return id }
        return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// Meal names, truncated so a 9-entry day still reads as one line of context.
    var mealSummary: String {
        guard !mealNames.isEmpty else { return "" }
        let shown = mealNames.prefix(4).joined(separator: " · ")
        let extra = mealNames.count - min(mealNames.count, 4)
        return extra > 0 ? "\(shown) +\(extra) more" : shown
    }
}

// MARK: - Shared day list

/// The day-history list itself. Rendered by `MealHistorySheet` (all days) and by
/// `NutritionTrendSheet` under its chart (last 30 days, matching the bars).
///
/// Takes rows already built by `MealHistoryDay.rows` rather than the raw logs:
/// both hosts need the row count for their own header, and building them here
/// too meant aggregating the whole food-log history twice per pass.
struct MealHistoryList: View {
    let days: [MealHistoryDay]
    let onSelectDay: (String) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            if days.isEmpty {
                Text("Nothing logged yet.")
                    .font(.callout).foregroundStyle(theme.dim)
            } else {
                ForEach(days) { day in
                    PressableCard(action: { onSelectDay(day.id) }) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(day.label)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(theme.text)
                                Text("\(day.totals.calories) cal · \(day.totals.proteinG)g protein · \(day.totals.carbsG)g carbs · \(day.totals.fatG)g fat")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(theme.accent)
                                if !day.mealSummary.isEmpty {
                                    Text(day.mealSummary)
                                        .font(.caption)
                                        .foregroundStyle(theme.dim)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.dim)
                        }
                    }
                    .accessibilityLabel("\(day.label), \(day.totals.calories) cal, \(day.mealNames.count) logged. Open in the log.")
                }
            }
        }
    }
}

// MARK: - Sheet

struct MealHistorySheet: View {
    let logs: [FoodLogEntryDTO]
    let onSelectDay: (String) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let days = MealHistoryDay.rows(from: logs)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Meal history")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text(days.isEmpty
                         ? "NOTHING LOGGED YET"
                         : "\(days.count) DAY\(days.count == 1 ? "" : "S") LOGGED · TAP TO OPEN")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }

                MealHistoryList(days: days) { dayKey in
                    onSelectDay(dayKey)
                    dismiss()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .scrollHapticTicks()
        }
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
    }
}
