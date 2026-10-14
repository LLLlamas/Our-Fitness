// Entry point for the OurFitnessWatch companion app.
//
// Thin client: all state comes from WatchSyncStore, which syncs with the
// phone over WatchConnectivity (see WatchSyncStore.swift). No local
// SwiftData store, no iOS Theme/Card system -- plain native watchOS SwiftUI.
//
// Four tabs mirroring the phone's shell, minus what makes no sense on a
// wrist: Today (glance + water quick-log), Train (quick sets + live
// session), Meals (one-tap shortcuts), Reminders. Each tab owns its own
// NavigationStack so pushing a detail on one tab never disturbs another.

import SwiftUI

@main
struct OurFitnessWatchApp: App {
    @StateObject private var store = WatchSyncStore.shared
    @State private var selection: Tab = .today

    private enum Tab: Hashable {
        case today, train, meals, reminders
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selection) {
                NavigationStack { WatchTodayView() }
                    .tag(Tab.today)

                NavigationStack { WatchTrainView() }
                    .tag(Tab.train)

                NavigationStack { WatchMealsView() }
                    .tag(Tab.meals)

                NavigationStack { ReminderListView() }
                    .tag(Tab.reminders)
            }
            .environmentObject(store)
        }
    }
}
