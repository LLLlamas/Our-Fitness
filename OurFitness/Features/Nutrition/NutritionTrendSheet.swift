// 30-day calorie trend for the nutrition log.
// Opened from the "This week" card in NutritionView.
// The day list under the chart is the shared `MealHistoryList` (see
// MealHistorySheet.swift) — tapping a day opens it in the Meals log.

import SwiftUI
import Charts

struct NutritionTrendSheet: View {
    let profile: ProfileDTO
    let logs: [FoodLogEntryDTO]
    var onSelectDay: ((String) -> Void)? = nil

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // One walk of the log history per pass: `series` used to be a computed
        // property read twice (the has-data check and the chart itself).
        let series = NutritionHistory.calorieSeries(logs, days: 30)
        let target = profile.computedTargets.calories
        // Same rows as the Meals history sheet, scoped to the charted window.
        let days = MealHistoryDay.rows(from: logs, maxDays: 30)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nutrition")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("CALORIES · LAST 30 DAYS · TARGET \(target)")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }

                if series.contains(where: { $0.value > 0 }) {
                    chart(series: series, target: target)
                } else {
                    Text("Log meals across a few days to see your trend.")
                        .font(.callout).foregroundStyle(theme.dim)
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .background(theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                }

                recentSection(days: days)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .scrollHapticTicks()
        }
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
    }

    @ViewBuilder
    private func chart(series: [Trends.Point], target: Int) -> some View {
        Chart {
            ForEach(series, id: \.date) { p in
                BarMark(
                    x: .value("Day", p.date),
                    y: .value("Calories", p.value)
                )
                .foregroundStyle(p.value >= Double(target) * 0.95 ? theme.barOk : theme.accent)
            }
            RuleMark(y: .value("Target", Double(target)))
                .foregroundStyle(theme.dim)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .chartXAxis(.hidden)
        .frame(height: 180)
    }

    @ViewBuilder
    private func recentSection(days: [MealHistoryDay]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent days".uppercased())
                .font(.caption).tracking(2).foregroundStyle(theme.dim)
            MealHistoryList(days: days) { dayKey in
                onSelectDay?(dayKey)
                dismiss()
            }
        }
    }
}
