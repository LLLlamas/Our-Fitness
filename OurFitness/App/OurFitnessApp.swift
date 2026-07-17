// @main entry. Sets up the SwiftData container, runs seeder once per launch,
// pre-warms haptic generators, injects ToastCenter, wires the Reminders
// notification delegate + watch sync.

import SwiftUI
import SwiftData
import UserNotifications

@main
struct OurFitnessApp: App {
    let container: ModelContainer
    @StateObject private var toasts = ToastCenter()

    init() {
        self.container = AppModelContainer.make()
        Seeder.seedAll(container.mainContext)

        // Registering categories never prompts; the actual authorization
        // request only ever fires from an explicit user action elsewhere
        // (Add-reminder save, the in-tab banner) — see ReminderNotificationService.
        AppNotificationDelegate.shared.container = container
        UNUserNotificationCenter.current().delegate = AppNotificationDelegate.shared
        ReminderNotificationService.registerCategories()
        WatchSyncService.shared.activate(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
                .environmentObject(toasts)
                .task { Haptics.prepare() }   // cut first-tap latency to ~0
        }
    }
}
