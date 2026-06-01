import SwiftUI
import SwiftData

struct SettingsView: View {
    let profile: ProfileDTO
    @ObservedObject var health: HealthKitService

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    @State private var showModeSwitch = false

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
                                        .font(.caption).foregroundStyle(theme.dim2)
                                }
                                Spacer()
                                Image(systemName: profile.healthGranted ? "checkmark.circle.fill" : "heart.text.square")
                                    .foregroundStyle(theme.accent)
                            }
                        }
                    }

                    section("Mode") {
                        modeRow
                    }

                    section("Profile") {
                        labeled("Name", profile.name)
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
        .sheet(isPresented: $showModeSwitch) {
            // Themed to the destination mode so the sheet previews the palette
            // you're switching into.
            ModeSwitchSheet(profile: profile, onConfirm: switchMode)
                .themed(profile.mode.toggled)
        }
    }

    @ViewBuilder
    private var modeRow: some View {
        PressableCard(action: { showModeSwitch = true }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.mode.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.text)
                    Text("Tap to switch to \(profile.mode.toggled.displayName)")
                        .font(.caption).foregroundStyle(theme.dim2)
                }
                Spacer()
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(theme.accent)
            }
        }
    }

    private func switchMode(to newMode: Mode) {
        guard Repos.updateMode(ctx, profileId: profile.id, to: newMode) != nil else { return }
        Haptics.success()
        toasts.show(Toast(title: "Switched to \(newMode.displayName)",
                          detail: "Targets recomputed. Your logs are kept.",
                          accent: .win, symbol: "checkmark.circle.fill"))
        showModeSwitch = false
    }

    private func connectHealth() {
        if profile.healthGranted {
            health.openSystemSettings()
        } else {
            Task {
                let ok = await health.connectAndPersist(profileId: profile.id, ctx: ctx, toasts: toasts)
                // RootView's .task(id: StepObserverKey) re-fires on grant transition and arms the observer.
                if ok {
                    // Pull whatever Health already has so Progress fills immediately.
                    await health.syncFromHealth(profileId: profile.id, ctx: ctx)
                }
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
            Text(k).foregroundStyle(theme.dim2)
            Spacer()
            Text(v).foregroundStyle(theme.text)
        }
        .padding(10)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }
}

// MARK: - Mode switch sheet

/// Confirms an at-will Build↔Circuit switch, previewing how the recomputed
/// targets shift before applying. Targets come straight from Targets.compute so
/// the preview matches exactly what Repos.updateMode will persist.
private struct ModeSwitchSheet: View {
    let profile: ProfileDTO
    let onConfirm: (Mode) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    private var newMode: Mode { profile.mode.toggled }

    private var current: MacroTargets { Targets.compute(mode: profile.mode, vitals: profile.vitals) }
    private var next: MacroTargets { Targets.compute(mode: newMode, vitals: profile.vitals) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("switch mode.")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("\(profile.mode.displayName.uppercased()) → \(newMode.displayName.uppercased())")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }

                Text(newMode.blurb)
                    .font(.callout).foregroundStyle(theme.dim)

                VStack(alignment: .leading, spacing: 8) {
                    Text("What changes")
                        .font(.caption).tracking(2).textCase(.uppercase)
                        .foregroundStyle(theme.dim)
                    compareRow("Calories", "\(current.calories)", "\(next.calories)", "cal")
                    compareRow("Protein", "\(current.proteinG)", "\(next.proteinG)", "g")
                    compareRow("Steps", current.stepsDaily.formatted(), next.stepsDaily.formatted(), "/day")
                }

                Text(newMode == .circuit
                     ? "Circuit adds the parenting movements (Lifted Baby, Stroller, Carried Baby) to your exercises and folds your workout log into Today."
                     : "Build brings back the Train tab for your own lifts and the rep counter.")
                    .font(.footnote).foregroundStyle(theme.dim)

                Text("Your food, workout, and body logs are kept exactly as they are.")
                    .font(.footnote).foregroundStyle(theme.dim)

                Button {
                    onConfirm(newMode)
                } label: {
                    Text("Switch to \(newMode.displayName)").frame(maxWidth: .infinity)
                }
                .tactile(.primary, fullWidth: true)

                Button { dismiss() } label: { Text("Cancel") }
                    .tactile(.ghost)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.bg)
    }

    @ViewBuilder
    private func compareRow(_ label: String, _ from: String, _ to: String, _ unit: String) -> some View {
        HStack {
            Text(label).foregroundStyle(theme.text).font(.callout)
            Spacer()
            Text(from)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(theme.dim)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(theme.dim)
            Text(to)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(theme.accent)
            Text(unit).font(.caption).foregroundStyle(theme.dim)
        }
        .padding(10)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }
}
