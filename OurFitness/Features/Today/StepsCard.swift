import SwiftUI

struct StepsCard: View {
    let steps: Int
    let defaultGoal: Int
    let profileId: UUID
    let healthGranted: Bool
    let weightLb: Double
    let mode: Mode
    let onConnectHealth: () -> Void

    @Environment(\.theme) private var theme
    @AppStorage private var customGoalRaw: Int
    @State private var showGoalPicker = false
    @State private var showInfo = false
    @State private var pickerGoal: Int = 10_000

    init(
        steps: Int,
        goal: Int,
        profileId: UUID,
        healthGranted: Bool,
        weightLb: Double,
        mode: Mode,
        onConnectHealth: @escaping () -> Void
    ) {
        self.steps = steps
        self.defaultGoal = goal
        self.profileId = profileId
        self.healthGranted = healthGranted
        self.weightLb = weightLb
        self.mode = mode
        self.onConnectHealth = onConnectHealth
        _customGoalRaw = AppStorage(wrappedValue: 0, "stepsGoal.\(profileId.uuidString)")
    }

    private var goal: Int { customGoalRaw > 0 ? customGoalRaw : defaultGoal }
    private var stepsKcal: Int {
        Int(CalorieEstimator.caloriesForSteps(steps: steps, bodyWeightLb: weightLb).rounded())
    }
    private var weightKg: Int { Int(weightLb * 0.4536) }
    private var pct: Double {
        guard goal > 0 else { return 0 }
        return min(1, Double(steps) / Double(goal))
    }
    private var ok: Bool { steps >= goal }
    private var hasData: Bool { steps > 0 }

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("STEPS TODAY")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(2)
                        .foregroundStyle(theme.dim)
                    Button { showInfo = true } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.dim)
                    }
                    .tactile(.ghost)
                    .accessibilityLabel("Steps health info")
                    Spacer()
                    if healthGranted && hasData {
                        Button {
                            pickerGoal = goal
                            showGoalPicker = true
                        } label: {
                            Text("\(steps.formatted()) / \(goal.formatted())")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(ok ? theme.ok : theme.dim)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .underline(color: (ok ? theme.ok : theme.dim).opacity(0.4))
                        }
                        .tactile(.ghost)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if healthGranted {
                        if hasData {
                            AnimatedNumber(
                                Double(steps),
                                font: .system(size: 44, weight: .regular),
                                color: theme.text
                            )
                            .tweenStat(steps)
                        } else {
                            Text("—")
                                .font(.system(size: 44, weight: .regular))
                                .foregroundStyle(theme.dim)
                        }
                    } else {
                        Text("—")
                            .font(.system(size: 44, weight: .regular))
                            .foregroundStyle(theme.dim)
                    }
                    Spacer()
                }

                if hasData && stepsKcal > 0 {
                    Text("~\(stepsKcal) cal burned")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.accent)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.barBg)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(ok ? theme.barOk : theme.barFill)
                            .frame(width: geo.size.width * pct)
                    }
                }
                .frame(height: 5)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: pct)

                footer
            }
        }
        .onChange(of: steps) { old, new in
            if old < goal && new >= goal { Haptics.success() }
        }
        .sheet(isPresented: $showGoalPicker) {
            goalPickerSheet.themed(theme.mode)
        }
        .sheet(isPresented: $showInfo) {
            StepsInfoSheet(steps: steps, stepsKcal: stepsKcal, weightKg: weightKg, mode: mode)
                .themed(mode)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if !healthGranted {
            Button(action: onConnectHealth) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.text.square")
                    Text("Connect Apple Health")
                }
            }
            .tactile(.pill, fill: theme.accent)
        } else if !hasData {
            HStack(spacing: 6) {
                Image(systemName: "heart.text.square")
                    .foregroundStyle(theme.dim)
                Text("No data from Health yet.")
                    .font(.caption2)
                    .foregroundStyle(theme.dim)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: ok ? "checkmark.seal.fill" : "heart.text.square")
                    .foregroundStyle(ok ? theme.ok : theme.dim)
                    .contentTransition(.symbolEffect(.replace))
                Text("Synced from Apple Health")
                    .font(.caption2)
                    .foregroundStyle(theme.dim)
            }
        }
    }

    @ViewBuilder
    private var goalPickerSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily Steps Goal")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(theme.text)
                Text("Mode default is \(defaultGoal.formatted()) steps.")
                    .font(.caption)
                    .foregroundStyle(theme.dim)
            }
            .padding(.top, 28)
            .padding(.horizontal, 20)

            Picker("Goal", selection: $pickerGoal) {
                ForEach(Array(stride(from: 2000, through: 25000, by: 500)), id: \.self) { val in
                    Text("\(val.formatted()) steps").tag(val)
                }
            }
            .pickerStyle(.wheel)
            .background(theme.card2)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            HStack(spacing: 12) {
                Button("Reset to default") {
                    customGoalRaw = 0
                    showGoalPicker = false
                }
                .tactile(.secondary, fullWidth: true)
                Button("Save") {
                    customGoalRaw = pickerGoal
                    showGoalPicker = false
                    Haptics.success()
                }
                .tactile(.primary, fullWidth: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.bg)
    }
}

