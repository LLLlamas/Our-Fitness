// Three concentric arcs for the Circuit Train "Movement Minutes" summary.
// Steps / Pilates minutes / Cardio active-energy minutes — each its own ring,
// no shared scale (each has its own goal). Lightweight: pure Shape + Stroke,
// no per-frame state, animates with the surrounding spring.

import SwiftUI

public struct ThreeRingSummary: View {
    public struct Ring: Equatable, Sendable {
        public let label: String
        public let value: Double
        public let goal: Double
        public let color: Color

        public init(label: String, value: Double, goal: Double, color: Color) {
            self.label = label
            self.value = value
            self.goal = goal
            self.color = color
        }

        public var pct: Double {
            guard goal > 0 else { return 0 }
            return min(1, value / goal)
        }
    }

    public let rings: [Ring]   // outer first
    @Environment(\.theme) private var theme

    public init(rings: [Ring]) {
        self.rings = rings
    }

    public var body: some View {
        HStack(spacing: 16) {
            ZStack {
                ForEach(Array(rings.enumerated()), id: \.offset) { idx, ring in
                    let inset = CGFloat(idx) * 14
                    arc(for: ring, inset: inset)
                }
            }
            .frame(width: 120, height: 120)
            .animation(.spring(response: 0.55, dampingFraction: 0.85), value: rings)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(rings.enumerated()), id: \.offset) { _, ring in
                    HStack(spacing: 8) {
                        Circle().fill(ring.color).frame(width: 8, height: 8)
                        Text(ring.label.uppercased())
                            .font(.system(size: 10, weight: .medium)).tracking(2)
                            .foregroundStyle(theme.dim)
                        Spacer()
                        Text(legend(for: ring))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(theme.text)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func arc(for ring: Ring, inset: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(theme.barBg, lineWidth: 10)
            Circle()
                .trim(from: 0, to: ring.pct)
                .stroke(ring.color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(inset)
    }

    private func legend(for ring: Ring) -> String {
        let v = Int(ring.value.rounded())
        let g = Int(ring.goal.rounded())
        return "\(v)/\(g)"
    }
}
