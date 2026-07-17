// Local notification scheduling + actionable delegate for the Reminders tab.
//
// One pending UNNotificationRequest per reminder, identifier "reminder.<uuid>",
// firing via a calendar trigger at the reminder's due day + the profile's
// preferred hour. Two categories carry action buttons ("Watered ✓"/"Done ✓"
// and "Snooze 1 day") that work from the lock screen AND a mirrored Apple
// Watch notification without unlocking the phone — no watch app is needed for
// that path (see docs/watch-app-setup.md for the full watch companion app).
//
// Authorization is requested ONLY from an explicit user action (Add-reminder
// save, or the in-tab "turn on reminders" banner) — never from .onAppear/.task.
// This mirrors the documented HealthKit crash-trap rule and the existing
// LiveSessionNotifier pattern (Services/LiveSessionService.swift).

import Foundation
import UserNotifications
import SwiftData

extension Notification.Name {
    /// Posted when the user taps a delivered reminder notification's body (not
    /// an action button). RootView listens and switches to the Reminders tab.
    public static let openRemindersTab = Notification.Name("openRemindersTab")
}

@MainActor
public enum ReminderNotificationService {

    public static let plantCategoryId = "PLANT_WATER"
    public static let customCategoryId = "REMINDER_DONE"
    public static let doneActionId = "REMINDER_DONE_ACTION"
    public static let snoozeActionId = "REMINDER_SNOOZE_ACTION"

    public static let defaultPreferredHour = ReminderSchedule.defaultReminderHour
    private static let hourKeyPrefix = "reminderHour."
    private static let globalEnabledKey = "reminders.enabled"
    private static let identifierPrefix = "reminder."

    // MARK: - Setup

