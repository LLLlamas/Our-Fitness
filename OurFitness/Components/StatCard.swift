// Uniform square tappable card for the Progress grid.
// Same chrome on every card: title (top), big value (center),
// unit + trend chip (bottom). Empty values show "Tap to log".

import SwiftUI

public struct StatCard: View {
    public let title: String
    public let value: String?
    public let unit: String?
    public let trend: String?
    /// Optional tint for the big value text. Used by the Progress tab to flag
    /// markers that are out of healthy range (theme.ok / theme.warn). When nil
    /// the value falls back to `theme.text` — the original behaviour.
    public let valueAccent: Color?
    public let action: () -> Void

    @Environment(\.theme) private var theme

    public init(
        title: String,
        value: String?,
        unit: String?,
        trend: String?,
        valueAccent: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.value = value
        self.unit = unit
        self.trend = trend
        self.valueAccent = valueAccent
        self.action = action
    }

    public var body: some View {
        PressableCard(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(theme.dim)
                Spacer(minLength: 0)
                if let value {
                    Text(value)
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(valueAccent ?? theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else {
                    Text("—")
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(theme.dim)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if let unit, value != nil {
                        Text(unit)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.dim)
                    } else if value == nil {
                        Text("Tap to log")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.dim)
                    }
                    Spacer()
                    if let trend {
                        Text(trend)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(theme.accent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(theme.accent.opacity(0.12))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
