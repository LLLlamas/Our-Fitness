import SwiftUI
import SwiftData

struct SettingsView: View {
    let profile: ProfileDTO
    @ObservedObject var health: HealthKitService

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("settings.")
                        .font(.system(size: 48, weight: .regular))
                        .foregroundStyle(theme.text)

                    section("Apple Health") {
                        PressableCard(action: connectHealth) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(HealthAccess.statusLabel(healthGranted: profile.healthGranted))
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(theme.text)
                                    Text(profile.healthGranted
                                         ? "Tap to manage per-metric toggles in Settings.app"
                                         : "Tap to grant access")
                                        .font(.caption).foregroundStyle(theme.dim)
                                }
                                Spacer()
                                Image(systemName: profile.healthGranted ? "checkmark.circle.fill" : "heart.text.square")
                                    .foregroundStyle(theme.accent)
                            }
                        }
                    }

                    section("Profile") {
                        labeled("Name", profile.name)
                        labeled("Mode", modeLabel(profile.mode))
                        labeled("Activity", profile.activity.label)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .background(theme.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tactile(.ghost)
                }
            }
        }
        .themed(profile.mode)
    }

    private func modeLabel(_ m: Mode) -> String {
        switch m {
        case .build:   return "Build"
        case .circuit: return "Circuit"
        }
    }

    private func connectHealth() {
        if profile.healthGranted {
            health.openSystemSettings()
        } else {
            Task {
                _ = await health.connectAndPersist(profileId: profile.id, ctx: ctx, toasts: toasts)
                // RootView's .task(id: StepObserverKey) re-fires on grant transition and arms the observer.
            }
        }
    }

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10)).tracking(2)
                .foregroundStyle(theme.dim)
            content()
        }
    }

    @ViewBuilder
    private func labeled(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(theme.dim)
            Spacer()
            Text(v).foregroundStyle(theme.text)
        }
        .padding(10)
        .background(theme.card)
        .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
    }
}
