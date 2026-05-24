// Top-level shell. Gates on whether any profile exists.
// Switches theme based on active profile's mode.
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
    @State private var showAddProfile = false

    private var profiles: [ProfileDTO] { profileModels.map(\.snapshot) }

    private var active: ProfileDTO? {
        if let uuid = UUID(uuidString: activeProfileIdString),
           let p = profiles.first(where: { $0.id == uuid }) {
            return p
        }
        return profiles.first
    }

    var body: some View {
        ZStack {
            content
            ToastHost()
                .themed(active?.mode ?? .build)
        }
        .task { await health.requestAuthorization() }
    }

    @ViewBuilder
    private var content: some View {
        if profiles.isEmpty || showAddProfile {
            OnboardingView { dto in
                Repos.saveProfile(ctx, dto)
                activeProfileIdString = dto.id.uuidString
                showAddProfile = false
                Task { await health.requestAuthorization() }
                Haptics.success()
                toasts.show(Toast(title: "Welcome, \(dto.name).",
                                  detail: "Targets locked. Let's go.",
                                  accent: .win, symbol: "checkmark.seal.fill"),
                            for: 2.4)
            }
            .themed(active?.mode ?? .build)
        } else if let active {
            appShell(for: active)
        } else {
            SwiftUI.ProgressView()
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
    }

    @ViewBuilder
    private func header(for profile: ProfileDTO) -> some View {
        let theme = Theme.for(profile.mode)
        HStack(spacing: 8) {
            Text("our-fitness.")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.text)
            Spacer()

            ForEach(profiles) { p in
                Button {
                    activeProfileIdString = p.id.uuidString
                } label: {
                    Text("\(p.name) · \(p.mode.rawValue)")
                }
                .tactile(.pill, fill: p.id == profile.id ? theme.accent : nil)
            }

            if profiles.count < 2 {
                Button { showAddProfile = true } label: { Text("+ Add") }
                    .tactile(.pill)
            }
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
