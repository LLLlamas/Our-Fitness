// Top-left identity avatar. One profile per install — tapping opens Settings.
//
// Collapsed from the former ProfileSwitcher (a shared-device "Whose device is
// this?" picker). The App Store model is one person per install, so there's
// nothing to switch between; the avatar is now just an identity badge that
// routes to Settings. The store layer keeps its per-profile scoping, so the
// multi-profile capability is dormant rather than removed.

import SwiftUI

public struct ProfileAvatar: View {
    public let profile: ProfileDTO
    public let onTap: () -> Void

    @Environment(\.theme) private var theme

    public init(profile: ProfileDTO, onTap: @escaping () -> Void) {
        self.profile = profile
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle().fill(theme.accent.opacity(0.18))
                Text(initial)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }
            .frame(width: 34, height: 34)
            .overlay(Circle().stroke(theme.line, lineWidth: 1))
        }
        .tactile(.ghost)
        .accessibilityLabel("\(profile.name) — profile and settings")
    }

    private var initial: String {
        String(profile.name.prefix(1)).uppercased()
    }
}
