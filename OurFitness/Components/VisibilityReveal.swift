// Replays a progress "reveal" (0->1) every time a view enters the visible viewport.
//
// SwiftUI's .onAppear fires once and not again when a view scrolls back into view
// or a tab is re-selected, so progress fills that animate on appear go static
// afterward. This modifier watches the view's on-screen position, resets the
// reveal to 0 when it leaves, and springs it back to 1 when it returns — so
// attached progress bars/rings always sweep in from empty on every (re)appearance.

import SwiftUI
import UIKit

public struct RevealOnAppear: ViewModifier {
    @Binding var reveal: CGFloat
    /// Fraction of screen height the view must cross to count as "visible".
    var margin: CGFloat = 0.03

    @State private var onScreen = false

    public func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { evaluate(geo.frame(in: .global)) }
                        .onChange(of: geo.frame(in: .global)) { _, f in evaluate(f) }
                }
            )
            .onDisappear {
                onScreen = false
                reveal = 0
            }
    }

    private func evaluate(_ frame: CGRect) {
        let screenH = UIScreen.main.bounds.height
        guard screenH > 0 else { return }
        let visible = frame.maxY > screenH * margin && frame.minY < screenH * (1 - margin)
        if visible {
            guard !onScreen else { return }
            onScreen = true
            withAnimation(.spring(response: 0.9, dampingFraction: 0.72).delay(0.05)) {
                reveal = 1
            }
        } else {
            guard onScreen else { return }
            onScreen = false
            reveal = 0   // settle at 0 so the next entry sweeps from empty
        }
    }
}

public extension View {
    /// Drives `reveal` (0->1) each time this view becomes visible (scroll or tab),
    /// resetting to 0 when it leaves — so progress fills sweep in from empty on
    /// every (re)appearance.
    func revealOnAppear(_ reveal: Binding<CGFloat>, margin: CGFloat = 0.03) -> some View {
        modifier(RevealOnAppear(reveal: reveal, margin: margin))
    }
}
