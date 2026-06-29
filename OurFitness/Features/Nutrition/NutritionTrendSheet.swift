// 30-day calorie trend for the nutrition log.
// Opened from the "This week" card in NutritionView.
// Recent day rows are tappable — tapping jumps back to that day's log in NutritionView.

import SwiftUI
import Charts

struct NutritionTrendSheet: View {
    let profile: ProfileDTO
    let logs: [FoodLogEntryDTO]
    var onSelectDay: ((String) -> Void)? = nil

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var dayDetail: NutritionHistory.DayTotals? = nil

    private var series: [Trends.Point] { NutritionHistory.calorieSeries(logs, days: 30) }
    private var recent: [NutritionHistory.DayTotals] {
        NutritionHistory.byDay(logs, days: 14).filter { $0.totals.calories > 0 }.reversed()
    }
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
        .sheet(item: $dayDetail) { day in
            DayMealDetailSheet(day: day, logs: logs) { dayKey in
                dayDetail = nil
                onSelectDay?(dayKey)
                dismiss()
            }
            .themed(profile.mode)
        }
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
            if recent.isEmpty {
                Text("Nothing logged yet.")
                    .font(.callout).foregroundStyle(theme.dim)
            } else {
                ForEach(recent) { row in
                    PressableCard(action: { dayDetail = row }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Dates.formatLong(row.day))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(theme.text)
                                Text("\(row.totals.calories) cal · \(row.totals.proteinG)g protein · \(row.totals.fatG)g fat")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(theme.accent)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.dim)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Day meal detail sheet

private struct DayMealDetailSheet: View {
    let day: NutritionHistory.DayTotals
    let logs: [FoodLogEntryDTO]
    let onViewInLog: (String) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    private var dayLogs: [FoodLogEntryDTO] {
        logs.filter { $0.date == day.id }.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Dates.formatLong(day.day))
                        .font(.system(size: 32, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("\(day.totals.calories) cal logged")
                        .font(.system(size: 11, weight: .medium)).tracking(2)
                        .textCase(.uppercase)
                        .foregroundStyle(theme.dim)
                }

                HStack(spacing: 8) {
                    MacroChip(label: "Cal", value: day.totals.calories)
                    MacroChip(label: "Protein", value: day.totals.proteinG)
                    MacroChip(label: "Carbs", value: day.totals.carbsG)
                    MacroChip(label: "Fat", value: day.totals.fatG)
                    if day.totals.fiberG > 0 { MacroChip(label: "Fiber", value: day.totals.fiberG) }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Meals logged".uppercased())
                        .font(.caption).tracking(2).foregroundStyle(theme.dim)
                    if dayLogs.isEmpty {
                        Text("No individual meal records for this day.")
                            .font(.callout).foregroundStyle(theme.dim)
                    } else {
                        ForEach(dayLogs) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(entry.customName ?? "Meal")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(theme.text)
                                    Spacer()
                                    Text(entry.slot.label)
                                        .font(.caption)
                                        .foregroundStyle(theme.dim)
                                }
                                Text("\(entry.perServing.calories) cal · \(entry.perServing.proteinG)g protein · \(entry.perServing.carbsG)g carbs · \(entry.perServing.fatG)g fat")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(theme.accent)
                            }
                            .padding(12)
                            .background(theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.bg)
    }
}
