// Top-level shell. User-created profiles; first launch routes to creation.
// One light theme for everyone. Overlays the toast host.
//
// Tab layout (same for every goal): Today | Meals | Train | Progress

import SwiftUI
import SwiftData

private enum Tab: String, CaseIterable, Identifiable {
    case today, meals, workouts, progress
    var id: String { rawValue }

    var label: String {
        switch self {
        case .today:     return "Today"
        case .meals:     return "Meals"
        case .workouts:  return "Train"
        case .progress:  return "Progress"
        }
    }

    var icon: String {
        switch self {
        case .today:     return "sun.max"
        case .meals:     return "fork.knife"
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
    @State private var showSaveError = false
    @Environment(\.scenePhase) private var scenePhase

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
            // App-wide water quick-log button (tap = repeat last, hold = radial picker).
            // Only with an active profile, so it stays off the creation screen.
            if let active {
                WaterQuickLogButton(profile: active)
                    .id(active.id)
            }
            ToastHost()
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryWriteFailed)) { _ in
            showSaveError = true
        }
        .alert("Couldn't save your change", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The change wasn't saved. Please try again. If this continues, check available device storage. An unfinished live session remains available to retry.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if profiles.isEmpty {
            ProfileCreationView { dto in
                activeProfileIdString = dto.id.uuidString
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

                WorkoutsView(profile: profile)
                    .tag(Tab.workouts)
                    .tabItem { Label(Tab.workouts.label, systemImage: Tab.workouts.icon) }

                ProgressTabView(profile: profile)
                    .tag(Tab.progress)
                    .tabItem { Label(Tab.progress.label, systemImage: Tab.progress.icon) }
            }
            .tint(Theme.standard.accent)
            .sensoryFeedback(.selection, trigger: tab)
        }
        .background(Theme.standard.bg.ignoresSafeArea())
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
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            // Rolls the meal-nudge window forward a day and catches permission
            // changes made in iOS Settings.
            Task { await MealReminderService.replan(ctx, userId: profile.id) }
            WatchSyncService.shared.pushSnapshot(ctx, userId: profile.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMealsTab)) { _ in
            tab = .meals
        }
    }

    @ViewBuilder
    private func header(for profile: ProfileDTO) -> some View {
        let theme = Theme.standard
        HStack(spacing: 10) {
            ProfileAvatar(profile: profile, onTap: { showSettings = true })
            Text("Our Fitness")
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
    }
}
