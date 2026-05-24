import SwiftUI

public struct StatBlock: View {
    public let label: String
    public let value: String
    public var unit: String?
    public var note: String?

    @Environment(\.theme) private var theme

    public init(label: String, value: String, unit: String? = nil, note: String? = nil) {
        self.label = label
        self.value = value
        self.unit = unit
        self.note = note
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10))
                .tracking(2)
                .foregroundStyle(theme.dim)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 38, weight: .regular, design: .default))
                    .foregroundStyle(theme.text)
                if let unit {
                    Text(unit).font(.footnote).foregroundStyle(theme.dim)
                }
            }
            if let note {
                Text(note).font(.caption).foregroundStyle(theme.accent2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card)
        .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
    }
}
