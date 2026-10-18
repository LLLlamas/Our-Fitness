// Watch-side sync store. Thin client: no local SwiftData, the phone is the
// sole source of truth (see Shared/WatchSyncPayload.swift for the wire format
// and OurFitness/Services/WatchSyncService.swift for the phone side).
//
// The phone pushes ONE `WatchSnapshotEnvelope` (today + quick-log
// + meal shortcuts + live session) per `updateApplicationContext`, so this
// store holds exactly that one value and exposes read-throughs for each
// section — views never unwrap the optional envelope themselves.
//
// The cache keeps the watch usable offline / on cold launch before the phone
// round-trips anything: `envelope` mirrors into UserDefaults as JSON on every
// update.
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
    /// The cached value is a whole envelope. The pre-envelope
    /// `watch.cachedReminderSnapshots` blob (a bare reminder list) has an
    /// incompatible shape and is discarded at launch; so is the plant-thumbnail
    /// cache directory from builds that still had Reminders.
    private let envelopeDefaultsKey = "watch.cachedSnapshotEnvelope"

    /// Amount this watch last logged per exercise, so an undo rewinds by the
    /// right step. Deliberately in-memory only: it describes a just-taken action
    /// the phone hasn't acknowledged yet, and is worthless across a relaunch.
    private var lastLoggedAmount: [String: Int] = [:]
    private let legacySnapshotsDefaultsKey = "watch.cachedReminderSnapshots"

    /// Raw bytes of the last application context we acted on, so a re-delivery
    /// of the identical context is a no-op rather than a rollback of optimistic
    /// state. In-memory only: after a relaunch there is no optimistic state left
    /// to protect, and reapplying the stored context is then exactly right.
    private var lastReceivedContextData: Data?

    /// Actions encoded before `WCSession` finished activating. `transferUserInfo`
    /// may only be called on an ACTIVATED session, so these wait here and flush
    /// from the activation callback instead of being dropped (or raising).
    private var pendingActions: [Data] = []

    /// Only ever used before the first sync, so a calorie readout shows a
    /// ballpark rather than zero. The real weight rides on every envelope.
    private static let fallbackBodyWeightLb: Double = 155

    private override init() {
        super.init()

        UserDefaults.standard.removeObject(forKey: legacySnapshotsDefaultsKey)
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? FileManager.default.removeItem(at: caches.appendingPathComponent("PlantThumbnails", isDirectory: true))
        }
        loadCachedEnvelope()

        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Read-throughs
    // Views bind to these rather than to `envelope`, so "no sync yet" and
    // "synced but empty" render through the same code path.

    var today: TodaySnapshot { envelope?.today ?? TodaySnapshot() }
    var quickLogExercises: [QuickLogExercise] { envelope?.quickLogExercises ?? [] }
    var mealShortcuts: [MealShortcut] { envelope?.mealShortcuts ?? [] }
    var liveSession: LiveSessionSnapshot? { envelope?.liveSession }
    var bodyWeightLb: Double { envelope?.bodyWeightLb ?? Self.fallbackBodyWeightLb }
    var hasSynced: Bool { envelope != nil }

    /// When the phone BUILT the snapshot these numbers come from — the one thing
    /// that tells a stale screen apart from a current one. `today` is folded from
    /// the phone's logs for the day of this instant, so once it rolls over a day
    /// the whole Today screen is reporting yesterday under a "Today" title.
    ///
    /// Nil when there is nothing honest to say: before the first sync, and for a
    /// payload from a build that didn't stamp the field (`init(from:)` decodes a
    /// missing key as `.distantPast`, which must never reach a UI as a date).
    var snapshotGeneratedAt: Date? {
        guard let at = envelope?.generatedAt, at.timeIntervalSince1970 > 0 else { return nil }
        return at
    }

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

    // MARK: - Applying context from the phone

    private func applyApplicationContext(_ context: [String: Any]) {
        guard let data = context[WatchSyncKeys.snapshotContextKey] as? Data else { return }
        // The SAME context is handed to us again on every activation
        // (`receivedApplicationContext` is the last one the system holds), and
        // reapplying it would roll back any optimistic update taken since —
        // the wrist's own water/quick-log tap would visibly un-happen on the
        // next launch. Distinct pushes always differ, because the phone stamps
        // `generatedAt` on each one, so byte-identical means "nothing new".
        guard data != lastReceivedContextData else { return }
        guard let decoded = decodeEnvelope(from: data) else { return }
        lastReceivedContextData = data
        // A phone newer than this watch build changed the format under us.
        // Decoding it as if it were this version is the failure mode to avoid,
        // so keep the last good envelope and wait for the watch app to update.
        guard decoded.isReadable else {
            print("[WatchSync] ignoring envelope schemaVersion \(decoded.schemaVersion) > \(WatchSnapshotEnvelope.currentSchemaVersion); keeping cached snapshot")
            return
        }
        envelope = decoded
        persistEnvelope()
    }

    private func decodeEnvelope(from data: Data) -> WatchSnapshotEnvelope? {
        try? JSONDecoder().decode(WatchSnapshotEnvelope.self, from: data)
    }

    // MARK: - Sending wrist actions

    /// Encodes and queues a wrist action for the phone, and applies an
    /// optimistic local update immediately so the UI feels instant even
    /// before the phone round-trips a fresh snapshot back. Never gated on
    /// `isReachable` — `transferUserInfo` queues automatically offline.
    func send(_ action: WatchAction) {
        applyOptimistic(action)
        guard WCSession.isSupported(), let data = try? JSONEncoder().encode(action) else { return }
        deliver(data)
    }

    /// `transferUserInfo` may only be called on an ACTIVATED session, and
    /// activation is asynchronous — a tap in the first moments after launch can
    /// land before it completes. The phone guards its own `updateApplicationContext`
    /// the same way (`WatchSyncService.pushSnapshot`); here the action is queued
    /// rather than dropped, because the optimistic update has already been applied
    /// and a dropped action would leave the two devices disagreeing.
    private func deliver(_ data: Data) {
        guard WCSession.default.activationState == .activated else {
            pendingActions.append(data)
            return
        }
        WCSession.default.transferUserInfo([WatchSyncKeys.actionUserInfoKey: data])
    }

    /// Drains the queue exactly once — emptied BEFORE the transfers are handed
    /// over, so a re-entrant activation callback can't send any action twice.
    private func flushPendingActions() {
        guard !pendingActions.isEmpty, WCSession.default.activationState == .activated else { return }
        let queued = pendingActions
        pendingActions.removeAll()
        for data in queued {
            WCSession.default.transferUserInfo([WatchSyncKeys.actionUserInfoKey: data])
        }
    }

    /// Best-effort local echo of what the phone is about to do. Anything it
    /// gets slightly wrong is corrected by the next context push, so it only
    /// ever needs to be right enough to look immediate.
    private func applyOptimistic(_ action: WatchAction) {
        guard var env = envelope else { return }
        switch action {
        case .logWater(let flOz, _):
            env.today.waterFlOz += flOz
            env.today.waterLastFlOz = flOz
        case .logQuickSet(let exerciseId, let amount, _):
            guard let idx = env.quickLogExercises.firstIndex(where: { $0.id == exerciseId }) else { return }
            // loggedToday is a SUM of reps (or minutes), matching what the phone's
            // ExercisesCard shows — not a count of sets.
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
    // (those are iOS-only) -- only the two methods below exist on this platform.

    nonisolated func session(
        _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?
    ) {
        // Covers the case where the context arrived before the delegate was set.
        let context = session.receivedApplicationContext
        Task { @MainActor in
            self.applyApplicationContext(context)
            // Anything tapped before activation finished goes out now.
            self.flushPendingActions()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.applyApplicationContext(applicationContext)
        }
    }
}
