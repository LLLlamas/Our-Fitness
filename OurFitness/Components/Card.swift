import SwiftUI

public struct Card<Content: View>: View {
    public var padding: CGFloat
    public let content: () -> Content

    @Environment(\.theme) private var theme

    public init(padding: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.content = content
    }

    public var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card)
            .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
    }
}
