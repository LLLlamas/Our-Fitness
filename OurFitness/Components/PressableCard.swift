// A tappable card that feels like the buttons.
// Use when the *whole card* should be the action (e.g. a meal suggestion card).
// Drops the need for a separate "LOG IT" button inside the card.

import SwiftUI

public struct PressableCard<Content: View>: View {
    public let action: () -> Void
    public let content: () -> Content

    @Environment(\.theme) private var theme

    public init(action: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.action = action
        self.content = content
    }

    public var body: some View {
        Button(action: action) {
            content()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(CardPressStyle(theme: theme))
    }
}

private struct CardPressStyle: ButtonStyle {
    let theme: Theme

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .background {
                ZStack {
                    Rectangle().fill(theme.card)
                    LinearGradient(
                        colors: [.white.opacity(pressed ? 0.03 : 0.10), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                Rectangle().strokeBorder(
                    pressed ? theme.accent.opacity(0.7) : theme.line,
                    lineWidth: 1
                )
            }
            .scaleEffect(pressed ? 0.985 : 1.0)
            .shadow(
                color: theme.text.opacity(pressed ? 0 : 0.12),
                radius: pressed ? 0 : 6,
                x: 0, y: pressed ? 0 : 3
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: pressed)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.55),
                             trigger: pressed) { _, isPressed in isPressed }
    }
}
