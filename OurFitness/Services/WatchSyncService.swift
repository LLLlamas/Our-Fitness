// Phone-side of the OurFitnessWatch companion app sync.
//
// Architecture: the watch is a thin client with no local SwiftData store; the
// phone is the sole source of truth. The phone pushes ONE
// `WatchSnapshotEnvelope` — reminders, today's numbers, quick-log movements,
// meal shortcuts, live session — via `updateApplicationContext` (latest-wins,
// delivered even when the watch app is closed) on activation, on every
// foreground, and after every mutation the watch can see. It is one envelope
// because `updateApplicationContext` REPLACES the whole context dictionary, so
// a second key would silently clobber the first. The watch sends
// `WatchAction`s back via `transferUserInfo`, which queues automatically while
// the phone is unreachable, so a wrist action taken offline is never lost — it
// applies as soon as connectivity resumes. See Shared/WatchSyncPayload.swift
// for the wire format.
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

    /// Builds and pushes the whole `WatchSnapshotEnvelope` for one profile. Call
    /// after activation, on `scenePhase == .active`, and after every mutation the
    /// watch can see (the same call sites that call
    /// `ReminderNotificationService.reschedule`).
    ///
    /// Deliberately ONE build-everything pass: `updateApplicationContext` replaces
    /// the entire context dictionary, so there is no such thing as pushing "just
    /// the reminders" or "just today" — see Shared/WatchSyncPayload.swift's header.
    /// The rule throughout is one fetch per entity, folded in memory; never a
    /// per-row fetch inside a loop.
    func pushSnapshot(_ ctx: ModelContext, userId: UUID) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        // The profile carries mode + body weight, which the watch needs for its
        // theme and for DISPLAYING (never computing) calorie figures. Without it
        // there is no envelope to build.
        guard let profile = Repos.listProfiles(ctx).first(where: { $0.id == userId }) else { return }

        let now = Date()
        let todayKey = Dates.dayKey(now)

        let groupsById = Dictionary(uniqueKeysWithValues: Repos.listReminderGroups(ctx, userId: userId).map { ($0.id, $0) })
        let reminders = Repos.listReminders(ctx, userId: userId)

        // One fetch of every event, folded into "latest per reminder" — not a
        // per-reminder lastReminderEvent call, which would be an N+1 fetch.
        var lastDoneById: [UUID: Date] = [:]
        for e in Repos.listReminderEvents(ctx, userId: userId) where lastDoneById[e.reminderId] == nil {
            lastDoneById[e.reminderId] = e.timestamp
        }

        // Same for every reminder in this push (it's a per-profile setting),
        // so it's read once rather than per iteration.
        let preferredHour = ReminderNotificationService.preferredHour(for: userId)

        let snapshots: [ReminderSnapshot] = reminders.compactMap { r in
            guard let group = groupsById[r.groupId] else { return nil }
            return ReminderSnapshot(
                id: r.id, groupId: r.groupId, groupName: group.name, groupKind: group.kind.rawValue,
                name: r.name, speciesId: r.speciesId, room: r.room, lightRaw: r.light?.rawValue,
                potDiameterInches: r.potDiameterInches, intervalDays: r.intervalDays,
                amountFlOz: r.amountFlOz, createdAt: r.createdAt, snoozedUntil: r.snoozedUntil,
                lastDoneAt: lastDoneById[r.id], notes: r.notes, preferredHour: preferredHour
            )
        }

        // ONE fetch of the whole food log, reused three ways: today's totals, the
        // 30-day affinity ranking, and the name/macro lookup that resolves the
        // ranked ids. Fetching per purpose would triple the same query.
        let allLogs = Repos.listFoodLog(ctx, userId: userId)

        let envelope = WatchSnapshotEnvelope(
            profileId: userId,
            profileName: profile.name,
            mode: profile.mode.rawValue,
            bodyWeightLb: profile.weightLb,
            reminders: snapshots,
            today: todaySnapshot(ctx, profile: profile, logs: allLogs, todayKey: todayKey),
            quickLogExercises: quickLogExercises(ctx, userId: userId, now: now),
            mealShortcuts: mealShortcuts(ctx, userId: userId, logs: allLogs, now: now),
            liveSession: LiveSessionStore.active(for: userId).map {
                LiveSessionSnapshot(
                    startDate: $0.startDate, activityId: $0.activityId,
                    activityName: $0.activityName, met: $0.met,
                    expectedMinutes: $0.expectedMinutes
                )
            },
            generatedAt: now
        )

        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? WCSession.default.updateApplicationContext([WatchSyncKeys.snapshotContextKey: data])

        pushChangedThumbnails(reminders, userId: userId)
    }

    // MARK: - Envelope sections

    /// Today's finished numbers. Macros are folded from the log array the caller
    /// already fetched; targets come straight off `profile.computedTargets` (the
    /// stored plan) rather than being recomputed, so the watch can never disagree
    /// with the phone's own cards about what the target is.
    private func todaySnapshot(
        _ ctx: ModelContext, profile: ProfileDTO, logs: [FoodLogEntryDTO], todayKey: String
    ) -> TodaySnapshot {
        let totals = DailyTotals.totals(from: logs.filter { $0.date == todayKey })
        let targets = profile.computedTargets
        let uid = profile.id.uuidString

        let steps = Steps.stepsForDay(Repos.listSteps(ctx, userId: profile.id), day: todayKey)
        // Mirrors StepsCard/TodayView: the per-profile override is an Int where
        // 0 (or absent) means "use the plan's target".
        let customStepsGoal = Self.intDefault("stepsGoal.\(uid)") ?? 0
        let water = Water.total(Repos.listWater(ctx, userId: profile.id), on: todayKey)
        let waterGoal = Self.doubleDefault("waterGoalFlOz.\(uid)") ?? Water.defaultGoalFlOz

        return TodaySnapshot(
            caloriesConsumed: totals.calories, caloriesTarget: targets.calories,
            proteinG: totals.proteinG, proteinTargetG: targets.proteinG,
            carbsG: totals.carbsG, carbsTargetG: targets.carbsG,
            fatG: totals.fatG, fatTargetG: targets.fatG,
            steps: steps, stepsGoal: customStepsGoal > 0 ? customStepsGoal : targets.stepsDaily,
            waterFlOz: water, waterGoalFlOz: waterGoal > 0 ? waterGoal : Water.defaultGoalFlOz,
            waterLastFlOz: Self.doubleDefault("waterLastFlOz.\(uid)")
        )
    }

    /// The same movement list `BabyExercisesCard` renders — every exercise owned
    /// by the profile, name-sorted — so the two devices show the same rows in the
    /// same order. `loggedToday` is the SUM OF REPS (for a duration exercise the
    /// reps field carries minutes), matching the card's per-row count exactly.
    private func quickLogExercises(_ ctx: ModelContext, userId: UUID, now: Date) -> [QuickLogExercise] {
        let exercises = Repos.exercises(ctx, forProfile: userId)
        guard !exercises.isEmpty else { return [] }
        let repsToday = todayRepsByExercise(ctx, userId: userId, now: now)
        return exercises.map {
            QuickLogExercise(
                id: $0.id, name: $0.name, kind: $0.kind.rawValue,
                loadLb: $0.loadLb, loggedToday: repsToday[$0.id] ?? 0
            )
        }
    }

    /// ONE fetch of today's sets folded into exerciseId → summed reps. A
    /// `Repos.setHistory` call per exercise would be an N+1 over the whole
    /// movement list on every foreground push. There is no repository function
    /// for "all of a profile's sets on one day" (only the per-exercise
    /// `setHistory`), so the descriptor is built here; if a second caller ever
    /// needs it, lift this into `Repos` rather than copying it.
    private func todayRepsByExercise(_ ctx: ModelContext, userId: UUID, now: Date) -> [String: Int] {
        let dayStart = Calendar.current.startOfDay(for: now)
        let desc = FetchDescriptor<WorkoutSetModel>(
            predicate: #Predicate { $0.userId == userId && $0.timestamp >= dayStart }
        )
        guard let models = try? ctx.fetch(desc) else { return [:] }
        return models.reduce(into: [:]) { acc, set in
            acc[set.exerciseId, default: 0] += set.reps
        }
    }

    /// Saved recipes first, then the profile's most-logged foods. Macros here are
    /// for DISPLAY only — `.logMeal` re-resolves them by id phone-side.
    private func mealShortcuts(
        _ ctx: ModelContext, userId: UUID, logs: [FoodLogEntryDTO], now: Date
    ) -> [MealShortcut] {
        var out: [MealShortcut] = []
        var seen = Set<String>()

        for t in Repos.listSavedTemplates(ctx, userId: userId) where seen.insert(t.id.uuidString).inserted {
            let total = t.totalPerServing
            out.append(MealShortcut(
                id: t.id.uuidString, name: t.name, emoji: t.emoji,
                calories: total.calories, proteinG: total.proteinG, source: "template"
            ))
        }

        // The affinity ranking returns ids only; names + macros are resolved from
        // the SAME log array (no extra fetch, no CommonFoods lookup — the user's
        // own most recent logging of that food is the truest label for it).
        let index = Self.loggedFoodIndex(logs)
        for id in FoodAffinity.mostLoggedIds(logs, days: 30, limit: Self.maxMealShortcuts, end: now) {
            guard let entry = index[id], seen.insert(id).inserted else { continue }
            out.append(MealShortcut(
                id: id, name: entry.name,
                calories: entry.perServing.calories, proteinG: entry.perServing.proteinG,
                source: "recent"
            ))
        }

        guard out.count > Self.maxMealShortcuts else { return out }
        // Truncation is logged, never silent: a shortcut that quietly vanished
        // from the wrist reads as lost data rather than a deliberate cap.
        print("[WatchSync] mealShortcuts truncated \(out.count) → \(Self.maxMealShortcuts)")
        return Array(out.prefix(Self.maxMealShortcuts))
    }

    /// Cap on `mealShortcuts`: the watch list stays glanceable and the
    /// application context stays small (it is a size-limited dictionary).
    private static let maxMealShortcuts = 20

    /// foodId → the most recent way this profile logged that food. `logs` arrives
    /// reverse-chronological from `Repos.listFoodLog`, so the FIRST hit per id is
    /// the newest one and later hits are skipped. Ingredient foodIds count too,
    /// matching how `FoodAffinity` counts them.
    private static func loggedFoodIndex(
        _ logs: [FoodLogEntryDTO]
    ) -> [String: (name: String, perServing: PerServing)] {
        var out: [String: (name: String, perServing: PerServing)] = [:]
        for e in logs {
            if let ings = e.ingredients, !ings.isEmpty {
                for ing in ings {
                    guard let id = ing.foodId, out[id] == nil else { continue }
                    out[id] = (ing.name, ing.scaledPerServing)
                }
            } else if let id = e.foodId, out[id] == nil {
                out[id] = (e.customName ?? id, e.perServing)
            }
        }
        return out
    }

    // MARK: - AppStorage bridges
    //
    // These keys are `@AppStorage` on the phone, which WCSession can't see. A
    // bare `.double(forKey:)`/`.integer(forKey:)` returns 0 for an ABSENT key,
    // which would read as "goal of zero" rather than "never set" — so read the
    // boxed object and let nil mean absent, the same care
    // `ReminderNotificationService.remindersGloballyEnabled()` takes.

    private static func doubleDefault(_ key: String) -> Double? {
        (UserDefaults.standard.object(forKey: key) as? NSNumber)?.doubleValue
    }

    private static func intDefault(_ key: String) -> Int? {
        (UserDefaults.standard.object(forKey: key) as? NSNumber)?.intValue
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

    /// Applies a wrist-initiated action. EVERY case must end with the phone's
    /// state pushed back, so the watch sees the result of its own action with no
    /// extra round trip.
    ///
    /// The reminder cases get that for free by going through the same mutation
    /// coordinators the UI uses (ReminderNotificationService.logDone/update/
    /// snooze) — each already reschedules the notification AND calls
    /// `pushSnapshot`. The cases with no such coordinator call `pushSnapshot`
    /// themselves after the write; that is the whole reason each of them resolves
    /// the active profile first.
    ///
    /// Nothing here trusts a number from the wire that it could derive itself:
    /// calories are recomputed from the real exercise/session and the profile's
    /// current weight, and meal macros are re-resolved by id — a snapshot the
    /// watch cached days ago must not be able to write stale figures.
    private func apply(_ action: WatchAction) {
        guard let container else { return }
        let ctx = container.mainContext

        switch action {
        case .done(let reminderId, let date):
            ReminderNotificationService.logDone(ctx, reminderId: reminderId, date: date)

        case .setInterval(let reminderId, let days):
            guard var reminder = Repos.reminder(ctx, id: reminderId) else { return }
            // Generic 1...365 bounds, NOT PlantCatalog's watering range — a
            // yearly reminder must survive a wrist edit round-trip intact.
            reminder.intervalDays = ReminderSchedule.clampInterval(days)
            ReminderNotificationService.update(ctx, reminder)

        case .snooze(let reminderId):
            ReminderNotificationService.snooze(ctx, reminderId: reminderId)

        case .logWater(let flOz, let date):
            guard flOz > 0, let profile = activeProfile(ctx) else { return }
            Repos.addWater(ctx, WaterEntryDTO(userId: profile.id, date: Dates.dayKey(date), flOz: flOz))
            // Keep the phone's tap-to-repeat amount in step with the wrist's, so
            // WaterQuickLogButton offers what the user last actually drank.
            UserDefaults.standard.set(flOz, forKey: "waterLastFlOz.\(profile.id.uuidString)")
            pushSnapshot(ctx, userId: profile.id)

        case .logQuickSet(let exerciseId, let amount, let date):
            guard amount > 0, let profile = activeProfile(ctx),
                  let exercise = Repos.exercises(ctx, forProfile: profile.id)
                    .first(where: { $0.id == exerciseId })
            else { return }
            // Mirrors BabyExercisesCard.logActivity — duration exercises bill by
            // the minute, rep exercises by the rep. Computed here from the stored
            // exercise, never sent over the wire.
            let cal: Double = exercise.kind == .duration
                ? CalorieEstimator.caloriesForDuration(
                    minutes: Double(amount), loadLb: exercise.loadLb, bodyWeightLb: profile.weightLb)
                : CalorieEstimator.caloriesForReps(
                    reps: amount, loadLb: exercise.loadLb, bodyWeightLb: profile.weightLb)
            // `date` (not now) so an action queued offline lands on the day it
            // was taken — which is also the day the watch already counted it on.
            Repos.addSet(ctx, WorkoutSetDTO(
                userId: profile.id, exerciseId: exercise.id, weightLb: nil,
                reps: amount, timestamp: date, caloriesEst: cal
            ))
            pushSnapshot(ctx, userId: profile.id)

        case .undoQuickSet(let exerciseId, let date):
            guard let profile = activeProfile(ctx) else { return }
            let dayKey = Dates.dayKey(date)
            // setHistory is one exercise-scoped fetch, newest first; narrowing to
            // the action's day keeps an offline undo from eating yesterday's set.
            guard let latest = Repos.setHistory(ctx, userId: profile.id, exerciseId: exerciseId)
                .first(where: { Dates.dayKey($0.timestamp) == dayKey })
            else { return }
            Repos.deleteSet(ctx, id: latest.id)
            pushSnapshot(ctx, userId: profile.id)

        case .logMeal(let shortcutId, let source, let slot, let date):
            guard let profile = activeProfile(ctx) else { return }
            let slotValue = Slot(rawValue: slot) ?? .other
            let dayKey = Dates.dayKey(date)
            if source == "template" {
                guard let id = UUID(uuidString: shortcutId),
                      let template = Repos.listSavedTemplates(ctx, userId: profile.id)
                        .first(where: { $0.id == id })
                else {
                    // Deleted since the snapshot was pushed. No-op rather than
                    // logging the wire's stale macros under a name that's gone.
                    print("[WatchSync] logMeal: template \(shortcutId) no longer exists — ignored")
                    return
                }
                Repos.addFoodLog(ctx, FoodLogEntryDTO(
                    userId: profile.id, date: dayKey, slot: slotValue,
                    customName: template.name, perServing: template.totalPerServing,
                    timestamp: date, ingredients: template.ingredients
                ))
            } else {
                guard let entry = Self.loggedFoodIndex(Repos.listFoodLog(ctx, userId: profile.id))[shortcutId] else {
                    print("[WatchSync] logMeal: food \(shortcutId) not in this profile's log history — ignored")
                    return
                }
                Repos.addFoodLog(ctx, FoodLogEntryDTO(
                    userId: profile.id, date: dayKey, slot: slotValue,
                    foodId: shortcutId, customName: entry.name,
                    perServing: entry.perServing, timestamp: date
                ))
            }
            pushSnapshot(ctx, userId: profile.id)

        case .startLiveSession(let activityId, let activityName, let met, let expectedMinutes, let startDate):
            guard let profile = activeProfile(ctx) else { return }
            let state = LiveSessionState(
                startDate: startDate, activityId: activityId, activityName: activityName,
                met: met, expectedMinutes: expectedMinutes, profileId: profile.id
            )
            // Both devices can start a session. Keep whichever started LATER —
            // an earlier start arriving now is a stale queued action, not the
            // session the user is actually in — and say which one was dropped.
            if let existing = LiveSessionStore.active(for: profile.id) {
                guard state.startDate > existing.startDate else {
                    print("[WatchSync] startLiveSession: discarded '\(activityName)' started \(startDate) — '\(existing.activityName)' started later (\(existing.startDate))")
                    return
                }
                print("[WatchSync] startLiveSession: replacing '\(existing.activityName)' (\(existing.startDate)) with the later '\(activityName)' (\(startDate))")
            }
            LiveSessionStore.save(state)
            // Best-effort, as in LiveSessionCard.start(): the Live Activity needs
            // no permission and fails soft. Notification authorization is NOT
            // requested here — a wrist action can arrive while the app is
            // backgrounded or freshly woken, and auth is only ever asked for from
            // an explicit in-app tap. `schedule` no-ops harmlessly if denied.
            if #available(iOS 16.2, *) {
                LiveSessionActivityController.start(
                    activityName: activityName,
                    symbol: ActivityCatalog.activity(id: activityId)?.symbol ?? "figure.mixed.cardio",
                    startDate: state.startDate,
                    expectedMinutes: expectedMinutes
                )
            }
            LiveSessionNotifier.schedule(
                activityName: activityName, expectedMinutes: expectedMinutes, from: state.startDate
            )
            pushSnapshot(ctx, userId: profile.id)

        case .endLiveSession(let startDate, let elapsedSeconds):
            guard let profile = activeProfile(ctx),
                  let state = LiveSessionStore.active(for: profile.id) else { return }
            // A queued end for a session that already finished — or that was
            // superseded by a later start — must not close the CURRENT one.
            // Sub-second tolerance: the anchor round-trips through two separate
            // JSON encodings (UserDefaults and the wire).
            guard abs(state.startDate.timeIntervalSince(startDate)) < 1 else {
                print("[WatchSync] endLiveSession: stale action for \(startDate) — active session started \(state.startDate); ignored")
                return
            }
            // Elapsed comes from the wrist because a queued action can be
            // delivered long after the user stopped, when now − startDate would
            // wildly overstate it; clamped to wall clock so it can't exceed the
            // time since the anchor either. Calories are recomputed from the
            // STORED session's MET and the profile's current weight.
            let elapsed = min(max(0, Double(elapsedSeconds)), Double(state.elapsedSeconds()))
            let actualMinutes = max(1, Int((elapsed / 60.0).rounded()))
            let cal = CalorieEstimator.caloriesForActivity(
                met: state.met, minutes: elapsed / 60.0, bodyWeightLb: profile.weightLb
            )
            // Pilates routes to its own model so it credits the pilates weekly
            // streak, exactly as LiveSessionCard.end() does.
            if state.activityId == ActivityCatalog.pilatesId {
                Repos.logPilatesSession(ctx, PilatesSessionDTO(
                    profileId: profile.id, date: state.startDate,
                    durationMinutes: actualMinutes, focusAreas: []
                ))
            } else {
                Repos.logActivitySession(ctx, ActivitySessionDTO(
                    profileId: profile.id, date: state.startDate,
                    activityId: state.activityId, activityName: state.activityName,
                    met: state.met, durationMinutes: actualMinutes,
                    expectedMinutes: state.expectedMinutes, caloriesEst: cal
                ))
            }
            LiveSessionNotifier.cancel()
            LiveSessionStore.clear()
            if #available(iOS 16.2, *) {
                LiveSessionActivityController.end()
            }
            pushSnapshot(ctx, userId: profile.id)
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
