// Macro progress display — four mini progress rings in a 2×2 grid.
// Each ring shows current vs target with a circular arc fill.
// An ⓘ button on each cell opens a sheet that leads with YOUR number, explains
// in plain English why that target is what it is, and ties it to your goal.

import SwiftUI

public struct MacroQuadGrid: View {
    public let totals: DailyTotals
    public let targets: MacroTargets
    public let profile: ProfileDTO

    public init(totals: DailyTotals, targets: MacroTargets, profile: ProfileDTO) {
        self.totals = totals
        self.targets = targets
        self.profile = profile
    }

    public var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2),
            spacing: 12
        ) {
            MacroRingCell(macro: .calories, value: Double(totals.calories),
                          target: Double(targets.calories), unit: "", profile: profile)
            MacroRingCell(macro: .protein, value: Double(totals.proteinG),
                          target: Double(targets.proteinG), unit: "g", profile: profile)
            MacroRingCell(macro: .carbs, value: Double(totals.carbsG),
                          target: Double(targets.carbsG), unit: "g", profile: profile)
            MacroRingCell(macro: .fat, value: Double(totals.fatG),
                          target: Double(targets.fatG), unit: "g", profile: profile)
        }
    }
}

// MARK: - Macro kind

private enum Macro {
    case calories, protein, carbs, fat

    var label: String {
        switch self {
        case .calories: return "Calories"
        case .protein:  return "Protein"
        case .carbs:    return "Carbs"
        case .fat:      return "Fat"
        }
    }
}

// MARK: - Ring cell

private struct MacroRingCell: View {
    let macro: Macro
    let value: Double
    let target: Double
    let unit: String
    let profile: ProfileDTO

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
                Text(macro.label.uppercased())
                    .font(.system(size: 9, weight: .medium)).tracking(2)
                    .foregroundStyle(theme.dim)
                Button { showInfo = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                }
                .tactile(.ghost)
                .sheet(isPresented: $showInfo) {
                    MacroInfoSheet(macro: macro, profile: profile)
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
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.line, lineWidth: 1))
        .onChange(of: value) { old, new in
            let wasUnder = old < target * 0.9
            if wasUnder && hitTarget { Haptics.success() }
        }
    }
}

// MARK: - Info sheet

private struct MacroInfoSheet: View {
    let macro: Macro
    let profile: ProfileDTO

    @Environment(\.theme) private var theme

    private var targets: MacroTargets { profile.computedTargets }

    /// The headline number for this macro.
    private var headline: String {
        switch macro {
        case .calories: return "\(targets.calories) cal"
        case .protein:  return "\(targets.proteinG)g"
        case .carbs:    return "\(targets.carbsG)g"
        case .fat:      return "\(targets.fatG)g"
        }
    }

    private var why: String {
        switch macro {
        case .calories: return TargetRationale.calorieWhy(for: profile)
        case .protein:  return TargetRationale.proteinWhy(for: profile)
        case .carbs:    return TargetRationale.carbsWhy(for: profile)
        case .fat:      return TargetRationale.fatWhy(for: profile)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(macro.label.lowercased()).")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("YOUR DAILY TARGET · \(headline.uppercased())")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }

                Text(TargetRationale.goalLine(for: profile.mode))
                    .font(.callout).foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)

                // Calories get a full from-the-ground-up breakdown of how the
                // number was built (rest → maintenance → goal).
                if macro == .calories { calorieBreakdown }

                infoSection(title: "Why this number") {
                    Text(why)
                        .font(.callout).foregroundStyle(theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(theme.dim)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.bg)
    }

    @ViewBuilder
    private var calorieBreakdown: some View {
        let c = TargetRationale.calories(for: profile)
        infoSection(title: "How we got your number") {
            VStack(alignment: .leading, spacing: 8) {
                calcRow(label: "At complete rest (your body's baseline)", detail: "\(c.bmr) cal")
                calcRow(label: "On a normal day · \(c.activityLabel)", detail: "\(c.tdee) cal")
                calcRow(label: c.isSurplus ? "Surplus to build" : "Deficit to lose fat",
                        detail: "\(c.isSurplus ? "+" : "−")\(abs(c.delta)) cal")
                calcRow(label: "Your daily goal", detail: "\(c.target) cal")
            }
        }
    }

    private var footnote: String {
        switch macro {
        case .calories:
            return "Estimated with the Mifflin-St Jeor formula from your height, weight, age, sex, and activity. It's the best available estimate — your real number can vary by about 10%. Source: Frankenfield et al., J Am Diet Assoc, 2005."
        case .protein:
            return "Source: International Society of Sports Nutrition protein position stand (Jäger et al., 2017)."
        case .carbs:
            return "Carbs fill the calories left after your protein and fat are set."
        case .fat:
            return "Source: Whittaker & Wu, J Steroid Biochem Mol Biol, 2021 (dietary fat and testosterone)."
        }
    }

    @ViewBuilder
    private func infoSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption).tracking(2).foregroundStyle(theme.dim)
            content()
        }
    }

    @ViewBuilder
    private func calcRow(label: String, detail: String) -> some View {
        HStack {
            Text(label).font(.callout).foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(detail).font(.system(.callout, design: .monospaced)).foregroundStyle(theme.accent)
        }
        .padding(10)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }
}
