import SwiftUI

struct StepsCard: View {
    let steps: Int
    let goal: Int
    let sourceLabel: String
    let onManualSave: (Int) -> Void

    @Environment(\.theme) private var theme
    @State private var lastSteps: Int = 0

    private var pct: Double {
        guard goal > 0 else { return 0 }
        return min(1, Double(steps) / Double(goal))
    }
    private var ok: Bool { steps >= goal }

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("STEPS TODAY")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(2)
                        .foregroundStyle(theme.dim)
                    Spacer()
                    Text("\(steps.formatted()) / \(goal.formatted())")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(ok ? theme.ok : theme.dim)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    AnimatedNumber(
                        Double(steps),
                        font: .system(size: 44, weight: .regular),
                        color: theme.text
                    )
                    .tweenStat(steps)

                    Spacer()
                    HStack(spacing: 6) {
                        bumpButton(500)
                        bumpButton(1000)
                        bumpButton(2500)
                    }
                }

                // Track + animated fill
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

                HStack(spacing: 6) {
                    Image(systemName: ok ? "checkmark.seal.fill" : "heart.text.square")
                        .foregroundStyle(ok ? theme.ok : theme.dim)
                        .contentTransition(.symbolEffect(.replace))
                    Text(sourceLabel)
                        .font(.caption2)
                        .foregroundStyle(theme.dim)
                }
            }
        }
        .onAppear { lastSteps = steps }
        .onChange(of: steps) { old, new in
            // Cross the goal line → celebration
            if old < goal && new >= goal {
                Haptics.success()
            }
            lastSteps = new
        }
    }

    @ViewBuilder
    private func bumpButton(_ delta: Int) -> some View {
        Button {
            onManualSave(max(0, steps + delta))
            Haptics.bump()
        } label: {
            Text("+\(delta >= 1000 ? "\(delta / 1000)k" : "\(delta)")")
        }
        .tactile(.bump)
    }
}
