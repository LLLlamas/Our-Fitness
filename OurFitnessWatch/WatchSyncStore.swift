// Watch-side sync store. Thin client: no local SwiftData, the phone is the
// sole source of truth (see Shared/WatchSyncPayload.swift for the wire format
// and OurFitness/Services/WatchSyncService.swift for the phone side).
//
// The phone pushes ONE `WatchSnapshotEnvelope` (reminders + today + quick-log
// + meal shortcuts + live session) per `updateApplicationContext`, so this
// store holds exactly that one value and exposes read-throughs for each
// section — views never unwrap the optional envelope themselves.
//
// Two caches keep the watch usable offline / on cold launch before the phone
// round-trips anything:
//   - `envelope` mirrors into UserDefaults as JSON on every update.
//   - `thumbnails` mirrors into files in the watch's Caches directory.
// Wrist actions (`send(_:)`) apply an optimistic local update immediately,
// then queue a `transferUserInfo` — which the system delivers even while the
// phone is unreachable, so nothing taken on the wrist is ever lost.

import Foundation
import Combine
import WatchConnectivity

@MainActor
final class WatchSyncStore: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSyncStore()

    /// nil until the first successful sync (or cache load) — `hasSynced`.
    @Published private(set) var envelope: WatchSnapshotEnvelope?
    @Published private(set) var thumbnails: [UUID: Data] = [:]

    /// New key: the cached value is now a whole envelope, not a bare
    /// `[ReminderSnapshot]`. The old `watch.cachedReminderSnapshots` blob has an
    /// incompatible shape and is discarded at launch rather than migrated — the
    /// gap it leaves lasts only until the phone's next context push, and the
    /// transitional wire-format fallback in `decodeEnvelope` covers a phone that
    /// is still on the old build.
    private let envelopeDefaultsKey = "watch.cachedSnapshotEnvelope"

    /// Amount this watch last logged per exercise, so an undo rewinds by the
    /// right step. Deliberately in-memory only: it describes a just-taken action
    /// the phone hasn't acknowledged yet, and is worthless across a relaunch.
    private var lastLoggedAmount: [String: Int] = [:]
    private let legacySnapshotsDefaultsKey = "watch.cachedReminderSnapshots"
    private let thumbnailsDirectory: URL

    /// Only ever used before the first sync, so a calorie readout shows a
    /// ballpark rather than zero. The real weight rides on every envelope.
    private static let fallbackBodyWeightLb: Double = 155

    private override init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        thumbnailsDirectory = caches.appendingPathComponent("PlantThumbnails", isDirectory: true)
        super.init()

        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        UserDefaults.standard.removeObject(forKey: legacySnapshotsDefaultsKey)
        loadCachedEnvelope()
        loadCachedThumbnails()

        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Read-throughs
    // Views bind to these rather than to `envelope`, so "no sync yet" and
    // "synced but empty" render through the same code path.

    var reminders: [ReminderSnapshot] { envelope?.reminders ?? [] }
    var today: TodaySnapshot { envelope?.today ?? TodaySnapshot() }
    var quickLogExercises: [QuickLogExercise] { envelope?.quickLogExercises ?? [] }
    var mealShortcuts: [MealShortcut] { envelope?.mealShortcuts ?? [] }
    var liveSession: LiveSessionSnapshot? { envelope?.liveSession }
    var bodyWeightLb: Double { envelope?.bodyWeightLb ?? Self.fallbackBodyWeightLb }
    var hasSynced: Bool { envelope != nil }

    // MARK: - Local caches

    private func loadCachedEnvelope() {
        guard let data = UserDefaults.standard.data(forKey: envelopeDefaultsKey),
              let decoded = try? JSONDecoder().decode(WatchSnapshotEnvelope.self, from: data),
              decoded.isReadable else { return }
        envelope = decoded
    }

    private func persistEnvelope() {
        guard let envelope, let data = try? JSONEncoder().encode(envelope) else { return }
        UserDefaults.standard.set(data, forKey: envelopeDefaultsKey)
    }

    /// Reads cached thumbnail files off the main actor at launch, then merges
    /// only ids still in `reminders` and not already set — so a slow load can
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
                let valid = Set(self.reminders.map(\.id))
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
              let decoded = decodeEnvelope(from: data) else { return }
        // A phone newer than this watch build changed the format under us.
        // Decoding it as if it were this version is the failure mode to avoid,
        // so keep the last good envelope and wait for the watch app to update.
        guard decoded.isReadable else {
            print("[WatchSync] ignoring envelope schemaVersion \(decoded.schemaVersion) > \(WatchSnapshotEnvelope.currentSchemaVersion); keeping cached snapshot")
            return
        }
        envelope = decoded
        persistEnvelope()
        pruneThumbnails(keeping: Set(decoded.reminders.map(\.id)))
    }

    private func decodeEnvelope(from data: Data) -> WatchSnapshotEnvelope? {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(WatchSnapshotEnvelope.self, from: data) {
            return envelope
        }
        // TRANSITIONAL: builds before the envelope pushed a bare
        // [ReminderSnapshot] under the same context key. During an app update
        // the phone and watch can briefly disagree; without this the watch
        // would show an empty screen until the phone side caught up. Remove
        // once no shipped phone build sends the old shape.
        guard let legacy = try? decoder.decode([ReminderSnapshot].self, from: data) else { return nil }
        print("[WatchSync] decoded legacy [ReminderSnapshot] payload; wrapping in a minimal envelope")
        return WatchSnapshotEnvelope(
            profileId: envelope?.profileId ?? UUID(),
            mode: envelope?.mode ?? "",
            bodyWeightLb: envelope?.bodyWeightLb ?? Self.fallbackBodyWeightLb,
            reminders: legacy,
            generatedAt: Date()
        )
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

    /// Best-effort local echo of what the phone is about to do. Anything it
    /// gets slightly wrong is corrected by the next context push, so it only
    /// ever needs to be right enough to look immediate.
    private func applyOptimistic(_ action: WatchAction) {
        guard var env = envelope else { return }
        switch action {
        case .done(let reminderId, let date):
            guard let idx = env.reminders.firstIndex(where: { $0.id == reminderId }) else { return }
            env.reminders[idx].lastDoneAt = date
        case .setInterval(let reminderId, let days):
            guard let idx = env.reminders.firstIndex(where: { $0.id == reminderId }) else { return }
            // Generic 1...365 bounds, NOT PlantCatalog's watering range —
            // mirrors the phone-side clamp in WatchSyncService.apply.
            env.reminders[idx].intervalDays = ReminderSchedule.clampInterval(days)
        case .snooze(let reminderId):
            guard let idx = env.reminders.firstIndex(where: { $0.id == reminderId }) else { return }
            // The profile's own hour rides on the snapshot; falling back to the
            // default only for a payload from a build that didn't send it.
            env.reminders[idx].snoozedUntil = ReminderSchedule.snoozeDate(
                preferredHour: env.reminders[idx].preferredHour ?? ReminderSchedule.defaultReminderHour
            )
        case .logWater(let flOz, _):
            env.today.waterFlOz += flOz
            env.today.waterLastFlOz = flOz
        case .logQuickSet(let exerciseId, let amount, _):
            guard let idx = env.quickLogExercises.firstIndex(where: { $0.id == exerciseId }) else { return }
            // loggedToday is a SUM of reps (or minutes), matching what the phone's
            // BabyExercisesCard shows — not a count of sets.
            env.quickLogExercises[idx].loggedToday += amount
            lastLoggedAmount[exerciseId] = amount
        case .undoQuickSet(let exerciseId, _):
            guard let idx = env.quickLogExercises.firstIndex(where: { $0.id == exerciseId }) else { return }
            // Step back by the amount THIS watch last logged, so undoing a "+5 min"
            // doesn't visibly rewind by 1. If the most recent set was logged on the
            // phone we don't know its size, so fall back to a single tap; either way
            // the phone's next push is authoritative and settles any drift.
            let step = lastLoggedAmount.removeValue(forKey: exerciseId) ?? 1
            env.quickLogExercises[idx].loggedToday = max(0, env.quickLogExercises[idx].loggedToday - step)
        case .logMeal(let shortcutId, _, _, _):
            guard let shortcut = env.mealShortcuts.first(where: { $0.id == shortcutId }) else { return }
            // Display-only arithmetic: the phone re-resolves the real macros
            // from the template/food, and its next push corrects any drift.
            env.today.caloriesConsumed += shortcut.calories
            env.today.proteinG += shortcut.proteinG
        case .startLiveSession(let activityId, let activityName, let met, let expectedMinutes, let startDate):
            env.liveSession = LiveSessionSnapshot(
                startDate: startDate, activityId: activityId, activityName: activityName,
                met: met, expectedMinutes: expectedMinutes
            )
        case .endLiveSession:
            env.liveSession = nil
        }
        envelope = env
        persistEnvelope()
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