    /// Registers both notification categories. Safe to call unconditionally on
    /// every launch — registering categories never prompts for permission.
    public static func registerCategories() {
        let done = UNNotificationAction(identifier: doneActionId, title: "Watered ✓", options: [])
        let snooze = UNNotificationAction(identifier: snoozeActionId, title: "Snooze 1 day", options: [])
        let plantCategory = UNNotificationCategory(
            identifier: plantCategoryId, actions: [done, snooze],
            intentIdentifiers: [], options: []
        )

        let customDone = UNNotificationAction(identifier: doneActionId, title: "Done ✓", options: [])
        let customCategory = UNNotificationCategory(
            identifier: customCategoryId, actions: [customDone, snooze],
            intentIdentifiers: [], options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([plantCategory, customCategory])
    }

    /// CALL ONLY FROM AN EXPLICIT USER ACTION. Returns whether notifications
    /// are permitted; a `false` must NOT block adding/using reminders — it
    /// just means no ping (the tab's Due section still works).
    @discardableResult
    public static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default:
            return false
        }
    }

    // MARK: - Preferences

    /// Per-profile preferred hour (0-23) for reminder notifications. Backed by
    /// the same UserDefaults key SettingsView's `@AppStorage("reminderHour.<uuid>")` writes.
    public static func preferredHour(for userId: UUID) -> Int {
        let key = hourKeyPrefix + userId.uuidString
        guard let stored = UserDefaults.standard.object(forKey: key) as? Int else { return defaultPreferredHour }
        return stored
    }

    /// Global on/off toggle, defaulting to true when never set (mirrors the
    /// existing `nudge.*.enabled` keys' default-true behavior — a plain
    /// `.bool(forKey:)` would incorrectly read false for an absent key).
    public static func remindersGloballyEnabled() -> Bool {
        (UserDefaults.standard.object(forKey: globalEnabledKey) as? Bool) ?? true
    }

    // MARK: - Scheduling

    private static func identifier(for reminderId: UUID) -> String { identifierPrefix + reminderId.uuidString }

    /// Parses a scheduled request's identifier back into the reminder id it
    /// was scheduled for, or nil if the identifier isn't one of ours.
    /// Centralizes the "reminder.<uuid>" format so nothing else (notably
    /// `AppNotificationDelegate`) re-derives it independently.
    static func reminderId(fromIdentifier id: String) -> UUID? {
        guard id.hasPrefix(identifierPrefix) else { return nil }
        return UUID(uuidString: String(id.dropFirst(identifierPrefix.count)))
    }

    /// (Re)schedules the single pending notification for one reminder, based on
    /// its current interval/last-completion/snooze state. Call after every
    /// mutation: add, edit, delete (paired with `cancel`), done, snooze.
    ///
    /// Deliberately does NOT check authorization status first (unlike
    /// `reconcile`, which is the periodic "is this worth doing" sweep) —
    /// mirrors `LiveSessionNotifier.schedule`: an unauthorized `add()` is a
    /// harmless no-op (the request just never fires) until the user grants
    /// permission, at which point the next `reconcile()` picks it up. This
    /// also keeps the function synchronous, so it stays safe to call directly
    /// on `ctx` from `@MainActor` UI code without hopping through a
    /// non-isolated completion-handler closure.
    public static func reschedule(_ ctx: ModelContext, reminderId: UUID) {
        guard remindersGloballyEnabled(), let reminder = Repos.reminder(ctx, id: reminderId) else {
            cancel(ids: [reminderId])
            return
        }
        let center = UNUserNotificationCenter.current()
        let id = identifier(for: reminderId)
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])

        let lastDone = Repos.lastReminderEvent(ctx, reminderId: reminderId)?.timestamp
        let dueDay = ReminderSchedule.nextDueDay(
            lastDone: lastDone, createdAt: reminder.createdAt,
            intervalDays: reminder.intervalDays, snoozedUntil: reminder.snoozedUntil
        )
        let hour = preferredHour(for: reminder.userId)
        let fireDate = ReminderSchedule.fireDate(dueDay: dueDay, preferredHour: hour)

        let isPlant = Repos.reminderGroup(ctx, id: reminder.groupId)?.kind == .plants

        let content = UNMutableNotificationContent()
        content.sound = .default
        content.threadIdentifier = reminder.groupId.uuidString
        content.userInfo = ["reminderId": reminderId.uuidString]

        if isPlant {
            content.categoryIdentifier = plantCategoryId
            content.title = "Time to water \(reminder.name)"
            var body = ""
            if let amount = reminder.amountFlOz {
                body += "About \(Int(amount.rounded())) fl oz — \(PlantCatalog.drainageCopy)."
            } else {
                body += "Check the soil and water if it's dry — \(PlantCatalog.drainageCopy)."
            }
            if let room = reminder.room, !room.isEmpty {
                body += " (\(room))"
            }
            content.body = body
        } else {
            content.categoryIdentifier = customCategoryId
            content.title = reminder.name
            var body = "Every \(reminder.intervalDays) days."
            if let notes = reminder.notes, !notes.isEmpty {
                body += " \(notes)"
            }
            content.body = body
        }

        var comps = Calendar.current.dateComponents([.year, .month, .day, .hour], from: fireDate)
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }

    /// Cancels the pending + delivered notification for each id. Call
    /// alongside `Repos.deleteReminder` / `Repos.deleteReminderGroup`.
    public static func cancel(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let identifiers = ids.map(identifier(for:))
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    /// Silent reconcile: prunes pending requests for reminders that no longer
    /// exist or belong to a different profile, then reschedules every reminder
    /// owned by `userId`. Never requests authorization — checks settings only.
    /// Call on `scenePhase == .active` and right after a permission grant.
    public static func reconcile(_ ctx: ModelContext, userId: UUID) async {
        guard remindersGloballyEnabled() else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral else { return }

        let reminders = Repos.listReminders(ctx, userId: userId)
        let validIds = Set(reminders.map(\.id))

        let pending = await center.pendingNotificationRequests()
        let staleIds: [String] = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
            .filter { idStr in
                guard let uuid = reminderId(fromIdentifier: idStr) else { return true }
                return !validIds.contains(uuid)
            }
        if !staleIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIds)
        }

        for reminder in reminders {
            reschedule(ctx, reminderId: reminder.id)
        }
    }

    // MARK: - Mutation coordinators
    //
    // Every reminder mutation needs the same follow-up: reschedule its
    // notification and push a fresh snapshot to the watch. These bundle that
    // sequence in one place so the UI, the notification-action delegate below,
    // and WatchSyncService's wrist-action handler all go through the same
    // path instead of re-assembling it independently at each call site.

    /// The reschedule+watch-push pair every mutation needs. Exposed publicly
    /// for call sites (like AddReminderSheet.save) that make their own Repos
    /// calls but still need to end with this same sync step.
    public static func syncAfterChange(_ ctx: ModelContext, reminderId: UUID, userId: UUID) {
        reschedule(ctx, reminderId: reminderId)
        WatchSyncService.shared.pushSnapshot(ctx, userId: userId)
    }

    /// Logs a completion (now, or at `date` for backdating) and syncs.
    @discardableResult
    public static func logDone(_ ctx: ModelContext, reminderId: UUID, date: Date = Date()) -> ReminderDTO? {
        guard let reminder = Repos.reminder(ctx, id: reminderId) else { return nil }
        Repos.logReminderDone(ctx, ReminderEventDTO(
            userId: reminder.userId, reminderId: reminderId,
            date: Dates.dayKey(date), amountFlOz: reminder.amountFlOz, timestamp: date
        ))
        syncAfterChange(ctx, reminderId: reminderId, userId: reminder.userId)
        return reminder
    }

    /// Snoozes to tomorrow at the profile's preferred hour and syncs.
    @discardableResult
    public static func snooze(_ ctx: ModelContext, reminderId: UUID) -> ReminderDTO? {
        guard let reminder = Repos.reminder(ctx, id: reminderId) else { return nil }
        let until = ReminderSchedule.snoozeDate(preferredHour: preferredHour(for: reminder.userId))
        Repos.snoozeReminder(ctx, id: reminderId, until: until)
        syncAfterChange(ctx, reminderId: reminderId, userId: reminder.userId)
        return reminder
    }

    /// Applies a full-fidelity `ReminderDTO` update (interval/amount/room/etc.) and syncs.
    public static func update(_ ctx: ModelContext, _ updated: ReminderDTO) {
        Repos.updateReminder(ctx, updated)
        syncAfterChange(ctx, reminderId: updated.id, userId: updated.userId)
    }

    /// Cancels the notification, deletes the reminder (cascading its events),
    /// and pushes the watch snapshot so the deletion shows up there too.
    public static func remove(_ ctx: ModelContext, reminderId: UUID, userId: UUID) {
        cancel(ids: [reminderId])
        Repos.deleteReminder(ctx, id: reminderId)
        WatchSyncService.shared.pushSnapshot(ctx, userId: userId)
    }
}

