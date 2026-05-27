// Top-level shell. Two seeded profiles; user picks one for this device on first launch.
// Theme follows the active profile's mode.
// Overlays the toast host so any view can fire a confirmation.

import SwiftUI
import SwiftData

private enum Tab: String, CaseIterable, Identifiable {
    case today, nutrition, workouts, progress
    var id: String { rawValue }

    var label: String {
        switch self {
        case .today:     return "Today"
        case .nutrition: return "Library"
        case .workouts:  return "Train"
        case .progress:  return "Progress"
        }
    }

    var icon: String {
        switch self {
        case .today:     return "sun.max"
        case .nutrition: return "fork.knife"
        case .workouts:  return "dumbbell"
        case .progress:  return "chart.line.uptrend.xyaxis"
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var ctx
    @EnvironmentObject private var toasts: ToastCenter
    @Query(sort: \ProfileModel.createdAt) private var profileModels: [ProfileModel]
    @AppStorage("activeProfileId") private var activeProfileIdString: String = ""
    @StateObject private var health = HealthKitService.shared

    @State private var tab: Tab = .today
    @State private var showSettings = false

    private var profiles: [ProfileDTO] { profileModels.map(\.snapshot) }

    private var active: ProfileDTO? {
        guard let uuid = UUID(uuidString: activeProfileIdString) else { return nil }
        // Falling through to nil here drops the user back into onboarding if their stored
        // UUID no longer matches a seeded profile (schema/ID change). Re-seed is idempotent
        // by name, so a future schema bump that re-keys profiles would otherwise strand them.
        return profiles.first(where: { $0.id == uuid })
    }

    private struct StepObserverKey: Hashable {
        let profileId: UUID
        let granted: Bool
    }

    var body: some View {
        ZStack {
            content
            ToastHost()
                .themed(active?.mode ?? .build)
        }
    }

    @ViewBuilder
    private var content: some View {
        if profiles.isEmpty {
            SwiftUI.ProgressView()
        } else if let active {
            appShell(for: active)
        } else {
            OnboardingView(profiles: profiles) { chosen, granted in
                activeProfileIdString = chosen.id.uuidString
                Repos.setHealthGranted(ctx, profileId: chosen.id, granted: granted)
                // Observer arm-up happens centrally in appShell's .task(id:) once the
                // grant flip is reflected in the re-rendered profile snapshot.
                Haptics.success()
                toasts.show(Toast(title: "Welcome, \(chosen.name).",
                                  detail: granted ? "Apple Health connected." : "Targets locked. Let's go.",
                                  accent: .win, symbol: "checkmark.seal.fill"),
                            for: 2.4)
            }
            .themed(active?.mode ?? .build)
        }
    }

    @ViewBuilder
    private func appShell(for profile: ProfileDTO) -> some View {
        VStack(spacing: 0) {
            header(for: profile)
            TabView(selection: $tab) {
                TodayView(profile: profile, health: health)
                    .tag(Tab.today)
                    .tabItem { Label(Tab.today.label, systemImage: Tab.today.icon) }

                NutritionView(profile: profile)
                    .tag(Tab.nutrition)
                    .tabItem { Label(Tab.nutrition.label, systemImage: Tab.nutrition.icon) }

                WorkoutsView(profile: profile)
                    .tag(Tab.workouts)
                    .tabItem { Label(Tab.workouts.label, systemImage: Tab.workouts.icon) }

                ProgressTabView(profile: profile)
                    .tag(Tab.progress)
                    .tabItem { Label(Tab.progress.label, systemImage: Tab.progress.icon) }
            }
            .tint(Theme.for(profile.mode).accent)
            .sensoryFeedback(.selection, trigger: tab)
        }
        .background(Theme.for(profile.mode).bg.ignoresSafeArea())
        .themed(profile.mode)
        .sheet(isPresented: $showSettings) {
            SettingsView(profile: profile, health: health)
        }
        .task(id: StepObserverKey(profileId: profile.id, granted: profile.healthGranted)) {
            if profile.healthGranted {
                health.beginStepObservation { steps in
                    Repos.setSteps(ctx, userId: profile.id, date: Dates.dayKey(),
                                   steps: steps, source: .appleHealth)
                }
            }
        }
    }

    @ViewBuilder
    private func header(for profile: ProfileDTO) -> some View {
        let theme = Theme.for(profile.mode)
        HStack(spacing: 10) {
            ProfileSwitcher(
                profiles: profiles,
                active: profile,
                onSelect: { activeProfileIdString = $0.id.uuidString },
                onOpenSettings: { showSettings = true }
            )
            Text("our-fitness.")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.text)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .tactile(.ghost)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(theme.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.line).frame(height: 1)
        }
        .themed(profile.mode)
    }
}
