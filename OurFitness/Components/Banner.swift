import SwiftUI

public enum BannerTone { case info, warn }

public struct Banner<Content: View>: View {
    public let tone: BannerTone
    public let content: () -> Content

    @Environment(\.theme) private var theme

    public init(tone: BannerTone = .info, @ViewBuilder content: @escaping () -> Content) {
        self.tone = tone
        self.content = content
    }

    private var stroke: Color { tone == .warn ? theme.warn : theme.accent }
    private var bg: Color { stroke.opacity(0.06) }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("⚠")
                .foregroundStyle(stroke)
                .fontWeight(.bold)
            content()
                .font(.system(size: 13))
                .foregroundStyle(theme.text)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(stroke, lineWidth: 1))
    }
}
