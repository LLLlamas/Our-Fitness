// The app's single colour/font token set — one warm light palette (sage / terracotta).
// It is the environment default, so every view and sheet reads it without re-applying
// anything; Info.plist `UIUserInterfaceStyle = Light` keeps system chrome (alerts,
// keyboards, wheel pickers) on the same light scheme. AccentColor in the asset catalog
// mirrors `accent` for UIKit-presented chrome — keep the two equal.

import SwiftUI

public struct Theme: Equatable, Sendable {
    // Backgrounds
    public var bg: Color
    public var card: Color
    public var card2: Color
    public var line: Color

    // Foregrounds
    public var text: Color
    public var dim: Color
    public var accent: Color
    public var accent2: Color
    public var ok: Color
    public var warn: Color

    // Bars
    public var barBg: Color
    public var barFill: Color
    public var barOk: Color
    public var barOver: Color

    public static let standard = Theme(
        bg:      Color(red: 0.969, green: 0.953, blue: 0.925),
        card:    Color.white,
        card2:   Color(red: 0.941, green: 0.922, blue: 0.882),
        line:    Color(red: 0.851, green: 0.824, blue: 0.773),
        text:    Color(red: 0.102, green: 0.086, blue: 0.078),
        dim:     Color(red: 0.478, green: 0.451, blue: 0.408),
        accent:  Color(red: 0.498, green: 0.631, blue: 0.447),
        accent2: Color(red: 0.788, green: 0.482, blue: 0.353),
        ok:      Color(red: 0.302, green: 0.541, blue: 0.243),
        warn:    Color(red: 0.769, green: 0.271, blue: 0.212),
        barBg:   Color(red: 0.941, green: 0.922, blue: 0.882),
        barFill: Color(red: 0.498, green: 0.631, blue: 0.447),
        barOk:   Color(red: 0.302, green: 0.541, blue: 0.243),
        barOver: Color(red: 0.769, green: 0.271, blue: 0.212)
    )
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .standard
}

public extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
