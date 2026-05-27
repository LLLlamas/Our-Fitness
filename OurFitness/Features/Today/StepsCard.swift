import SwiftUI

struct StepsCard: View {
    let steps: Int
    let defaultGoal: Int
    let profileId: UUID
    let healthGranted: Bool
    let onConnectHealth: () -> Void

    @Environment(\.theme) private var theme
    @AppStorage private var customGoalRaw: Int
    @State private var showGoalPicker = false
    @State private var pickerGoal: Int = 10_000

    init(
        steps: Int,
        goal: Int,
        profileId: UUID,
        healthGranted: Bool,
        onConnectHealth: @escaping () -> Void
    ) {
        self.steps = steps
        self.defaultGoal = goal
        self.profileId = profileId
        self.healthGranted = healthGranted
        self.onConnectHealth = onConnectHealth
        _customGoalRaw = AppStorage(wrappedValue: 0, "stepsGoal.\(profileId.uuidString)")
    }

    private var goal: Int { customGoalRaw > 0 ? customGoalRaw : defaultGoal }
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

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(theme.barBg)
                        Rectangle()
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
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
