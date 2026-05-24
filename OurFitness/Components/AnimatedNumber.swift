// Smoothly counts a number up/down to a new value over a short duration.
// Use for stat readouts (calories, protein, steps) where snapping looks dead.
//
// `value` is a Double for math convenience; render with the supplied formatter.

import SwiftUI

public struct AnimatedNumber: View, Animatable {
    public var value: Double
    public var format: (Double) -> String
    public var font: Font = .system(size: 28, weight: .regular)
    public var color: Color = .primary

    public init(
        _ value: Double,
        font: Font = .system(size: 28, weight: .regular),
        color: Color = .primary,
        format: @escaping (Double) -> String = { String(Int($0.rounded())) }
    ) {
        self.value = value
        self.font = font
        self.color = color
        self.format = format
    }

    // Animatable conformance: SwiftUI tweens this Double for us.
    public var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    public var body: some View {
        Text(format(value))
            .font(font)
            .foregroundStyle(color)
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}

public extension View {
    /// Animate any value change inside `Self` with a calm spring tuned for stat readouts.
    func tweenStat<V: Equatable>(_ value: V) -> some View {
        animation(.spring(response: 0.45, dampingFraction: 0.85), value: value)
    }
}
