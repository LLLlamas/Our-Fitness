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

    public init(series: [Trends.Point], goal: Double, height: CGFloat = 38, barHeight: CGFloat = 36) {
        self.series = series
        self.goal = goal
        self.height = height
        self.barHeight = barHeight
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            let peak = max(goal, series.map(\.value).max() ?? 1, 1)
            ForEach(Array(series.enumerated()), id: \.offset) { _, point in
                let h = max(2, CGFloat(point.value / peak) * barHeight)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(point.value > 0 && point.value >= goal ? theme.accent : theme.dim.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .frame(height: h)
            }
        }
        .frame(height: height)
    }
}
