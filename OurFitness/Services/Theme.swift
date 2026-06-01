// Mode-aware color/font tokens. Inject at the screen root via .environment(\.theme, ...).
// Every component reads from Theme rather than branching on mode.

import SwiftUI

public struct Theme: Equatable, Sendable {
    public var mode: Mode

    // Backgrounds
    public var bg: Color
    public var card: Color
    public var card2: Color
    public var line: Color

    // Foregrounds
    public var text: Color
    public var dim: Color
    /// Higher-contrast secondary text. Sits between `dim` and `text` so muted
    /// labels stay legible — including when iOS dims a surface behind a presented
    /// sheet (e.g. Settings cards under the mode-switch sheet). Use for sub-labels
    /// that must remain readable; keep `dim` for purely decorative captions.
    public var dim2: Color
    public var accent: Color
    public var accent2: Color
    public var ok: Color
    public var warn: Color

    // Bars
    public var barBg: Color
    public var barFill: Color
    public var barOk: Color
    public var barOver: Color

    public static let build = Theme(
        mode: .build,
        bg:      Color(red: 0.039, green: 0.039, blue: 0.039),
        card:    Color(red: 0.075, green: 0.075, blue: 0.075),
        card2:   Color(red: 0.102, green: 0.102, blue: 0.102),
        line:    Color(red: 0.149, green: 0.149, blue: 0.149),
        text:    Color(red: 0.961, green: 0.961, blue: 0.941),
        dim:     Color(red: 0.541, green: 0.541, blue: 0.510),
        dim2:    Color(red: 0.745, green: 0.741, blue: 0.706),
        accent:  Color(red: 1.000, green: 0.420, blue: 0.208),
        accent2: Color(red: 1.000, green: 0.722, blue: 0.000),
        ok:      Color(red: 0.498, green: 0.690, blue: 0.412),
        warn:    Color(red: 0.902, green: 0.224, blue: 0.275),
        barBg:   Color(red: 0.102, green: 0.102, blue: 0.102),
        barFill: Color(red: 1.000, green: 0.420, blue: 0.208),
        barOk:   Color(red: 0.498, green: 0.690, blue: 0.412),
        barOver: Color(red: 0.902, green: 0.224, blue: 0.275)
    )

    public static let circuit = Theme(
        mode: .circuit,
        bg:      Color(red: 0.969, green: 0.953, blue: 0.925),
        card:    Color.white,
        card2:   Color(red: 0.941, green: 0.922, blue: 0.882),
        line:    Color(red: 0.851, green: 0.824, blue: 0.773),
        text:    Color(red: 0.102, green: 0.086, blue: 0.078),
        dim:     Color(red: 0.478, green: 0.451, blue: 0.408),
        dim2:    Color(red: 0.302, green: 0.282, blue: 0.255),
        accent:  Color(red: 0.498, green: 0.631, blue: 0.447),
        accent2: Color(red: 0.788, green: 0.482, blue: 0.353),
        ok:      Color(red: 0.302, green: 0.541, blue: 0.243),
        warn:    Color(red: 0.769, green: 0.271, blue: 0.212),
        barBg:   Color(red: 0.941, green: 0.922, blue: 0.882),
        barFill: Color(red: 0.498, green: 0.631, blue: 0.447),
        barOk:   Color(red: 0.302, green: 0.541, blue: 0.243),
        barOver: Color(red: 0.769, green: 0.271, blue: 0.212)
    )

    public static func `for`(_ mode: Mode) -> Theme {
        mode == .circuit ? .circuit : .build
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .build
}

public extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

public extension View {
    /// Apply the mode's tokens to this subtree.
    /// Also forces colorScheme so system UI (wheel pickers, etc.) renders correctly
    /// against the mode's background regardless of the device's iOS setting.
    func themed(_ mode: Mode) -> some View {
        environment(\.theme, .for(mode))
            .environment(\.colorScheme, mode == .build ? .dark : .light)
    }
}
