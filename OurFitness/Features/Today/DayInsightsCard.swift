// Today vs yesterday — up to three observations with a next step each, from
// `DayInsights.compute`. Read-only like the rest of Today: the copy points at
// where to act (Meals, Train, the water button) rather than adding a second
// logging surface. Hidden when there's nothing to say.

import SwiftUI

struct DayInsightsCard: View {
    let insights: [DayInsights.Insight]

    @Environment(\.theme) private var theme

    var body: some View {
        if !insights.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Today vs yesterday", systemImage: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.accent)
                    ForEach(insights) { row($0) }
                }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func row(_ insight: DayInsights.Insight) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: insight.symbol)
                .font(.system(size: 14))
                .foregroundStyle(insight.tone == .win ? theme.accent : theme.warn)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.text)
                Text(insight.detail)
                    .font(.caption).foregroundStyle(theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
