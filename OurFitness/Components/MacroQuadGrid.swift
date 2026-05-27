// Macro progress display — four mini progress rings in a 2×2 grid.
// Each ring shows current vs target with a circular arc fill.
// An ⓘ button on each cell opens a sheet explaining why that target exists.

import SwiftUI

public struct MacroQuadGrid: View {
    public let totals: DailyTotals
    public let targets: MacroTargets

    public init(totals: DailyTotals, targets: MacroTargets) {
        self.totals = totals
        self.targets = targets
    }

    public var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2),
            spacing: 12
        ) {
            MacroRingCell(
                label: "Calories",
                value: Double(totals.calories),
                target: Double(targets.calories),
                unit: "",
                infoText: "Displayed in calories (cal) — the everyday unit on food labels. 1 cal here = 1 kilocalorie (kcal), the scientific unit. Your target is computed via Mifflin-St Jeor BMR × activity multiplier, then adjusted ±400–500 for your mode. Build = surplus to grow lean mass; Circuit = modest deficit to reduce body fat. The floor is 1,200 cal to protect metabolic rate."
            )
            MacroRingCell(
                label: "Protein",
                value: Double(totals.proteinG),
                target: Double(targets.proteinG),
                unit: "g",
                infoText: "Protein at 1.0–1.1 g/lb preserves muscle during a deficit and drives synthesis in a surplus. It's the most thermogenic macro — 25–30% of its calories are burned just digesting it. Source: Helms et al., ISSN Position Stand, 2014."
            )
            MacroRingCell(
                label: "Carbs",
                value: Double(totals.carbsG),
                target: Double(targets.carbsG),
                unit: "g",
                infoText: "Carbs fill remaining calorie budget after protein and fat. They fuel training, support thyroid function, and keep cortisol in check. Chronically low carbs can suppress leptin and impair the HPA axis."
            )
            MacroRingCell(
                label: "Fat",
                value: Double(totals.fatG),
                target: Double(targets.fatG),
                unit: "g",
                infoText: "Fat is held at ~27–28% of calories — the minimum for hormone production (testosterone, estrogen) and fat-soluble vitamin absorption (A, D, E, K). Below ~20% of calories, hormonal health and recovery suffer."
            )
        }
    }
}

// MARK: - Ring cell

private struct MacroRingCell: View {
    let label: String
    let value: Double
    let target: Double
    let unit: String
    let infoText: String

    @State private var showInfo = false
    @Environment(\.theme) private var theme

    private var pct: Double {
        guard target > 0 else { return 0 }
        return min(1, value / target)
    }
    private var hitTarget: Bool { value >= target * 0.9 && value <= target * 1.1 }
    private var over: Bool { value > target * 1.1 }
    private var ringColor: Color {
        over ? theme.barOver : hitTarget ? theme.barOk : theme.barFill
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                ProgressRing(pct: pct, color: ringColor, trackColor: theme.barBg, lineWidth: 9)
                VStack(spacing: 1) {
                    AnimatedNumber(
                        value,
                        font: .system(size: 17, weight: .semibold, design: .monospaced),
                        color: theme.text
                    )
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: 8))
                            .foregroundStyle(theme.dim)
                    }
                }
            }
            .frame(width: 72, height: 72)

            HStack(spacing: 3) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .medium)).tracking(2)
                    .foregroundStyle(theme.dim)
                Button { showInfo = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                }
                .tactile(.ghost)
                .sheet(isPresented: $showInfo) {
                    MacroInfoSheet(label: label, infoText: infoText)
                        .themed(theme.mode)
                }
            }

            Text("/ \(Int(target.rounded()))\(unit)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(theme.dim)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(theme.card)
        .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
        .onChange(of: value) { old, new in
            let wasUnder = old < target * 0.9
            if wasUnder && hitTarget { Haptics.success() }
        }
    }
}

// MARK: - Info sheet

private struct MacroInfoSheet: View {
    let label: String
    let infoText: String
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(label.uppercased())
                    .font(.caption).tracking(2)
                    .foregroundStyle(theme.dim)
                Text(infoText)
                    .font(.callout)
                    .foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
