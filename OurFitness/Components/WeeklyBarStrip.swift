// Shared 7-day (or N-day) bar strip. Bars normalize to the larger of the goal
// or the window's peak; days meeting the goal use the accent, others a dim fill.
// Used by the steps, water, and nutrition cards — render your own header above it.

import SwiftUI

public struct WeeklyBarStrip: View {
    public let series: [Trends.Point]
    public let goal: Double
    public var height: CGFloat
    public var barHeight: CGFloat

    @Environment(\.theme) private var theme
    @State private var appeared = false

    public init(series: [Trends.Point], goal: Double, height: CGFloat = 38, barHeight: CGFloat = 36) {
        self.series = series
        self.goal = goal
        self.height = height
        self.barHeight = barHeight
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            let peak = max(goal, series.map(\.value).max() ?? 1, 1)
            ForEach(Array(series.enumerated()), id: \.offset) { idx, point in
                let h = max(2, CGFloat(point.value / peak) * barHeight)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(point.value > 0 && point.value >= goal ? theme.accent : theme.dim.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .frame(height: h)
                    .scaleEffect(y: appeared ? 1 : 0.01, anchor: .bottom)
                    .animation(
                        .spring(response: 0.55, dampingFraction: 0.78)
                            .delay(Double(idx) * 0.04),
                        value: appeared
                    )
            }
        }
        .frame(height: height)
        .onAppear {
            withAnimation { appeared = true }
        }
        .onChange(of: series.map(\.value)) { _, _ in
            appeared = false
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                appeared = true
            }
        }
    }
}
