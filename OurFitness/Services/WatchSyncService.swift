// Phone-side of the OurFitnessWatch companion app sync.
//
// Architecture: the watch is a thin client with no local SwiftData store; the
// phone is the sole source of truth. The phone pushes the full reminder list
// via `updateApplicationContext` (latest-wins, delivered even when the watch
// app is closed) on activation, on every foreground, and after every
// reminder mutation. The watch sends `WatchAction`s back via
// `transferUserInfo`, which queues automatically while the phone is
// unreachable, so a wrist action taken offline is never lost — it applies as
// soon as connectivity resumes. See Shared/ReminderSyncPayload.swift for the
// wire format.
//
// Guarded by `WCSession.isSupported()` throughout, so this is a complete
// no-op (zero behavior change) for any user without a paired Apple Watch.

import Foundation
import WatchConnectivity
import SwiftData

@MainActor
final class WatchSyncService: NSObject, WCSessionDelegate {
    static let shared = WatchSyncService()

    private var container: ModelContainer?

    private override init() {
        super.init()
    }

    /// Call once from `OurFitnessApp.init()`, right after the container is built.
    func activate(container: ModelContainer) {
        self.container = container
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Pushes the full reminder list for one profile to the watch. Call after
    /// activation, on `scenePhase == .active`, and after every add/edit/
    /// delete/done/snooze mutation (the same call sites that call
    /// `ReminderNotificationService.reschedule`).
    func pushSnapshot(_ ctx: ModelContext, userId: UUID) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }

        let groupsById = Dictionary(uniqueKeysWithValues: Repos.listReminderGroups(ctx, userId: userId).map { ($0.id, $0) })
        let reminders = Repos.listReminders(ctx, userId: userId)

        // One fetch of every event, folded into "latest per reminder" — not a
        // per-reminder lastReminderEvent call, which would be an N+1 fetch.
        var lastDoneById: [UUID: Date] = [:]
        for e in Repos.listReminderEvents(ctx, userId: userId) where lastDoneById[e.reminderId] == nil {
            lastDoneById[e.reminderId] = e.timestamp
        }

        let snapshots: [ReminderSnapshot] = reminders.compactMap { r in
            guard let group = groupsById[r.groupId] else { return nil }
            return ReminderSnapshot(
                id: r.id, groupId: r.groupId, groupName: group.name, groupKind: group.kind.rawValue,
                name: r.name, speciesId: r.speciesId, room: r.room, lightRaw: r.light?.rawValue,
                potDiameterInches: r.potDiameterInches, intervalDays: r.intervalDays,
                amountFlOz: r.amountFlOz, createdAt: r.createdAt, snoozedUntil: r.snoozedUntil,
                lastDoneAt: lastDoneById[r.id]
            )
        }
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        try? WCSession.default.updateApplicationContext([WatchSyncKeys.snapshotContextKey: data])

        for r in reminders where r.photoData != nil {
            pushThumbnail(reminderId: r.id, fullPhotoData: r.photoData!)
        }
    }

    /// Sends a small (~120px) JPEG thumbnail so the watch can show the actual
    /// plant instead of only an SF Symbol. Best-effort: `transferFile` queues
    /// on the system side, so this can be called liberally without checking
    /// reachability first.
    private func pushThumbnail(reminderId: UUID, fullPhotoData: Data) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let thumb = ImageDownscale.jpegData(from: fullPhotoData, maxDimension: 120) else { return }

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(WatchSyncKeys.thumbnailFilePrefix + reminderId.uuidString)
            .appendingPathExtension("jpg")
        do {
            try thumb.write(to: tmpURL, options: .atomic)
            WCSession.default.transferFile(tmpURL, metadata: ["reminderId": reminderId.uuidString])
        } catch {
            // Best-effort — the watch falls back to the group's sfSymbol.
        }
    }

    /// Applies a wrist-initiated action via the same mutation coordinators the
    /// UI uses (ReminderNotificationService.logDone/update/snooze) — each
    /// already reschedules the notification and pushes a fresh snapshot back,
    /// so the watch reflects the change (e.g. "watered today") without this
    /// method separately re-doing that sync step.
    private func apply(_ action: WatchAction) {
        guard let container else { return }
        let ctx = container.mainContext

        switch action {
        case .done(let reminderId, let date):
            ReminderNotificationService.logDone(ctx, reminderId: reminderId, date: date)

        case .setInterval(let reminderId, let days):
            guard var reminder = Repos.reminder(ctx, id: reminderId) else { return }
            reminder.intervalDays = min(PlantCatalog.maxIntervalDays, max(PlantCatalog.minIntervalDays, days))
            ReminderNotificationService.update(ctx, reminder)

        case .snooze(let reminderId):
            ReminderNotificationService.snooze(ctx, reminderId: reminderId)
        }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            guard let container = self.container else { return }
            let ctx = container.mainContext
            for profile in Repos.listProfiles(ctx) {
                self.pushSnapshot(ctx, userId: profile.id)
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[WatchSyncKeys.actionUserInfoKey] as? Data,
              let action = try? JSONDecoder().decode(WatchAction.self, from: data) else { return }
        Task { @MainActor in
            self.apply(action)
        }
    }
}
