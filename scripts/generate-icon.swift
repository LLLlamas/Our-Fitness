#!/usr/bin/env swift
// Generates a 1024×1024 App Store icon at the path passed as argv[1].
// Pure Swift + CoreGraphics — no external tools, works on any macOS with Xcode.
//
// Background: warm dark.
// Wordmark: "OF" in heavy SF, accent orange.
// Subtle warm radial glow from the bottom (depth, not flair).
// Thin accent bar beneath the wordmark (a quiet nod to the progress bars in the app).
// No alpha channel — App Store requirement.

import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// MARK: - Inputs

let size: Int = 1024
let outPath: String = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon.png"

// MARK: - Palette (matches Theme.build tokens)

let bg          = CGColor(red: 0.078, green: 0.063, blue: 0.055, alpha: 1.0)   // warm near-black
let accent      = CGColor(red: 1.000, green: 0.420, blue: 0.137, alpha: 1.0)   // build orange
let glow        = CGColor(red: 1.000, green: 0.420, blue: 0.137, alpha: 0.22)  // accent, soft
let clearAccent = CGColor(red: 1.000, green: 0.420, blue: 0.137, alpha: 0.0)

// MARK: - Context (opaque, no alpha → App Store compliant)

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fputs("[icon] failed to create CGContext\n", stderr); exit(1)
}

let bounds = CGRect(x: 0, y: 0, width: size, height: size)

// Background
ctx.setFillColor(bg)
ctx.fill(bounds)

// Soft radial glow rising from bottom-center
if let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [glow, clearAccent] as CFArray,
    locations: [0.0, 1.0] as [CGFloat]
) {
    let center = CGPoint(x: CGFloat(size) * 0.5, y: CGFloat(size) * 0.25)
    ctx.drawRadialGradient(
        gradient,
        startCenter: center, startRadius: 0,
        endCenter: center, endRadius: CGFloat(size) * 0.8,
        options: []
    )
}

// MARK: - Wordmark "OF"

let fontSize: CGFloat = 560
let font = NSFont.systemFont(ofSize: fontSize, weight: .black)
let attrString = NSAttributedString(
    string: "OF",
    attributes: [
        .font: font,
        .foregroundColor: NSColor(cgColor: accent) ?? .orange,
    ]
)
let line = CTLineCreateWithAttributedString(attrString)
let glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

let textX = (CGFloat(size) - glyphBounds.width) / 2 - glyphBounds.minX
let textY = (CGFloat(size) - glyphBounds.height) / 2 - glyphBounds.minY + 30  // optical center

ctx.textPosition = CGPoint(x: textX, y: textY)
CTLineDraw(line, ctx)

// MARK: - Accent bar under the wordmark

let barW: CGFloat = CGFloat(size) * 0.34
let barH: CGFloat = 14
let barRect = CGRect(
    x: (CGFloat(size) - barW) / 2,
    y: CGFloat(size) * 0.17,
    width: barW,
    height: barH
)
ctx.setFillColor(accent)
ctx.fill(barRect)

// MARK: - Write PNG

guard let cgImage = ctx.makeImage() else {
    fputs("[icon] failed to make CGImage\n", stderr); exit(1)
}

let url = URL(fileURLWithPath: outPath)
let pngType = UTType.png.identifier as CFString
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, pngType, 1, nil) else {
    fputs("[icon] failed to create image destination at \(outPath)\n", stderr); exit(1)
}

CGImageDestinationAddImage(dest, cgImage, nil)
guard CGImageDestinationFinalize(dest) else {
    fputs("[icon] failed to finalize PNG\n", stderr); exit(1)
}

print("[icon] ✓ wrote \(outPath) (\(size)×\(size), no alpha)")
