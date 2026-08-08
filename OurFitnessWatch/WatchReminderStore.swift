// Watch-side sync store. Thin client: no local SwiftData, the phone is the
// sole source of truth (see Shared/ReminderSyncPayload.swift for the wire
// format and OurFitness/Services/WatchSyncService.swift for the phone side).
//
// Two caches keep the watch usable offline / on cold launch before the phone
// round-trips anything:
//   - `snapshots` mirrors into UserDefaults as JSON on every update.
//   - `thumbnails` mirrors into files in the watch's Caches directory.
// Wrist actions (`send(_:)`) apply an optimistic local update immediately,
// then queue a `transferUserInfo` — which the system delivers even while the
// phone is unreachable, so nothing taken on the wrist is ever lost.

import Foundation
import Combine
import WatchConnectivity

@MainActor
final class WatchReminderStore: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchReminderStore()

    @Published var snapshots: [ReminderSnapshot] = []
    @Published var thumbnails: [UUID: Data] = [:]

    private let snapshotsDefaultsKey = "watch.cachedReminderSnapshots"
    private let thumbnailsDirectory: URL

    private override init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        thumbnailsDirectory = caches.appendingPathComponent("PlantThumbnails", isDirectory: true)
        super.init()

        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        loadCachedSnapshots()
        loadCachedThumbnails()

        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Local caches

    private func loadCachedSnapshots() {
        guard let data = UserDefaults.standard.data(forKey: snapshotsDefaultsKey),
              let decoded = try? JSONDecoder().decode([ReminderSnapshot].self, from: data) else { return }
        snapshots = decoded
    }

    private func persistSnapshots() {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        UserDefaults.standard.set(data, forKey: snapshotsDefaultsKey)
    }

    /// Reads cached thumbnail files off the main actor at launch, then merges
    /// only ids still in `snapshots` and not already set — so a slow load can
    /// neither clobber a fresher transfer nor resurrect a pruned entry.
    private func loadCachedThumbnails() {
        let dir = thumbnailsDirectory
        Task.detached(priority: .utility) {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            let loaded: [UUID: Data] = files.reduce(into: [:]) { acc, url in
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                      let data = try? Data(contentsOf: url) else { return }
                acc[id] = data
            }
            await MainActor.run {
                let valid = Set(self.snapshots.map(\.id))
                for (id, data) in loaded where valid.contains(id) && self.thumbnails[id] == nil {
                    self.thumbnails[id] = data
                }
            }
        }
    }

    private func thumbnailURL(for reminderId: UUID) -> URL {
        thumbnailsDirectory.appendingPathComponent(reminderId.uuidString).appendingPathExtension("jpg")
    }

    private func storeThumbnail(_ data: Data, for reminderId: UUID) {
        try? data.write(to: thumbnailURL(for: reminderId), options: .atomic)
        thumbnails[reminderId] = data
    }

    /// Evicts cached thumbnails (memory + disk) for reminders no longer in
    /// the latest snapshot set (deleted, or another profile's).
    private func pruneThumbnails(keeping ids: Set<UUID>) {
        thumbnails = thumbnails.filter { ids.contains($0.key) }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: thumbnailsDirectory, includingPropertiesForKeys: nil
        )) ?? []
        for url in files {
            let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent)
            if id.map(ids.contains) != true {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Applying context from the phone

    private func applyApplicationContext(_ context: [String: Any]) {
        guard let data = context[WatchSyncKeys.snapshotContextKey] as? Data,
              let decoded = try? JSONDecoder().decode([ReminderSnapshot].self, from: data) else { return }
        snapshots = decoded
        persistSnapshots()
        pruneThumbnails(keeping: Set(decoded.map(\.id)))
    }

    // MARK: - Sending wrist actions

    /// Encodes and queues a wrist action for the phone, and applies an
    /// optimistic local update immediately so the UI feels instant even
    /// before the phone round-trips a fresh snapshot back. Never gated on
    /// `isReachable` — `transferUserInfo` queues automatically offline.
    func send(_ action: WatchAction) {
        applyOptimistic(action)
        guard WCSession.isSupported(), let data = try? JSONEncoder().encode(action) else { return }
        WCSession.default.transferUserInfo([WatchSyncKeys.actionUserInfoKey: data])
    }

    private func applyOptimistic(_ action: WatchAction) {
        guard let idx = snapshots.firstIndex(where: { $0.id == actionReminderId(action) }) else { return }
        switch action {
        case .done(_, let date):
            snapshots[idx].lastDoneAt = date
        case .setInterval(_, let days):
            // Generic 1...365 bounds, NOT PlantCatalog's watering range —
            // mirrors the phone-side clamp in WatchSyncService.apply.
            snapshots[idx].intervalDays = ReminderSchedule.clampInterval(days)
        case .snooze:
            // The profile's own hour rides on the snapshot; falling back to the
            // default only for a payload from a build that didn't send it.
            snapshots[idx].snoozedUntil = ReminderSchedule.snoozeDate(
                preferredHour: snapshots[idx].preferredHour ?? ReminderSchedule.defaultReminderHour
            )
        }
        persistSnapshots()
    }

    private func actionReminderId(_ action: WatchAction) -> UUID {
        switch action {
        case .done(let reminderId, _): return reminderId
        case .setInterval(let reminderId, _): return reminderId
        case .snooze(let reminderId): return reminderId
        }
    }

    // MARK: - WCSessionDelegate
    // watchOS's WCSessionDelegate has no sessionDidBecomeInactive/sessionDidDeactivate
    // (those are iOS-only) -- only the three methods below exist on this platform.

    nonisolated func session(
        _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?
    ) {
        // Covers the case where the context arrived before the delegate was set.
        let context = session.receivedApplicationContext
        Task { @MainActor in
            self.applyApplicationContext(context)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.applyApplicationContext(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // Read the bytes out synchronously -- the system deletes the temp
        // file right after this method returns, so this cannot wait for a
        // Task hop before extracting the data.
        guard let reminderIdString = file.metadata?["reminderId"] as? String,
              let reminderId = UUID(uuidString: reminderIdString),
              let data = try? Data(contentsOf: file.fileURL) else { return }
        Task { @MainActor in
            self.storeThumbnail(data, for: reminderId)
        }
    }
}
