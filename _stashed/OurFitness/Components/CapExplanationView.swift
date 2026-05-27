// Sheet content for a Reset cap explanation.
// Copy lives in Domain/CapExplanations.swift — this is purely presentational.

import SwiftUI

public struct CapExplanationView: View {
    public let explanation: CapExplanation

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    public init(explanation: CapExplanation) {
        self.explanation = explanation
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(explanation.title.lowercased() + ".")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundStyle(theme.text)

                Text(explanation.limit)
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(theme.accent)

                Text("Why this matters")
                    .font(.caption).tracking(2).textCase(.uppercase)
                    .foregroundStyle(theme.dim)
                Text(explanation.whyItMatters)
                    .font(.body)
                    .foregroundStyle(theme.text)

                Text("Source")
                    .font(.caption).tracking(2).textCase(.uppercase)
                    .foregroundStyle(theme.dim)
                Text(explanation.source)
                    .font(.callout)
                    .foregroundStyle(theme.dim)

                Spacer(minLength: 8)

                Button { dismiss() } label: {
                    Text("Got it")
                }
                .tactile(.primary, fullWidth: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(theme.bg.ignoresSafeArea())
    }
}
