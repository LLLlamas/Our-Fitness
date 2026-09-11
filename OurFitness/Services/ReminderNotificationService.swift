// Local notification scheduling + actionable delegate for the Reminders tab.
//
// One pending UNNotificationRequest per reminder, identifier "reminder.<uuid>",
// firing via a calendar trigger at the reminder's due day + the profile's
// preferred hour. Three categories carry action buttons ("Watered ✓"/"Done ✓"/
// "Log taken ✓" and "Snooze 1 day") that work from the lock screen AND a
// mirrored Apple Watch notification without unlocking the phone — no watch app
// is needed for that path (see docs/watch-app-setup.md for the full watch
// companion app).
//
// Medication is the exception to "due day + preferred hour": it has no
// interval and no snooze, and fires at a time inferred from the completion log
// (Domain/MedicationPattern.swift), so it is the one kind whose desired
// request can legitimately be *nothing at all*.
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
    public static let medicationCategoryId = "MED_LOG"
    public static let doneActionId = "REMINDER_DONE_ACTION"
    public static let snoozeActionId = "REMINDER_SNOOZE_ACTION"

    public static let defaultPreferredHour = ReminderSchedule.defaultReminderHour
    private static let hourKeyPrefix = "reminderHour."
    private static let globalEnabledKey = "reminders.enabled"
    // nonisolated: read from the nonisolated `reminderId(fromIdentifier:)` below
    // (mirrors the nonisolated static let precedent in HealthKitService.swift).
    nonisolated private static let identifierPrefix = "reminder."

    // MARK: - Setup

    /// Registers all three notification categories. Safe to call
    /// unconditionally on every launch — registering categories never prompts
    /// for permission.
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

        // Medication gets ONE action and no snooze: snoozing is interval
        // semantics ("push the due day out"), which a pattern-scheduled
        // medication has no concept of — a snoozedUntil written here would be
        // ignored by the scheduler. Reusing `doneActionId` rather than minting
        // a medication-specific identifier means AppNotificationDelegate needs
        // no new case: the tap logs a dose through the same logDone path.
        let medDone = UNNotificationAction(identifier: doneActionId, title: "Log taken ✓", options: [])
        let medicationCategory = UNNotificationCategory(
            identifier: medicationCategoryId, actions: [medDone],
            intentIdentifiers: [], options: []
        )

        UNUserNotificationCenter.current()
            .setNotificationCategories([plantCategory, customCategory, medicationCategory])
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

    /// `reminder.<uuid>` for a single request, `reminder.<uuid>#<minute>` for
    /// one of a medication's set-time alarms. The suffix is what lets several
    /// daily alarms coexist for the same medication; `reminderId(fromIdentifier:)`
    /// strips it, so every existing caller keeps working unchanged.
    private static func identifier(for reminderId: UUID, minuteOfDay: Int? = nil) -> String {
        let base = identifierPrefix + reminderId.uuidString
        guard let minuteOfDay else { return base }
        return "\(base)#\(minuteOfDay)"
    }

    /// Parses a scheduled request's identifier back into the reminder id it
    /// was scheduled for, or nil if the identifier isn't one of ours.
    /// Centralizes the "reminder.<uuid>" format so nothing else (notably
    /// `AppNotificationDelegate`) re-derives it independently. `nonisolated`
    /// because it's pure string parsing (no actor-isolated state) and is
    /// called from `willPresent`, a synchronous, non-isolated delegate method.
    nonisolated static func reminderId(fromIdentifier id: String) -> UUID? {
        guard id.hasPrefix(identifierPrefix) else { return nil }
        let body = id.dropFirst(identifierPrefix.count)
        let uuidPart = body.split(separator: "#", maxSplits: 1).first.map(String.init) ?? String(body)
        return UUID(uuidString: uuidPart)
    }

    /// Builds the desired pending request for one reminder from pre-fetched
    /// state — the single source of the identifier/content/trigger format
    /// shared by `reschedule` and `reconcile`.
    ///
    /// `recentEventTimes` is only read for `.medication` (which infers its fire
    /// time from the completion log); the interval kinds need `lastDone` alone.
    ///
    /// Returns nil when the reminder should have NO pending notification —
    /// today that is medication with the nudge switched off, or medication with
    /// no history to infer a routine from. Both callers must treat nil as
    /// "cancel whatever is pending", not as "leave it alone".
    private static func buildRequests(for reminder: ReminderDTO, kind: ReminderGroupKind,
                                      lastDone: Date?, recentEventTimes: [Date]) -> [UNNotificationRequest] {
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.threadIdentifier = reminder.groupId.uuidString
        content.userInfo = ["reminderId": reminder.id.uuidString]

        // Component set differs by kind, so each branch produces its own:
        // plants/custom fire on the hour, medication needs minute precision.
        var comps: DateComponents

        switch kind {
        case .medication:
            return medicationRequests(for: reminder, recentEventTimes: recentEventTimes)

        case .plants, .custom:
            let dueDay = ReminderSchedule.nextDueDay(
                lastDone: lastDone, createdAt: reminder.createdAt,
                intervalDays: reminder.intervalDays, snoozedUntil: reminder.snoozedUntil
            )
            let fireDate = ReminderSchedule.fireDate(dueDay: dueDay, preferredHour: preferredHour(for: reminder.userId))

            if kind == .plants {
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
                // intervalLabel, not interpolation — a daily reminder read
                // "Every 1 days" before, and it also gets us "Weekly"/"Yearly"
                // instead of raw day counts now that intervals reach 365.
                var body = ReminderSchedule.intervalLabel(days: reminder.intervalDays) + "."
                if let notes = reminder.notes, !notes.isEmpty {
                    body += " \(notes)"
                }
                content.body = body
            }

            comps = Calendar.current.dateComponents([.year, .month, .day, .hour], from: fireDate)
            comps.minute = 0
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return [UNNotificationRequest(identifier: identifier(for: reminder.id), content: content, trigger: trigger)]
    }

    /// A medication's pending notifications — several, when it has several set
    /// times.
    ///
    /// SET TIMES ARE DAILY REPEATING ALARMS: one request per time, `repeats:
    /// true` on an hour+minute trigger. That is the entire reliability story.
    /// The one-shot requests this used to build were re-armed only when the app
    /// ran, so a nudge ignored without opening the app was the LAST one that
    /// medication ever produced — silence from then on, for exactly the person
    /// least likely to notice. A repeating trigger is re-fired by iOS forever
    /// with no app involvement, and needs no fire instant, no grace period and
    /// no re-arm path, so it deletes that whole class of bug rather than
    /// patching it.
    ///
    /// With NO set times the inferred behaviour is unchanged: one one-shot
    /// request at the observed time plus grace (`MedicationPattern.nextFireDate`).
    private static func medicationRequests(for reminder: ReminderDTO,
                                           recentEventTimes: [Date]) -> [UNNotificationRequest] {
        guard reminder.patternReminderEnabled == true else { return [] }

        let times = reminder.scheduledMinutesOfDay
        if !times.isEmpty {
            return times.map { minute in
                // Hour and minute ONLY: no year/month/day, which is what makes
                // the trigger recur daily. The user picked the minute, so there
                // is deliberately no grace period here — 8:00 means 8:00.
                var comps = DateComponents()
                comps.hour = minute / 60
                comps.minute = minute % 60
                let clock = MedicationPattern.clockLabel(minuteOfDay: minute)
                return UNNotificationRequest(
                    identifier: identifier(for: reminder.id, minuteOfDay: minute),
                    content: medicationContent(
                        for: reminder,
                        body: "\(reminder.name) is set for \(clock). Tap to log this dose."
                    ),
                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                )
            }
        }

        guard let fireDate = MedicationPattern.nextFireDate(
            recentEventTimes, now: Date(), calendar: .current
        ) else { return [] }
        // Minute included (and never zeroed): the observed time is a real clock
        // time read off the user's own logs, so an 8:35 routine must not be
        // floored to 8:00 the way the on-the-hour kinds are.
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        return [UNNotificationRequest(
            identifier: identifier(for: reminder.id),
            content: medicationContent(
                for: reminder,
                body: "You usually log \(reminder.name) around this time. No log has been recorded yet today."
            ),
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        )]
    }

    /// SAFETY REQUIREMENT — DO NOT "IMPROVE" THIS COPY.
    ///
    /// The app only knows what has been LOGGED. It cannot tell a dose that was
    /// taken but not logged from one deliberately skipped from one a clinician
    /// changed or stopped. So a medication notification may only ever speak
    /// about the log or about a time the user themselves entered: never "take X
    /// now", never "you missed a dose", and never a dose amount in the body.
    /// Anything stronger turns a missing tap into medical instruction the app
    /// has no grounds to give.
    ///
    /// Note the set-time body says a time was SET and invites a log — it does
    /// not assert a dose is due, which a repeating alarm could not know anyway.
    private static func medicationContent(for reminder: ReminderDTO, body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = .default
        // Threaded per MEDICATION, not per group. Every medication lives in the
        // one built-in Medication group, so threading by group collapsed three
        // different doses into a single stack that is read and dismissed as one.
        content.threadIdentifier = reminder.id.uuidString
        content.userInfo = ["reminderId": reminder.id.uuidString]
        content.categoryIdentifier = medicationCategoryId
        content.title = "Medication reminder"
        content.body = body
        return content
    }

    /// Whether an already-pending request matches the desired one, so
    /// `reconcile` can leave it untouched.
    ///
    /// Minute is part of the comparison and both kinds supply it — the
    /// interval kinds as an explicit 0, medication as the real pattern minute
    /// — so a medication whose inferred time shifts by 20 minutes correctly
    /// reads as changed rather than matching on the hour alone.
    private static func matches(_ existing: UNNotificationRequest, _ desired: UNNotificationRequest) -> Bool {
        guard let a = (existing.trigger as? UNCalendarNotificationTrigger)?.dateComponents,
              let b = (desired.trigger as? UNCalendarNotificationTrigger)?.dateComponents else { return false }
        return (a.year, a.month, a.day, a.hour, a.minute) == (b.year, b.month, b.day, b.hour, b.minute)
            && existing.content.title == desired.content.title
            && existing.content.body == desired.content.body
            && existing.content.categoryIdentifier == desired.content.categoryIdentifier
            && existing.content.threadIdentifier == desired.content.threadIdentifier
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
        center.removeDeliveredNotifications(withIdentifiers: [identifier(for: reminderId)])

        let kind = Repos.reminderGroup(ctx, id: reminder.groupId)?.kind ?? .custom
        // Medication reads its fire time off the whole recent completion log,
        // so it needs the event list; the interval kinds only ever need the
        // latest event. Events come back newest-first, so `.first` is the same
        // value `lastReminderEvent` would return — medication still costs one
        // event fetch here, not two.
        let recentEventTimes: [Date] = kind == .medication
            ? Repos.reminderEvents(ctx, reminderId: reminderId, limit: 60).map(\.timestamp)
            : []
        let lastDone = kind == .medication
            ? recentEventTimes.first
            : Repos.lastReminderEvent(ctx, reminderId: reminderId)?.timestamp

        let requests = buildRequests(for: reminder, kind: kind,
                                     lastDone: lastDone, recentEventTimes: recentEventTimes)

        // Clear by REMINDER id, not by the identifiers we're about to add: a set
        // time the user just deleted still has an alarm pending under an
        // identifier the new list no longer mentions, and `add` only replaces
        // identifiers it collides with. An empty `requests` therefore cancels
        // everything, which is also the medication-switched-off case.
        center.getPendingNotificationRequests { pending in
            let mine = pending.map(\.identifier).filter { Self.reminderId(fromIdentifier: $0) == reminderId }
            if !mine.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: mine)
            }
            for request in requests {
                center.add(request, withCompletionHandler: nil)
            }
        }
    }

    /// Cancels the pending + delivered notifications for each id. Call
    /// alongside `Repos.deleteReminder` / `Repos.deleteReminderGroup`.
    ///
    /// Sweeps by reminder id rather than by exact identifier: a medication holds
    /// one repeating alarm per set time, under identifiers the call site has no
    /// way to enumerate — and a repeating alarm that outlived its medication
    /// would fire daily, forever, for something that no longer exists.
    public static func cancel(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let targets = Set(ids)
        let center = UNUserNotificationCenter.current()

        func isOurs(_ identifier: String) -> Bool {
            guard let id = reminderId(fromIdentifier: identifier) else { return false }
            return targets.contains(id)
        }

        center.getPendingNotificationRequests { requests in
            let matching = requests.map(\.identifier).filter(isOurs)
            if !matching.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: matching)
            }
        }
        center.getDeliveredNotifications { delivered in
            let matching = delivered.map(\.request.identifier).filter(isOurs)
            if !matching.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: matching)
            }
        }
    }

    /// Silent reconcile: prunes pending requests for reminders that no longer
    /// exist or belong to a different profile, then re-issues only reminders
    /// whose desired notification differs from the pending one — runs on every
    /// foreground, so unchanged reminders cost zero remove/add churn. Never
    /// requests authorization — checks settings only. Call on
    /// `scenePhase == .active` and right after a permission grant.
    public static func reconcile(_ ctx: ModelContext, userId: UUID) async {
        guard remindersGloballyEnabled() else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral else { return }

        // One fetch each of reminders/groups/events (events are newest-first,
        // so first-seen-wins folds to "latest per reminder") — not the 3
        // per-reminder fetches `reschedule` does.
        let reminders = Repos.listReminders(ctx, userId: userId)
        let validIds = Set(reminders.map(\.id))
        var kindByGroupId: [UUID: ReminderGroupKind] = [:]
        for g in Repos.listReminderGroups(ctx, userId: userId) { kindByGroupId[g.id] = g.kind }

        // Latest-per-reminder and full-history-per-reminder folded in the SAME
        // pass over the one events fetch. Medication needs the history to infer
        // its time; adding a per-reminder fetch for that would undo the
        // "one fetch each" property this whole sweep is built around.
        var lastDoneById: [UUID: Date] = [:]
        var eventTimesById: [UUID: [Date]] = [:]
        for e in Repos.listReminderEvents(ctx, userId: userId) {
            if lastDoneById[e.reminderId] == nil { lastDoneById[e.reminderId] = e.timestamp }
            eventTimesById[e.reminderId, default: []].append(e.timestamp)
        }

        let pending = await center.pendingNotificationRequests()
        let pendingById = Dictionary(uniqueKeysWithValues: pending.map { ($0.identifier, $0) })
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
            let desired = buildRequests(
                for: reminder,
                kind: kindByGroupId[reminder.groupId] ?? .custom,
                lastDone: lastDoneById[reminder.id],
                recentEventTimes: eventTimesById[reminder.id] ?? []
            )
            let desiredIds = Set(desired.map(\.identifier))

            // Anything still pending for this reminder that the desired set no
            // longer contains: a deleted set time, or the whole medication
            // switched off. These survive the stale-id prune above (the reminder
            // itself still exists), so they have to be dropped here. An empty
            // `desired` makes this the "cancel everything" path.
            let obsolete = pending
                .map(\.identifier)
                .filter { reminderId(fromIdentifier: $0) == reminder.id && !desiredIds.contains($0) }
            if !obsolete.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: obsolete)
            }

            for request in desired {
                if let existing = pendingById[request.identifier], matches(existing, request) { continue }
                center.removeDeliveredNotifications(withIdentifiers: [request.identifier])
                center.add(request, withCompletionHandler: nil)
            }
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
    /// `dosageTaken` records what was actually taken for a medication event —
    /// pass it only when the user said so.
    @discardableResult
    public static func logDone(_ ctx: ModelContext, reminderId: UUID, date: Date = Date(),
                               dosageTaken: String? = nil) -> ReminderDTO? {
        guard let reminder = Repos.reminder(ctx, id: reminderId) else { return nil }

        // A one-tap log — lock-screen "Log taken ✓", the watch, the tab's Done
        // button — carries no amount, and for a medication that tap means "I
        // took the dose I'm supposed to take". So an absent `dosageTaken` falls
        // back to the reminder's configured `dosage`, which makes the history
        // read back truthfully instead of blank. An explicit value (half a
        // tablet) always wins, and this never writes back to `reminder.dosage`.
        var resolvedDosage = dosageTaken
        if resolvedDosage == nil,
           Repos.reminderGroup(ctx, id: reminder.groupId)?.kind == .medication {
            resolvedDosage = reminder.dosage
        }

        Repos.logReminderDone(ctx, ReminderEventDTO(
            userId: reminder.userId, reminderId: reminderId,
            date: Dates.dayKey(date), amountFlOz: reminder.amountFlOz, timestamp: date,
            dosageTaken: resolvedDosage
        ))
        // This is the mechanism behind "a log cancels the nudge": syncAfterChange
        // reschedules, and the event just written makes MedicationPattern's
        // hasLogToday true, so the rebuilt request moves to tomorrow's pattern
        // time (replacing today's pending one) rather than firing this evening.
        syncAfterChange(ctx, reminderId: reminderId, userId: reminder.userId)
        return reminder
    }

    /// Snoozes to tomorrow at the profile's preferred hour and syncs.
    /// No-ops (returns nil) for medication.
    @discardableResult
    public static func snooze(_ ctx: ModelContext, reminderId: UUID) -> ReminderDTO? {
        guard let reminder = Repos.reminder(ctx, id: reminderId) else { return nil }
        // Snooze is interval semantics — "push the due day out" — and
        // medication has no interval: it's scheduled from the logged pattern,
        // which never reads `snoozedUntil`. There's no snooze affordance on its
        // notification or in the UI either, so anything reaching here is a
        // mistake. Refuse rather than persist state nothing will act on.
        guard Repos.reminderGroup(ctx, id: reminder.groupId)?.kind != .medication else { return nil }

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
/// "Log taken ✓" / "Snooze 1 day") and the notification body, including when they wake the
/// app from a fully-terminated state (the action is what launches the
/// process — `container` is set in `OurFitnessApp.init()`, which always runs
/// before this delegate is invoked).
///
/// `@MainActor` with `nonisolated` delegate methods (the WatchSyncService
/// pattern): `container` is written from app init and read inside the
/// `Task { @MainActor }` hops, so it's never shared mutable state across actors.
@MainActor
final class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationDelegate()
    var container: ModelContainer?

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
    nonisolated func userNotificationCenter(
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
