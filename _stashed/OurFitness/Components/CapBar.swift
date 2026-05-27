// Reset-only progress bar with a trailing info button.
//
// Wraps `ProgressBar` (don't reinvent the bar visuals; reuse its target-hit flash,
// haptic, and inversion logic) and adds an `info.circle` button that presents
// `CapExplanationView` in a sheet.

import SwiftUI

public struct CapBar: View {
    public let value: Double
    public let target: Double
    public let label: String
    public let unit: String
    public let inverted: Bool
    public let explanation: CapExplanation

    @Environment(\.theme) private var theme
    @State private var showSheet = false

    public init(
        value: Double, target: Double, label: String,
        unit: String = "", inverted: Bool = false,
        explanation: CapExplanation
    ) {
        self.value = value
        self.target = target
        self.label = label
        self.unit = unit
        self.inverted = inverted
        self.explanation = explanation
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ProgressBar(
                value: value, target: target, label: label,
                unit: unit, inverted: inverted
            )
            Button {
                showSheet = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
            }
            .tactile(.ghost)
            .accessibilityLabel("Why this \(explanation.title.lowercased()) cap?")
        }
        .sheet(isPresented: $showSheet) {
            CapExplanationView(explanation: explanation)
                .themed(theme.mode)
        }
    }
}
