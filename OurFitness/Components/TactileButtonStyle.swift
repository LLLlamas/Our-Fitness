// The single button style for the app.
//
// At rest:  subtle top-edge highlight (3D lift) + drop shadow
// On press: scale 0.96, shadow shrinks, optional brief glare sweep
// Haptic:   tick on touch-down (no haptic on release — feels more responsive)
//
// Variants control color + size + whether the glare sweep fires.
// Keep this list short. Adding a 6th variant is a smell — reuse one.

import SwiftUI

public enum TactileVariant {
    case primary    // bold solid fill, full lift + glare (LOG IT, START SESSION)
    case secondary  // outlined, modest lift (FINISH, secondary CTAs)
    case pill       // chip / tab / slot — small, no glare
    case bump       // +500 / +1k / +2.5k — quiet
    case ghost      // text-only inline action (× close, link)
}

public struct TactileButtonStyle: ButtonStyle {
    public var variant: TactileVariant
    public var fillColor: Color?     // override; otherwise theme-driven per variant
    public var fullWidth: Bool

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    public init(_ variant: TactileVariant = .primary,
                fill: Color? = nil,
                fullWidth: Bool = false) {
        self.variant = variant
        self.fillColor = fill
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let style = resolved(theme: theme)

        configuration.label
            .font(style.font)
            .tracking(style.tracking)
            .textCase(style.textCase)
            .foregroundStyle(isEnabled ? style.fg : style.fg.opacity(0.55))
            .padding(.horizontal, style.padH)
            .padding(.vertical, style.padV)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .fill(isEnabled ? style.bg : style.bg.opacity(0.55))
                    if style.showTopHighlight {
                        topEdgeHighlight(pressed: pressed)
                    }
                    if style.showGlare {
                        GlareSweep(triggerOnPress: pressed)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
            .overlay {
                if style.strokeWidth > 0 {
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .strokeBorder(style.stroke, lineWidth: style.strokeWidth)
                }
            }
            .compositingGroup()
            .scaleEffect(pressed ? 0.96 : 1.0)
            .shadow(
                color: style.shadow.opacity(pressed ? 0.0 : (isEnabled ? 0.35 : 0.0)),
                radius: pressed ? 0 : style.shadowRadius,
                x: 0, y: pressed ? 0 : style.shadowY
            )
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: pressed)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.55),
                             trigger: pressed) { _, isPressed in isPressed }
    }

    // MARK: - Resolved style per variant

    private struct ResolvedStyle {
        var bg: Color
        var fg: Color
        var stroke: Color
        var shadow: Color
        var padH: CGFloat
        var padV: CGFloat
        var strokeWidth: CGFloat
        var shadowRadius: CGFloat
        var shadowY: CGFloat
        var showTopHighlight: Bool
        var showGlare: Bool
        var font: Font
        var tracking: CGFloat
        var textCase: Text.Case?
        var cornerRadius: CGFloat
    }

    private func resolved(theme: Theme) -> ResolvedStyle {
        switch variant {
        case .primary:
            return .init(
                bg: fillColor ?? theme.accent,
                fg: theme.bg,
                stroke: .clear,
                shadow: fillColor ?? theme.accent,
                padH: 18, padV: 12,
                strokeWidth: 0, shadowRadius: 10, shadowY: 4,
                showTopHighlight: true, showGlare: true,
                font: .system(size: 13, weight: .semibold),
                tracking: 2, textCase: .uppercase,
                cornerRadius: 10
            )
        case .secondary:
            return .init(
                bg: theme.card,
                fg: theme.text,
                stroke: theme.line,
                shadow: theme.text,
                padH: 16, padV: 11,
                strokeWidth: 1, shadowRadius: 6, shadowY: 2,
                showTopHighlight: true, showGlare: false,
                font: .system(size: 13, weight: .semibold),
                tracking: 2, textCase: .uppercase,
                cornerRadius: 10
            )
        case .pill:
            return .init(
                bg: fillColor ?? .clear,
                fg: fillColor == nil ? theme.text : theme.bg,
                stroke: fillColor == nil ? theme.line : (fillColor ?? theme.accent),
                shadow: theme.accent,
                padH: 12, padV: 8,
                strokeWidth: 1, shadowRadius: 4, shadowY: 1,
                showTopHighlight: fillColor != nil, showGlare: false,
                font: .system(size: 11, weight: .medium),
                tracking: 2, textCase: .uppercase,
                cornerRadius: 20
            )
        case .bump:
            return .init(
                bg: theme.barBg,
                fg: theme.dim,
                stroke: theme.line,
                shadow: theme.text,
                padH: 10, padV: 6,
                strokeWidth: 1, shadowRadius: 3, shadowY: 1,
                showTopHighlight: false, showGlare: false,
                font: .system(.caption2, design: .monospaced).weight(.medium),
                tracking: 1, textCase: nil,
                cornerRadius: 8
            )
        case .ghost:
            return .init(
                bg: .clear,
                fg: theme.dim,
                stroke: .clear,
                shadow: .clear,
                padH: 8, padV: 6,
                strokeWidth: 0, shadowRadius: 0, shadowY: 0,
                showTopHighlight: false, showGlare: false,
                font: .system(size: 12, weight: .regular),
                tracking: 0, textCase: nil,
                cornerRadius: 0
            )
        }
    }

    // MARK: - Visual effects

    @ViewBuilder
    private func topEdgeHighlight(pressed: Bool) -> some View {
        LinearGradient(
            colors: [.white.opacity(pressed ? 0.05 : 0.18), .clear],
            startPoint: .top,
            endPoint: .center
        )
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

// MARK: - Glare sweep

/// Quick light sweep across the surface when the button is pressed.
/// Subtle: white at 22% alpha, ~450ms diagonal sweep, fires once per press.
private struct GlareSweep: View {
    var triggerOnPress: Bool
    @State private var phase: CGFloat = -1.4   // offscreen left
    @State private var lastTrigger: Bool = false

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, .white.opacity(0.22), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.4)
            .offset(x: geo.size.width * phase)
            .rotationEffect(.degrees(20))
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
            .onChange(of: triggerOnPress) { _, pressed in
                guard pressed, !lastTrigger else { lastTrigger = pressed; return }
                lastTrigger = pressed
                phase = -1.4
                withAnimation(.easeOut(duration: 0.45)) {
                    phase = 1.4
                }
            }
        }
        .clipped()
    }
}

// MARK: - Convenience extensions

public extension View {
    /// Apply `TactileButtonStyle` with a variant. Sugar.
    func tactile(_ variant: TactileVariant = .primary,
                 fill: Color? = nil,
                 fullWidth: Bool = false) -> some View {
        buttonStyle(TactileButtonStyle(variant, fill: fill, fullWidth: fullWidth))
    }
}
