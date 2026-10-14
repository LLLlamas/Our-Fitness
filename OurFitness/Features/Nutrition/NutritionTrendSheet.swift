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

    private var series: [Trends.Point] { NutritionHistory.calorieSeries(logs, days: 30) }
    private var target: Int { profile.computedTargets.calories }

    var body: some View {
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
                    chart
                } else {
                    Text("Log meals across a few days to see your trend.")
                        .font(.callout).foregroundStyle(theme.dim)
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .background(theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                }

                recentSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .scrollHapticTicks()
        }
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
    }

    @ViewBuilder
    private var chart: some View {
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
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent days".uppercased())
                .font(.caption).tracking(2).foregroundStyle(theme.dim)
            // Same rows as the Meals history sheet, scoped to the charted window.
            MealHistoryList(logs: logs, maxDays: 30) { dayKey in
                onSelectDay?(dayKey)
                dismiss()
            }
        }
    }
}
