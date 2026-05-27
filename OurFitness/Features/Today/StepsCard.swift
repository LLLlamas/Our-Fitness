import SwiftUI

struct StepsCard: View {
    let steps: Int
    let goal: Int
    let healthGranted: Bool
    let onConnectHealth: () -> Void

    @Environment(\.theme) private var theme

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
                        Text("\(steps.formatted()) / \(goal.formatted())")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(ok ? theme.ok : theme.dim)
                            .monospacedDigit()
                            .contentTransition(.numericText())
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
            if old < goal && new >= goal {
                Haptics.success()
            }
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
}
