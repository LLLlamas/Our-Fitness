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
    /// Session-scoped change detection: hash of the `photoData` last handed to
    /// `transferFile` per reminder, so unchanged photos skip the decode →
    /// re-encode → transfer pipeline on every foreground/mutation push.
    private var pushedThumbnailHashes: [UUID: Int] = [:]
    /// Cleared-hash trigger: the watch prunes its thumbnail cache to the
    /// pushed profile's reminders, so a profile switch must re-push everything.
    private var lastPushedUserId: UUID?

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

        pushChangedThumbnails(reminders, userId: userId)
    }

    /// Transfers thumbnails only for photos not yet pushed (or changed) this
    /// session. A superseded in-flight transfer for the same reminder is
    /// cancelled — and its temp file removed — before the replacement queues.
    private func pushChangedThumbnails(_ reminders: [ReminderDTO], userId: UUID) {
        if userId != lastPushedUserId {
            pushedThumbnailHashes.removeAll()
            lastPushedUserId = userId
        }
        let outstanding = WCSession.default.outstandingFileTransfers
        for r in reminders {
            guard let photo = r.photoData, pushedThumbnailHashes[r.id] != photo.hashValue else { continue }
            pushedThumbnailHashes[r.id] = photo.hashValue
            for t in outstanding where t.file.metadata?["reminderId"] as? String == r.id.uuidString {
                t.cancel()
                try? FileManager.default.removeItem(at: t.file.fileURL)
            }
            pushThumbnail(reminderId: r.id, fullPhotoData: photo)
        }
    }

    /// Sends a small (~120px) JPEG thumbnail so the watch can show the actual
    /// plant instead of only an SF Symbol. Best-effort: `transferFile` queues
    /// on the system side, so this needs no reachability check, and a failed
    /// downscale/write just leaves the watch on its sfSymbol fallback.
    /// Decode/re-encode runs off the main actor; the temp filename is unique
    /// per transfer so a cancelled predecessor's cleanup can't race the new
    /// write (the watch reads the reminder id from metadata, not the name).
    /// Each temp file is deleted in `session(_:didFinish:error:)`.
    private func pushThumbnail(reminderId: UUID, fullPhotoData: Data) {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(WatchSyncKeys.thumbnailFilePrefix + reminderId.uuidString + "-" + UUID().uuidString)
            .appendingPathExtension("jpg")
        Task.detached(priority: .utility) {
            guard let thumb = ImageDownscale.jpegData(from: fullPhotoData, maxDimension: 120),
                  (try? thumb.write(to: tmpURL, options: .atomic)) != nil else { return }
            WCSession.default.transferFile(tmpURL, metadata: ["reminderId": reminderId.uuidString])
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

    /// Mirrors RootView's active-profile resolution: `@AppStorage("activeProfileId")`
    /// with a fallback to the first (oldest-created) profile.
    private func activeProfile(_ ctx: ModelContext) -> ProfileDTO? {
        let profiles = Repos.listProfiles(ctx)
        guard let stored = UserDefaults.standard.string(forKey: "activeProfileId"),
              let id = UUID(uuidString: stored) else { return profiles.first }
        return profiles.first(where: { $0.id == id }) ?? profiles.first
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("[WatchSync] activation failed:", error.localizedDescription)
        }
        sweepStaleTempFiles(session)
        Task { @MainActor in
            guard let container = self.container else { return }
            let ctx = container.mainContext
            // Only the active profile — every profile would overwrite the same
            // application-context key, leaving whichever pushed last on the watch.
            guard let profile = self.activeProfile(ctx) else { return }
            self.pushSnapshot(ctx, userId: profile.id)
        }
    }

    /// Deletes leftover thumbnail temp files (e.g. from a session that died
    /// mid-transfer) that no outstanding transfer still references.
    nonisolated private func sweepStaleTempFiles(_ session: WCSession) {
        let live = Set(session.outstandingFileTransfers.map { $0.file.fileURL.standardizedFileURL })
        let tmp = FileManager.default.temporaryDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
        for url in files
        where url.lastPathComponent.hasPrefix(WatchSyncKeys.thumbnailFilePrefix) && !live.contains(url.standardizedFileURL) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        // A failed transfer stays retryable: drop its hash so the next
        // pushSnapshot re-sends instead of skipping it as already pushed.
        guard error != nil,
              let idString = fileTransfer.file.metadata?["reminderId"] as? String,
              let id = UUID(uuidString: idString) else { return }
        Task { @MainActor in
            self.pushedThumbnailHashes.removeValue(forKey: id)
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
