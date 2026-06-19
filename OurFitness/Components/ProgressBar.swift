// Animated progress bar with a target-hit flash.
//
// Smooth fill on value changes (spring).
// When the value crosses target, briefly pulses brighter to celebrate.
// `inverted: true` means smaller is better (sodium/sugar/sat fat caps).

import SwiftUI

public struct ProgressBar: View {
    public let value: Double
    public let target: Double
    public let label: String
    public var unit: String = ""
    public var inverted: Bool = false

    @Environment(\.theme) private var theme

    @State private var lastValue: Double = 0
    @State private var flashActive: Bool = false
    @State private var reveal: CGFloat = 0

    public init(value: Double, target: Double, label: String,
                unit: String = "", inverted: Bool = false) {
        self.value = value
        self.target = target
        self.label = label
        self.unit = unit
        self.inverted = inverted
    }

    private var pct: Double {
        guard target > 0 else { return 0 }
        return min(1, value / target)
    }

    /// The on-screen fill fraction: the real pct scaled by the reveal sweep, so
    /// the bar fills from 0 every time it (re)appears.
    private var displayPct: Double { pct * Double(reveal) }

    private var hitTarget: Bool {
        inverted ? value <= target : value >= target * 0.95 && value <= target * 1.05
    }

    private var over: Bool {
        inverted ? value > target : value > target * 1.1
    }

    private var fillColor: Color {
        if over { return theme.barOver }
        if hitTarget { return theme.barOk }
        return theme.barFill
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(theme.dim)
                Spacer()
                HStack(spacing: 4) {
                    AnimatedNumber(
                        value,
                        font: .system(.footnote, design: .monospaced),
                        color: theme.text
                    )
                    Text("/ \(Int(target.rounded()))\(unit)")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(theme.dim)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Capsule().fill(theme.barBg)
                    // Gradient fill with glow
                    if displayPct > 0 {
                        let fillWidth = max(geo.size.height, geo.size.width * displayPct)
                        Capsule()
                            .fill(LinearGradient(
                                colors: [fillColor, fillColor.opacity(0.72)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: fillWidth)
                            .shadow(color: fillColor.opacity(over ? 0.25 : 0.45), radius: 5, x: 0, y: 1)
                    }
                    // Hit flash overlay
                    if flashActive {
                        let fillWidth = max(geo.size.height, geo.size.width * displayPct)
                        Capsule()
                            .fill(LinearGradient(
                                colors: [.white.opacity(0.0), .white.opacity(0.6), .white.opacity(0.0)],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: fillWidth)
                            .blendMode(.plusLighter)
                            .transition(.opacity)
                    }
                }
            }
            .frame(height: 7)
            .clipShape(Capsule())
        }
        .animation(.spring(response: 0.48, dampingFraction: 0.80), value: pct)
        .animation(.easeOut(duration: 0.35), value: fillColor)
        .revealOnAppear($reveal)
        .onAppear {
            lastValue = value
        }
        .onChange(of: value) { _, newValue in
            // Flash on transition into the on-target window.
            let wasUnder = inverted ? lastValue > target : lastValue < target * 0.95
            let nowAt = hitTarget
            if wasUnder && nowAt {
                Haptics.success()
                withAnimation(.easeOut(duration: 0.4)) { flashActive = true }
                Task {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    await MainActor.run {
                        withAnimation(.easeIn(duration: 0.3)) { flashActive = false }
                    }
                }
            }
            lastValue = newValue
        }
    }
}
