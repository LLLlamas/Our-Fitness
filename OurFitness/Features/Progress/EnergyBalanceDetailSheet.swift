// Energy-balance detail: calories IN (food logs) vs ACTIVITY BURN (steps +
// logged training), charted over the recent window with the user's target
// intake drawn as a reference line. Burn excludes resting metabolism — it's
// the same active-calorie figure shown on the Today/Move card.

import SwiftUI
import Charts

struct EnergyBalanceDetailSheet: View {
    let rows: [EnergyBalance.DayBalance]   // oldest-first
    let targetCalories: Int

    @Environment(\.theme) private var theme

    /// Cap the chart window so very long histories stay legible.
    private var chartRows: [EnergyBalance.DayBalance] {
        rows.suffix(30).map { $0 }
    }

    /// Most-recent-first slice for the list under the chart.
    private var recentRows: [EnergyBalance.DayBalance] {
        rows.suffix(10).reversed().map { $0 }
    }

    private var averages: (intake: Int, burned: Int) {
        EnergyBalance.averages(rows)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                avgSummary

                chartSection

                recentSection

                note
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.bg)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Energy balance")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(theme.text)
            Text("CALORIES IN vs ACTIVITY BURN")
                .font(.system(size: 10, weight: .medium)).tracking(2)
                .foregroundStyle(theme.dim)
        }
    }

    // MARK: Average summary

    private var avgSummary: some View {
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
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily intake vs burn")
                .font(.caption).tracking(2).textCase(.uppercase)
                .foregroundStyle(theme.dim)

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
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent days")
                .font(.caption).tracking(2).textCase(.uppercase)
                .foregroundStyle(theme.dim)

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

    // MARK: Footer note

    private var note: some View {
        Text("Burn = active calories from steps + logged training (not resting metabolism). Target is your daily calorie goal. Net = calories in minus activity burn.")
            .font(.footnote)
            .foregroundStyle(theme.dim)
            .fixedSize(horizontal: false, vertical: true)
    }
}