/// Handles taps on notification action buttons ("Watered ✓" / "Done ✓" /
/// "Snooze 1 day") and the notification body, including when they wake the
/// app from a fully-terminated state (the action is what launches the
/// process — `container` is set in `OurFitnessApp.init()`, which always runs
/// before this delegate is invoked).
final class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationDelegate()
    var container: ModelContainer?

    private override init() { super.init() }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let requestId = response.notification.request.identifier
        let actionId = response.actionIdentifier
        Task { @MainActor in
            defer { completionHandler() }
            guard let container,
                  let reminderId = ReminderNotificationService.reminderId(fromIdentifier: requestId)
            else { return }

            let ctx = container.mainContext
            guard Repos.reminder(ctx, id: reminderId) != nil else {
                center.removeDeliveredNotifications(withIdentifiers: [requestId])
                return
            }

            switch actionId {
            case ReminderNotificationService.doneActionId:
                ReminderNotificationService.logDone(ctx, reminderId: reminderId)
            case ReminderNotificationService.snoozeActionId:
                ReminderNotificationService.snooze(ctx, reminderId: reminderId)
            case UNNotificationDefaultActionIdentifier:
                NotificationCenter.default.post(name: .openRemindersTab, object: nil)
            default:
                break
            }
        }
    }

    /// Only reminder notifications bannered in foreground; every other
    /// notification (e.g. the live-session end ping) keeps today's behavior of
    /// no delegate handling it, so it stays silent in foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if ReminderNotificationService.reminderId(fromIdentifier: notification.request.identifier) != nil {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([])
        }
    }
}
