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
    @State private var displayPct: Double = 0

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
                    // Fill
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(fillColor)
                        .frame(width: geo.size.width * displayPct)
                    // Hit flash (overlay)
                    if flashActive {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(LinearGradient(
                                colors: [.white.opacity(0.0), .white.opacity(0.55), .white.opacity(0.0)],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * displayPct)
                            .blendMode(.plusLighter)
                            .transition(.opacity)
                    }
                }
            }
            .frame(height: 5)
            .clipped()
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: displayPct)
        .animation(.easeOut(duration: 0.35), value: fillColor)
        .onAppear {
            lastValue = value
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.12)) {
                displayPct = pct
            }
        }
        .onChange(of: value) { _, newValue in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                displayPct = pct
            }
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
