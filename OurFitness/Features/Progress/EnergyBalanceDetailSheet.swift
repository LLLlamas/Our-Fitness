// Energy-balance detail: calories IN (food logs) vs ACTIVITY BURN (steps +
// logged training), charted over the recent window with the user's target
// intake drawn as a reference line. Burn is activity-only — (MET − 1) × kg ×
// hours, so the resting baseline every MET carries is subtracted out. It's the
// same active-calorie figure shown on the Today/Move card.

import SwiftUI
import Charts

struct EnergyBalanceDetailSheet: View {
    let rows: [EnergyBalance.DayBalance]   // oldest-first
    let targetCalories: Int

    @Environment(\.theme) private var theme

    var body: some View {
        // Hoisted once: each of these walks `rows`, and they were previously
        // computed properties read two or three times per pass.
        let chartRows = rows.suffix(30).map { $0 }
        let recentRows = rows.suffix(10).reversed().map { $0 }
        let averages = EnergyBalance.averages(rows)
        InfoSheetScaffold(title: "Energy balance", subtitle: "CALORIES IN vs ACTIVITY BURN") {
            avgSummary(averages: averages)

            chartSection(chartRows: chartRows)

            recentSection(recentRows: recentRows)

            InfoFootnote("Burn is active calories from steps and logged training. Net = in minus burn.")
        }
    }

    // MARK: Average summary

    private func avgSummary(averages: (intake: Int, burned: Int)) -> some View {
        HStack(spacing: 12) {
            summaryCell(label: "AVG IN", value: averages.intake, accent: theme.accent)
            summaryCell(label: "TARGET", value: targetCalories, accent: theme.text)
            summaryCell(label: "AVG BURN", value: averages.burned, accent: theme.accent2)
        }
    }

    private func summaryCell(label: String, value: Int, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold)).tracking(1.5)
                .foregroundStyle(theme.dim)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
                Text("cal")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }

    // MARK: Chart

    @ViewBuilder
    private func chartSection(chartRows: [EnergyBalance.DayBalance]) -> some View {
        InfoSection(title: "Daily intake vs burn") {
            if chartRows.allSatisfy({ $0.intake == 0 && $0.burned == 0 }) {
                Text("Log meals and training to see your intake and burn trend.")
                    .font(.callout).foregroundStyle(theme.dim)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(16)
                    .background(theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
            } else {
                Chart {
                    ForEach(chartRows) { row in
                        BarMark(
                            x: .value("Day", row.day),
                            y: .value("Intake", row.intake)
                        )
                        .foregroundStyle(theme.barFill.opacity(0.85))
                    }
                    ForEach(chartRows) { row in
                        LineMark(
                            x: .value("Day", row.day),
                            y: .value("Burn", row.burned)
                        )
                        .foregroundStyle(theme.accent2)
                        .interpolationMethod(.monotone)
                        PointMark(
                            x: .value("Day", row.day),
                            y: .value("Burn", row.burned)
                        )
                        .symbolSize(14)
                        .foregroundStyle(theme.accent2)
                    }
                    if targetCalories > 0 {
                        RuleMark(y: .value("Target", targetCalories))
                            .foregroundStyle(theme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("target")
                                    .font(.system(size: 9, weight: .semibold)).tracking(1)
                                    .foregroundStyle(theme.accent)
                            }
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 180)

                // Legend
                HStack(spacing: 14) {
                    legendSwatch(color: theme.barFill, label: "Calories in")
                    legendSwatch(color: theme.accent2, label: "Activity burn")
                    legendSwatch(color: theme.accent, label: "Target", dashed: true)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private func legendSwatch(color: Color, label: String, dashed: Bool = false) -> some View {
        HStack(spacing: 5) {
            if dashed {
                Rectangle().fill(color).frame(width: 12, height: 2)
            } else {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(theme.dim)
        }
    }

    // MARK: Recent list

    @ViewBuilder
    private func recentSection(recentRows: [EnergyBalance.DayBalance]) -> some View {
        InfoSection(title: "Recent days") {
            if recentRows.allSatisfy({ $0.intake == 0 && $0.burned == 0 }) {
                Text("Nothing logged yet.")
                    .font(.callout).foregroundStyle(theme.dim)
            } else {
                // Column headers
                HStack {
                    Text("DAY")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("IN")
                        .frame(width: 56, alignment: .trailing)
                    Text("BURN")
                        .frame(width: 56, alignment: .trailing)
                    Text("NET")
                        .frame(width: 64, alignment: .trailing)
                }
                .font(.system(size: 9, weight: .semibold)).tracking(1)
                .foregroundStyle(theme.dim)
                .padding(.horizontal, 10)

                ForEach(recentRows) { row in
                    dayRow(row)
                }
            }
        }
    }

    @ViewBuilder
    private func dayRow(_ row: EnergyBalance.DayBalance) -> some View {
        HStack {
            Text(Dates.formatShort(row.day))
                .font(.system(size: 13))
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(row.intake)")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(theme.accent)
                .frame(width: 56, alignment: .trailing)
            Text("\(row.burned)")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(theme.accent2)
                .frame(width: 56, alignment: .trailing)
            Text("\(row.net >= 0 ? "+" : "")\(row.net)")
                .font(.system(.footnote, design: .monospaced, weight: .semibold))
                .foregroundStyle(row.net >= 0 ? theme.text : theme.warn)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(10)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }
}
