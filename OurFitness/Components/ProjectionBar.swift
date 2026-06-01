// Inline projection strip shown below action buttons in workout and step cards.
// Purely informational — no tap target. The string is pre-formatted by
// EncouragementEngine (e.g. "1,500 more steps · ~60 cal to goal").

import SwiftUI

struct ProjectionBar: View {
    let text: String

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(theme.dim)
            Text(text)
                .font(.caption)
                .foregroundStyle(theme.accent2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }
}
