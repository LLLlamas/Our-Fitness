// Push notifications that remind the user to log a meal, timed from when they
// usually log it (Domain/MealLogPattern.swift — learning rule, grace, quiet
// hours and horizon all live there).
//
// Opt-in, default OFF, per profile: `mealReminders.enabled.<profile-uuid>`.
// Authorization is requested ONLY from the Settings toggle being turned on
// (`enable`) — never from .onAppear/.task (see ReminderNotificationService).
//
// One one-shot request per (meal day, slot), identifier
// `mealLog.<yyyy-MM-dd>.<slot>`, for today plus the next two days — at most 9
// pending, well clear of iOS's 64 and of the Reminders tab's requests. The
// prefix is deliberately NOT "reminder.": ReminderNotificationService.reconcile
// prunes every "reminder.*" id it doesn't own, and AppNotificationDelegate's
// willPresent banners only "reminder.*" — so a meal nudge stays silent while the
// app is open, where the in-app meal toast (TodayView) already covers it. That
// is the whole no-double-nag rule; nothing in TodayView needed to change.
//
// Re-planned (a cheap diff — unchanged requests are left alone):
//   - on every successful repository save (observes `.repositoryDidSave`,
//     coalesced), which covers food log add/edit/delete from every surface,
//     the watch included, without touching any logging call site;
//   - on foreground (RootView scenePhase), which rolls the 3-day window forward;
//   - when the Settings toggle changes.

import Foundation
import UserNotifications
import SwiftData

extension Notification.Name {
    /// Posted when the user taps a meal-logging notification's body. RootView
    /// listens and switches to the Meals tab.
    public static let openMealsTab = Notification.Name("openMealsTab")
}

@MainActor
final class MealReminderService {
    static let shared = MealReminderService()

    nonisolated static let identifierPrefix = "mealLog."
    private static let enabledKeyPrefix = "mealReminders.enabled."

    private var container: ModelContainer?
    private var saveObserver: NSObjectProtocol?
    private var replanTask: Task<Void, Never>?

    private init() {}

    // MARK: - Preferences

    static func enabledKey(for userId: UUID) -> String { enabledKeyPrefix + userId.uuidString }

