// Top-left avatar that flips the active profile.
// Both profiles always exist; this only changes which one the shell renders.
// No auth — both households trust each other (see CLAUDE.md §2).

import SwiftUI

public struct ProfileSwitcher: View {
    public let profiles: [ProfileDTO]
    public let active: ProfileDTO
    public let onSelect: (ProfileDTO) -> Void
    public let onOpenSettings: () -> Void
    public let onAddProfile: () -> Void

    @Environment(\.theme) private var theme
    @State private var showSheet = false

    public init(
        profiles: [ProfileDTO],
        active: ProfileDTO,
        onSelect: @escaping (ProfileDTO) -> Void,
        onOpenSettings: @escaping () -> Void,
        onAddProfile: @escaping () -> Void
    ) {
        self.profiles = profiles
        self.active = active
        self.onSelect = onSelect
        self.onOpenSettings = onOpenSettings
        self.onAddProfile = onAddProfile
    }

    public var body: some View {
        Button { showSheet = true } label: {
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
        .sheet(isPresented: $showSheet) {
            sheet
                .presentationDetents([.height(360), .medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var initial: String {
        String(active.name.prefix(1)).uppercased()
    }

    private func modeLabel(_ m: Mode) -> String {
        switch m {
        case .build:   return "Build"
        case .circuit: return "Circuit"
        }
    }

    @ViewBuilder
    private var sheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Whose device is this?")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.text)
            ForEach(profiles) { p in
                PressableCard(action: {
                    onSelect(p)
                    showSheet = false
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(theme.text)
                            Text(modeLabel(p.mode))
                                .font(.caption).tracking(2)
                                .foregroundStyle(theme.dim)
                        }
                        Spacer()
                        if p.id == active.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(theme.accent)
                        }
                    }
                }
            }
            Button {
                showSheet = false
                onAddProfile()
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("Add profile")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tactile(.secondary, fullWidth: true)
            Button {
                showSheet = false
                onOpenSettings()
            } label: {
                HStack {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tactile(.ghost)
            Spacer()
        }
        .padding(20)
        .background(theme.bg.ignoresSafeArea())
        .themed(active.mode)
    }
}
