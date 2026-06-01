// Custom-drawn drinking-glass icons for the water tracker presets.
//
// Replaces the old coffee-cup SF Symbols. Three glass sizes (small/medium/large)
// are tapered tumblers that differ in height + width so the size reads at a
// glance; the bottle option falls back to the `waterbottle.fill` SF Symbol. All
// are tintable like a symbol — they take the current `theme` accent.

import SwiftUI

/// Tapered-glass outline. Top is the rim (wider); bottom is the base (narrower).
private struct GlassShape: Shape {
    /// Fraction of the width each side draws in at the base (per side).
    var taper: CGFloat = 0.16

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let inset = rect.width * taper
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Renders a `Water.CupIcon` as a tintable glyph sized to roughly match an
/// 18pt SF Symbol in the preset row.
struct GlassIcon: View {
    let icon: Water.CupIcon
    var tint: Color
    /// Nominal glyph height for the largest glass / the symbol. Smaller glasses
    /// scale down from this so they look like smaller vessels.
    var height: CGFloat = 22

    private var dims: (w: CGFloat, h: CGFloat) {
        switch icon {
        case .glassSmall:  return (height * 0.46, height * 0.66)
        case .glassMedium: return (height * 0.52, height * 0.82)
        case .glassLarge:  return (height * 0.58, height * 1.00)
        case .bottle:      return (height, height)   // unused; symbol path below
        }
    }

    var body: some View {
        switch icon {
        case .bottle:
            Image(systemName: "waterbottle.fill")
                .font(.system(size: height * 0.82))
                .foregroundStyle(tint)
                .frame(height: height)
        case .glassSmall, .glassMedium, .glassLarge:
            glass
                .frame(height: height, alignment: .bottom)
        }
    }

    private var glass: some View {
        let d = dims
        return ZStack(alignment: .bottom) {
            // Glass body fill (faint) + water fill (stronger) clipped to the glass.
            // The glass height `d.h` is known, so the water level is a fixed
            // fraction of it — no GeometryReader needed (this renders per preset
            // in a ForEach row, so we keep it allocation-light).
            GlassShape().fill(tint.opacity(0.14))
            Rectangle()
                .fill(tint.opacity(0.55))
                .frame(height: d.h * 0.66)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .mask(GlassShape())
            // Rim + sides outline.
            GlassShape().stroke(tint, lineWidth: 1.5)
        }
        .frame(width: d.w, height: d.h)
    }
}
