// 30-day calorie trend + weekly/monthly averages for the nutrition log.
// Opened from the "This week" card in NutritionView. Mirrors the steps detail.

import SwiftUI
import Charts

struct NutritionTrendSheet: View {
    let profile: ProfileDTO
    let logs: [FoodLogEntryDTO]

    @Environment(\.theme) private var theme

    private var series: [Trends.Point] { NutritionHistory.calorieSeries(logs, days: 30) }
    private var recent: [NutritionHistory.DayTotals] {
        NutritionHistory.byDay(logs, days: 14).filter { $0.totals.calories > 0 }.reversed()
    }
    private var avg7: DailyTotals { NutritionHistory.averagePerLoggedDay(logs, days: 7) }
    private var avg30: DailyTotals { NutritionHistory.averagePerLoggedDay(logs, days: 30) }
    private var target: Int { profile.computedTargets.calories }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("nutrition.")
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

                averagesSection
                recentSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
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
    private var averagesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Average per logged day".uppercased())
                .font(.caption).tracking(2).foregroundStyle(theme.dim)
            avgRow(label: "Last 7 days", t: avg7)
            avgRow(label: "Last 30 days", t: avg30)
        }
    }

    @ViewBuilder
    private func avgRow(label: String, t: DailyTotals) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(theme.dim)
            HStack(spacing: 8) {
                MacroChip(label: "Cal", value: t.calories)
                MacroChip(label: "P", value: t.proteinG)
                MacroChip(label: "C", value: t.carbsG)
                MacroChip(label: "F", value: t.fatG)
                if t.fiberG > 0 { MacroChip(label: "Fiber", value: t.fiberG) }
            }
        }
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
                    HStack {
                        Text(row.day).foregroundStyle(theme.text)
                        Spacer()
                        Text("\(row.totals.calories) cal · \(row.totals.proteinG)p · \(row.totals.carbsG)c · \(row.totals.fatG)f")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(theme.accent)
                    }
                    .padding(10)
                    .background(theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                }
            }
        }
    }
}
