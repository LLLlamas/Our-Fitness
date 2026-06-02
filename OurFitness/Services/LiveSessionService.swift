// Live Session persistence (UserDefaults) + local end-notification.
//
// The session is timestamp-anchored, NOT a running timer: iOS suspends a
// backgrounded app, so we never keep a clock ticking. We persist only the
// immutable `startDate` anchor + the plan (LiveSessionState lives in Domain);
// elapsed time is always recomputed as now − startDate, so the session correctly
// survives app-switching, backgrounding, and a full app kill + relaunch — on
// launch we read the persisted state back and resume the live screen.
//
// At the expected end we schedule ONE local notification. We do NOT add any
// background modes (no audio/location) — a UNTimeIntervalNotificationTrigger
// fires while the app is suspended or terminated with no entitlement. If the
// user denies notification permission the session still works fully; it just
// won't ping. Authorization is requested only from the explicit Start action —
// never from .onAppear/.task — mirroring the documented HealthKit crash-trap
// rule (an auto-request on launch is the kind of thing that bites us).

import Foundation
import UserNotifications

public enum LiveSessionStore {
    private static let key = "liveSession.active.v1"

    public static func load() -> LiveSessionState? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LiveSessionState.self, from: data)
    }

    public static func save(_ state: LiveSessionState) {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// The active session for this profile, or nil if none / it belongs to another
    /// profile (defensive — one profile per install today, but keeps resume scoped).
    public static func active(for profileId: UUID) -> LiveSessionState? {
        guard let s = load(), s.profileId == profileId else { return nil }
        return s
    }
}

/// Schedules / cancels the single "you hit your planned time" local notification.
@MainActor
public enum LiveSessionNotifier {
    private static let requestId = "liveSession.expectedEnd"

    /// Request authorization. CALL ONLY FROM AN EXPLICIT USER ACTION (tapping
    /// Start), never from .onAppear/.task. Returns whether notifications are
    /// permitted; a `false` must NOT block the session — it just means no ping.
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
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            return granted
        @unknown default:
            return false
        }
    }

    /// Schedule the notification for `expectedMinutes` from `from`. Replaces any
    /// existing pending request (so adjusting the expected time reschedules cleanly).
    /// No-op when the remaining time is non-positive (already past the plan).
    public static func schedule(activityName: String, expectedMinutes: Int, from: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestId])

        let fireDate = from.addingTimeInterval(Double(expectedMinutes) * 60)
        let remaining = fireDate.timeIntervalSinceNow
        guard remaining > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(activityName) session"
        content.body = "You hit your planned \(expectedMinutes) min — finish when you're ready, or keep going."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
        let request = UNNotificationRequest(identifier: requestId, content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }

    /// Cancel the pending end notification (session ended early or finished).
    public static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [requestId])
    }
}