// MARK: - Steps info sheet

private struct StepsInfoSheet: View {
    let steps: Int
    let stepsKcal: Int
    let weightKg: Int
    let mode: Mode

    @Environment(\.theme) private var theme

    // Fat burned: walking is ~55% fat oxidation at low-moderate intensity
    private var fatGrams: Int { max(0, Int((Double(stepsKcal) * 0.55 / 9.0).rounded())) }

    // Step category per Tudor-Locke & Bassett (2004) classification
    private var stepCategory: (label: String, description: String) {
        switch steps {
        case 0..<5000:
            return ("Sedentary", "Under 5,000 steps/day is associated with increased cardiovascular disease risk, higher LDL, and insulin resistance.")
        case 5000..<7500:
            return ("Low active", "5,000–7,499 steps/day. Better than sedentary — aim to add a 10-15 min walk to cross 7,500.")
        case 7500..<10000:
            return ("Somewhat active", "7,500–9,999 steps/day reduces metabolic syndrome risk by ~20% vs. sedentary. Close to optimal.")
        case 10000..<12500:
            return ("Active", "10,000+ steps/day: measurably reduces LDL, blood pressure, and fasting glucose within 2–4 weeks of consistency.")
        default:
            return ("Highly active", "12,500+ steps/day: associated with highest cardiovascular fitness scores. Strong longevity marker.")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("steps.")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("TODAY'S MOVEMENT")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }

                infoSection(title: "Calorie formula") {
                    infoRow(label: "MET 4.3 × \(weightKg)kg × \(steps.formatted())/7392 hr",
                            detail: "≈\(stepsKcal) cal burned")
                    infoRow(label: "Fat burned",
                            detail: "~\(fatGrams)g fat oxidized (55% fat at walking intensity)")
                }

                infoSection(title: "Today's activity level") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(stepCategory.label)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.accent)
                        Text(stepCategory.description)
                            .font(.callout)
                            .foregroundStyle(theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                }

                infoSection(title: "Health research") {
                    VStack(alignment: .leading, spacing: 8) {
                        researchRow("Each 1,000 additional daily steps reduces all-cause mortality by ~6% (Saint-Maurice et al., JAMA 2020).")
                        researchRow("10,000 steps/day lowers resting blood pressure by 3–5 mmHg within 4 weeks of consistency.")
                        researchRow("30+ minutes of walking improves insulin sensitivity for 24–48 hours post-walk.")
                        if mode == .circuit {
                            researchRow("Circuit target: 10,000 steps/day is the #1 lever for reducing LDL, blood pressure, and fasting glucose simultaneously.")
                        }
                    }
                }

                Text("Sources: Tudor-Locke & Bassett 2004; Saint-Maurice et al. JAMA 2020; Ainsworth 2011 Compendium.")
                    .font(.caption2)
                    .foregroundStyle(theme.dim)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.bg)
    }

    @ViewBuilder
    private func infoSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption).tracking(2)
                .foregroundStyle(theme.dim)
            content()
        }
    }

    @ViewBuilder
    private func infoRow(label: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(theme.accent)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private func researchRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("·").foregroundStyle(theme.accent).font(.callout)
            Text(text).font(.callout).foregroundStyle(theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