    /// Default OFF: an absent key reads false.
    static func isEnabled(for userId: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: enabledKey(for: userId))
    }

    nonisolated static func isMealIdentifier(_ id: String) -> Bool {
        id.hasPrefix(identifierPrefix)
    }

    // MARK: - Lifecycle

    /// Call once from `OurFitnessApp.init()`. Never prompts.
    func activate(container: ModelContainer) {
        self.container = container
        guard saveObserver == nil else { return }
        saveObserver = NotificationCenter.default.addObserver(
            forName: .repositoryDidSave, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleReplan() }
        }
    }

    /// Coalesce save bursts (a meal with several ingredients, a seeder pass)
    /// into one re-plan of the active profile.
    private func scheduleReplan() {
        replanTask?.cancel()
        replanTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, let container = self.container else { return }
            let ctx = container.mainContext
            guard let userId = Self.activeProfileId(ctx) else { return }
            await Self.replan(ctx, userId: userId)
        }
    }

    /// Same resolution RootView uses (`activeProfileId` AppStorage, else first).
    private static func activeProfileId(_ ctx: ModelContext) -> UUID? {
        let profiles = Repos.listProfiles(ctx)
        if let stored = UserDefaults.standard.string(forKey: "activeProfileId"),
           let id = UUID(uuidString: stored),
           profiles.contains(where: { $0.id == id }) {
            return id
        }
        return profiles.first?.id
    }

    // MARK: - Toggle

    /// CALL ONLY FROM THE SETTINGS TOGGLE being switched on. Asks for
    /// permission if it hasn't been decided, then plans. Returns whether
    /// notifications are allowed — false leaves the toggle on but nothing fires.
    @discardableResult
    static func enable(_ ctx: ModelContext, userId: UUID) async -> Bool {
        let granted = await ReminderNotificationService.requestAuthorizationIfNeeded()
        await replan(ctx, userId: userId)
        return granted
    }

    // MARK: - Planning

    /// Brings pending meal requests in line with `MealLogPattern.plan`. Never
    /// requests authorization. Disabled → clears everything of ours.
    static func replan(_ ctx: ModelContext, userId: UUID) async {
        let center = UNUserNotificationCenter.current()
        guard isEnabled(for: userId) else {
            cancelAll()
            return
        }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral else { return }

        let now = Date()
        let calendar = Calendar.current
        let entries = recentEntries(ctx, userId: userId, now: now)
        let plan = MealLogPattern.plan(entries, now: now, calendar: calendar)
        let desired = plan.map { request(for: $0, calendar: calendar) }
        let desiredById = Dictionary(uniqueKeysWithValues: desired.map { ($0.identifier, $0) })

        let pending = await center.pendingNotificationRequests().filter { isMealIdentifier($0.identifier) }
        let pendingById = Dictionary(uniqueKeysWithValues: pending.map { ($0.identifier, $0) })

        let obsolete = pending.map(\.identifier).filter { desiredById[$0] == nil }
        if !obsolete.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: obsolete)
        }
        for request in desired {
            if let existing = pendingById[request.identifier], matches(existing, request) { continue }
            center.add(request, withCompletionHandler: nil)
        }

        // A delivered "lunch isn't logged yet" for a meal that now IS logged is
        // stale — clear it so Notification Center doesn't contradict the log.
        let loggedIds = Set(entries.map { identifier(dayKey: $0.date, slot: $0.slot) })
        let stale = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { loggedIds.contains($0) }
        if !stale.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: stale)
        }
    }

    /// Learned times for the Settings caption — empty while still learning.
    static func learnedTimes(_ ctx: ModelContext, userId: UUID) -> [(slot: Slot, minuteOfDay: Int)] {
        let now = Date()
        return MealLogPattern.learnedTimes(recentEntries(ctx, userId: userId, now: now),
                                           now: now, calendar: .current)
    }

    /// Removes every pending and delivered meal-logging notification.
    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter(isMealIdentifier)
            if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }
        }
        center.getDeliveredNotifications { delivered in
            let ids = delivered.map(\.request.identifier).filter(isMealIdentifier)
            if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
        }
    }

    // MARK: - Requests

    /// The lookback window plus today — one bounded fetch.
    private static func recentEntries(_ ctx: ModelContext, userId: UUID, now: Date) -> [FoodLogEntryDTO] {
        let window = Dates.lastNDays(MealLogPattern.lookbackDays + 1, end: now)
        guard let first = window.first, let last = window.last else { return [] }
        return Repos.foodLogs(ctx, userId: userId, inDayRange: first...last)
    }

    private static func identifier(dayKey: String, slot: Slot) -> String {
        "\(identifierPrefix)\(dayKey).\(slot.rawValue)"
    }

    /// Copy rule: says the meal isn't logged yet and invites a log. No guilt,
    /// no numbers, never "you skipped a meal" — the app only knows what was logged.
    private static func request(for nudge: MealLogPattern.Nudge, calendar: Calendar) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.threadIdentifier = "mealLog"
        let meal = nudge.slot.label
        content.title = "Log your \(meal)?"
        let clock = MedicationPattern.clockLabel(minuteOfDay: nudge.typicalMinuteOfDay, calendar: calendar)
        content.body = "You usually log \(meal) around \(clock), and it isn't logged yet today. A quick entry or an estimate is plenty."
        // Year/month/day/hour/minute: a one-shot at a real wall-clock time.
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: nudge.fireDate)
        return UNNotificationRequest(
            identifier: identifier(dayKey: nudge.dayKey, slot: nudge.slot),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        )
    }

    private static func matches(_ existing: UNNotificationRequest, _ desired: UNNotificationRequest) -> Bool {
        guard let a = (existing.trigger as? UNCalendarNotificationTrigger)?.dateComponents,
              let b = (desired.trigger as? UNCalendarNotificationTrigger)?.dateComponents else { return false }
        return (a.year, a.month, a.day, a.hour, a.minute) == (b.year, b.month, b.day, b.hour, b.minute)
            && existing.content.title == desired.content.title
            && existing.content.body == desired.content.body
    }
}
