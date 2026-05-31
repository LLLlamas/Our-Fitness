// Top-of-screen ephemeral confirmation. Animated in/out by ToastHost.
// Single component — keep it small, never has tap targets (no actions).

import SwiftUI

public struct ToastView: View {
    public let toast: Toast

    @Environment(\.theme) private var theme

    public init(_ toast: Toast) { self.toast = toast }

    private var stroke: Color {
        switch toast.accent {
        case .ok:   return theme.ok
        case .win:  return theme.accent
        case .warn: return theme.warn
        case .info: return theme.dim
        }
    }

    public var body: some View {
        HStack(spacing: 12) {
            if let sym = toast.symbol {
                Image(systemName: sym)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(stroke)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.text)
                if let detail = toast.detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.dim)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.card)
                LinearGradient(
                    colors: [.white.opacity(0.10), .clear],
                    startPoint: .top, endPoint: .center
                )
                .blendMode(.plusLighter)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(stroke, lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            Rectangle().fill(stroke).frame(width: 3)
        }
        .shadow(color: stroke.opacity(0.35), radius: 12, y: 4)
        .padding(.horizontal, 16)
    }
}

/// Host overlay that animates the current toast in from the top.
public struct ToastHost: View {
    @EnvironmentObject private var center: ToastCenter

    public init() {}

    public var body: some View {
        VStack {
            if let toast = center.current {
                ToastView(toast)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .padding(.top, 8)
            }
            Spacer()
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: center.current)
        .allowsHitTesting(false)
    }
}
