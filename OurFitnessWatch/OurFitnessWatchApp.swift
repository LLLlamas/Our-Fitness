// Entry point for the OurFitnessWatch companion app.
//
// Thin client: all state comes from WatchReminderStore, which syncs with the
// phone over WatchConnectivity (see WatchReminderStore.swift). No local
// SwiftData store, no iOS Theme/Card system -- plain native watchOS SwiftUI.

import SwiftUI

@main
struct OurFitnessWatchApp: App {
    @StateObject private var store = WatchReminderStore.shared

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ReminderListView()
            }
            .environmentObject(store)
        }
    }
}
