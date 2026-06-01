// Top-level shell. User-created profiles; first launch routes to creation.
// Theme follows the active profile's mode. Overlays the toast host.
//
// Tab layout is mode-dependent:
//   Build:   Today | Meals | Train | Progress
//   Circuit: Today | Meals | Progress   (Train is absorbed into Today)

import SwiftUI
import SwiftData

private enum Tab: String, CaseIterable, Identifiable {
    case today, meals, workouts, progress
    var id: String { rawValue }

    var label: String {
        switch self {
        case .today:    return "Today"
        case .meals:    return "Meals"
        case .workouts: return "Train"
        case .progress: return "Progress"
        }
    }

    var icon: String {
        switch self {
        case .today:    return "sun.max"
        case .meals:    return "fork.knife"
        case .workouts: return "dumbbell"
        case .progress: return "chart.line.uptrend.xyaxis"
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
        guard let uuid = UUID(uuidString: activeProfileIdString) else {
            return profiles.first
        }
        return profiles.first(where: { $0.id == uuid }) ?? profiles.first
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
            ProfileCreationView { dto in
                activeProfileIdString = dto.id.uuidString
                Haptics.success()
                toasts.show(Toast(title: "Welcome, \(dto.name).",
                                  detail: "Targets locked. Let's go.",
                                  accent: .win, symbol: "checkmark.seal.fill"),
                            for: 2.4)
            }
        } else if let active {
            appShell(for: active)
                .id(active.id)
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
                    .tag(Tab.meals)
                    .tabItem { Label(Tab.meals.label, systemImage: Tab.meals.icon) }

                // Train tab only for Build — Circuit workout content lives in Today
                if profile.mode == .build {
                    WorkoutsView(profile: profile)
                        .tag(Tab.workouts)
                        .tabItem { Label(Tab.workouts.label, systemImage: Tab.workouts.icon) }
                }

                ProgressTabView(profile: profile, health: health)
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
        .onChange(of: profile.mode) { _, _ in
            // If switching from Build → Circuit while on the Train tab, land on Today
            if tab == .workouts { tab = .today }
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
            ProfileAvatar(profile: profile, onTap: { showSettings = true })
            Text("our-fitness.")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.text)
            Spacer()
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
