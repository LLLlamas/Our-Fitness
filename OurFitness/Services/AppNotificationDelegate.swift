// Notification-center delegate + the one-time cleanup of the retired Reminders
// tab's notifications (see docs/removed-reminders.md).
//
// The only notifications the app still owns are meal-logging nudges
// (MealReminderService, ids "mealLog.*") and the live-session end ping
// (LiveSessionService). Neither carries action buttons.

import Foundation
import UserNotifications

/// Handles taps on notification bodies, including when they wake the app from
/// a fully-terminated state.
///
/// `@MainActor` with `nonisolated` delegate methods (the WatchSyncService
/// pattern): nothing here is shared mutable state across actors.
@MainActor
final class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationDelegate()

    private override init() { super.init() }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let requestId = response.notification.request.identifier
        let actionId = response.actionIdentifier
        Task { @MainActor in
            defer { completionHandler() }
            // Meal-logging nudges carry no action buttons; a body tap opens
            // the Meals tab.
            if MealReminderService.isMealIdentifier(requestId),
               actionId == UNNotificationDefaultActionIdentifier {
                NotificationCenter.default.post(name: .openMealsTab, object: nil)
            }
        }
    }

    /// Nothing is bannered in the foreground: with the app open, the in-app
    /// meal toast already covers a meal nudge, and the live-session end ping
    /// has always stayed silent while the app is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }
}

/// Reminders (plants, generic, medication) were removed from the app. Installs
/// that updated from a build that had them still have pending repeating
/// alarms ("reminder.<uuid>#<minute>") registered with iOS, and those would
/// keep firing with no way to act on them. This clears them once.
enum RetiredReminderCleanup {
    private static let doneKey = "retiredReminders.notificationCleanup.v1"
    /// Identifier prefix the removed ReminderNotificationService used. Meal
    /// nudges use "mealLog." and are untouched.
    private static let identifierPrefix = "reminder."

    /// Call once from `OurFitnessApp.init()`. Never prompts for permission.
    static func runOnce() {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        let center = UNUserNotificationCenter.current()
        // The action-button categories (plant / custom / medication) died with
        // the feature. Nothing else registers categories.
        center.setNotificationCategories([])
        Task {
            let pending = await center.pendingNotificationRequests()
                .map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
            if !pending.isEmpty { center.removePendingNotificationRequests(withIdentifiers: pending) }
            let delivered = await center.deliveredNotifications()
                .map(\.request.identifier).filter { $0.hasPrefix(identifierPrefix) }
            if !delivered.isEmpty { center.removeDeliveredNotifications(withIdentifiers: delivered) }
            UserDefaults.standard.set(true, forKey: doneKey)
        }
    }
}
