import SwiftUI

/// Circular progress arc. Wrap in a ZStack to add center labels.
/// Callers control frame size; this view fills the available space.
public struct ProgressRing: View {
    public let pct: Double
    public let color: Color
    public let trackColor: Color
    public let lineWidth: CGFloat

    public init(pct: Double, color: Color, trackColor: Color, lineWidth: CGFloat = 10) {
        self.pct = pct
        self.color = color
        self.trackColor = trackColor
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle().stroke(trackColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, pct)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.55, dampingFraction: 0.85), value: pct)
        }
    }
}
