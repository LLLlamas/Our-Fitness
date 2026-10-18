// @main entry. Sets up the SwiftData container, runs seeder once per launch,
// pre-warms haptic generators, injects ToastCenter, wires the notification
// delegate + watch sync.

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

        // Authorization is only ever requested from an explicit user action
        // (the meal-reminders Settings toggle) — see MealReminderService.
        UNUserNotificationCenter.current().delegate = AppNotificationDelegate.shared
        // One-time: clear notifications left over from the removed Reminders tab.
        RetiredReminderCleanup.runOnce()
        WatchSyncService.shared.activate(container: container)
        // Observes saves to re-plan meal-logging nudges; never prompts.
        MealReminderService.shared.activate(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
                .modelContainer(container)
                .environmentObject(toasts)
                .task { Haptics.prepare() }   // cut first-tap latency to ~0
        }
    }
}
