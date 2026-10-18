// Phone-side of the OurFitnessWatch companion app sync.
//
// Architecture: the watch is a thin client with no local SwiftData store; the
// phone is the sole source of truth. The phone pushes ONE
// `WatchSnapshotEnvelope` — today's numbers, quick-log movements,
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
    private var changeObservers: [NSObjectProtocol] = []
    private var snapshotTask: Task<Void, Never>?

    /// Coalesce save bursts and goal/session changes into one latest-state push.
    private func scheduleSnapshot() {
        guard WCSession.isSupported(), WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        snapshotTask?.cancel()
        snapshotTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, let container = self.container else { return }
            let ctx = container.mainContext
            guard let profile = self.activeProfile(ctx) else { return }
            self.pushSnapshot(ctx, userId: profile.id)
        }
    }

    private override init() {
        super.init()
    }

    /// Call once from `OurFitnessApp.init()`, right after the container is built.
    func activate(container: ModelContainer) {
        self.container = container
        if changeObservers.isEmpty {
            for name in [Notification.Name.repositoryDidSave, .liveSessionDidChange,
                         UserDefaults.didChangeNotification] {
                changeObservers.append(NotificationCenter.default.addObserver(
                    forName: name, object: nil, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.scheduleSnapshot() }
                })
            }
        }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Builds and pushes the whole `WatchSnapshotEnvelope` for one profile. Call
    /// after activation, on `scenePhase == .active`, and after every mutation the
    /// watch can see.
    ///
    /// Deliberately ONE build-everything pass: `updateApplicationContext` replaces
    /// the entire context dictionary, so there is no such thing as pushing "just
    /// the meals" or "just today" — see Shared/WatchSyncPayload.swift's header.
    /// The rule throughout is one fetch per entity, folded in memory; never a
    /// per-row fetch inside a loop.
    func pushSnapshot(_ ctx: ModelContext, userId: UUID) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        // The profile carries body weight, which the watch needs for DISPLAYING
        // (never computing) calorie figures, plus the fitness goal that still
        // rides the wire as `mode` for older watch builds (the current watch
        // never reads it). Without a profile there is no envelope to build.
        guard let profile = Repos.listProfiles(ctx).first(where: { $0.id == userId }) else { return }

        let now = Date()
        let todayKey = Dates.dayKey(now)

        // ONE fetch of the whole food log, reused three ways: today's totals, the
        // 30-day affinity ranking, and the name/macro lookup that resolves the
        // ranked ids. Fetching per purpose would triple the same query.
        let window = Dates.lastNDays(30, end: now)
        let allLogs = Repos.foodLogs(ctx, userId: userId, inDayRange: window[0]...todayKey)

        let envelope = WatchSnapshotEnvelope(
            profileId: userId,
            profileName: profile.name,
            mode: profile.fitnessGoal.rawValue,
            bodyWeightLb: profile.weightLb,
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
        // NOT `try?`. The application context is a size-limited dictionary, and
        // `quickLogExercises` (every exercise the profile owns)
        // is uncapped — so this call CAN start failing on a heavy profile. Swallowed, the symptom is a watch that silently stops
        // updating forever; logged, the size is at least visible in a console.
        do {
            try WCSession.default.updateApplicationContext([WatchSyncKeys.snapshotContextKey: data])
        } catch {
            print("[WatchSync] updateApplicationContext failed (\(data.count) bytes):", error.localizedDescription)
        }
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

        let steps = Steps.stepsForDay(Repos.steps(ctx, userId: profile.id, on: todayKey), day: todayKey)
        // Mirrors MoveCard/TodayView: the per-profile override is an Int where
        // 0 (or absent) means "use the plan's target".
        let customStepsGoal = Self.intDefault("stepsGoal.\(uid)") ?? 0
        let water = Water.total(Repos.water(ctx, userId: profile.id, on: todayKey), on: todayKey)
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

    /// The one-tap rows of the Train tab's `ExercisesCard` — every exercise owned
    /// by the profile that `isOneTapLoggable`, name-sorted — so the two devices show
    /// those rows in the same order. `loggedToday` is the SUM OF REPS (for a duration exercise the
    /// reps field carries minutes), matching the card's per-row count exactly.
    /// Only exercises a single tap can record CORRECTLY.
    ///
    /// `.logQuickSet` writes `reps: amount` and no typed weight (only a fixed
    /// exercise's own `loadLb`, stamped phone-side) — there is no
    /// weight input on the wrist and no hold timer. So:
    ///   • lifts that track a per-set weight (`ExerciseDTO.tracksPerSetWeight`:
    ///     compound/isolation rep work with no fixed load) are excluded. A
    ///     wrist "+1" on a barbell press logged a weightless rep that then
    ///     counted toward training volume. Wrong data is worse than a
    ///     missing button.
    ///   • isometric exercises are excluded. A hold is `{reps: 1, holdSeconds: N}`
    ///     billed by `caloriesForIsometric`; one tap would log it as a rep.
    /// Both rules are `ExerciseDTO.isOneTapLoggable`. The parenting movements
    /// and other bodyweight/duration work pass it — they carry a fixed `loadLb`
    /// (or none) on the exercise, which the calorie math already uses, so a
    /// tap records exactly what happened.
    ///
    /// Adding either back means a wire field plus a real input affordance, not
    /// just lifting this filter.
    private func quickLogExercises(_ ctx: ModelContext, userId: UUID, now: Date) -> [QuickLogExercise] {
        let exercises = Repos.exercises(ctx, forProfile: userId).filter(\.isOneTapLoggable)
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
    // boxed object and let nil mean absent.

    private static func doubleDefault(_ key: String) -> Double? {
        (UserDefaults.standard.object(forKey: key) as? NSNumber)?.doubleValue
    }

    private static func intDefault(_ key: String) -> Int? {
        (UserDefaults.standard.object(forKey: key) as? NSNumber)?.intValue
    }

    /// Applies a wrist-initiated action. EVERY case must end with the phone's
    /// state pushed back, so the watch sees the result of its own action with no
    /// extra round trip.
    ///
    /// Each case calls `pushSnapshot` itself after its write; that is the whole
    /// reason each of them resolves the active profile first.
    ///
    /// Nothing here trusts a number from the wire that it could derive itself:
    /// calories are recomputed from the real exercise/session and the profile's
    /// current weight, and meal macros are re-resolved by id — a snapshot the
    /// watch cached days ago must not be able to write stale figures.
    private func apply(_ action: WatchAction) {
        guard let container else { return }
        let ctx = container.mainContext
        defer { scheduleSnapshot() } // Reconcile optimistic wrist state even after a rejected/failed action.

        switch action {
        case .logWater(let flOz, let date):
            guard flOz.isFinite, flOz > 0, flOz <= 1024,
                  SessionInputValidation.validDate(date, now: Date()), let profile = activeProfile(ctx) else { return }
            guard Repos.addWater(ctx, WaterEntryDTO(userId: profile.id, date: Dates.dayKey(date), flOz: flOz, timestamp: date)) else { return }
            // Keep the phone's tap-to-repeat amount in step with the wrist's, so
            // WaterQuickLogButton offers what the user last actually drank.
            UserDefaults.standard.set(flOz, forKey: "waterLastFlOz.\(profile.id.uuidString)")
            pushSnapshot(ctx, userId: profile.id)

        case .logQuickSet(let exerciseId, let amount, let date):
            guard (1...10000).contains(amount), SessionInputValidation.validDate(date, now: Date()),
                  let profile = activeProfile(ctx),
                  let exercise = Repos.exercises(ctx, forProfile: profile.id)
                    .first(where: { $0.id == exerciseId })
            else { return }
            // The same shape dispatch every phone logging/edit surface uses
            // (duration bills by the minute, rep exercises by the rep), so a
            // wrist log and a later phone edit store the same figure. Computed
            // here from the stored exercise, never sent over the wire.
            // A fixed-load movement stamps the load it is done at (resolved here
            // from the stored exercise, not the wire), so editing the exercise's
            // weight later never re-reads a wrist log.
            let load = exercise.fixedLoadLb(forRowWeight: nil, holdSeconds: nil)
            let cal = CalorieEstimator.caloriesForSet(
                exercise: exercise, reps: amount, holdSeconds: nil,
                bodyWeightLb: profile.weightLb, loadLb: load)
            // `date` (not now) so an action queued offline lands on the day it
            // was taken — which is also the day the watch already counted it on.
            guard Repos.addSet(ctx, WorkoutSetDTO(
                userId: profile.id, exerciseId: exercise.id, weightLb: load,
                reps: amount, timestamp: date, caloriesEst: cal
            )) else { return }
            pushSnapshot(ctx, userId: profile.id)

        case .undoQuickSet(let exerciseId, let date):
            guard let profile = activeProfile(ctx) else { return }
            let dayKey = Dates.dayKey(date)
            // setHistory is one exercise-scoped fetch, newest first; narrowing to
            // the action's day keeps an offline undo from eating yesterday's set.
            guard let latest = Repos.setHistory(ctx, userId: profile.id, exerciseId: exerciseId)
                .first(where: { Dates.dayKey($0.timestamp) == dayKey })
            else { return }
            guard Repos.deleteSet(ctx, id: latest.id) else { return }
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
                guard Repos.addFoodLog(ctx, FoodLogEntryDTO(
                    userId: profile.id, date: dayKey, slot: slotValue,
                    customName: template.name, perServing: template.totalPerServing,
                    timestamp: date, ingredients: template.ingredients
                )) else { return }
            } else {
                guard let entry = Self.loggedFoodIndex(Repos.listFoodLog(ctx, userId: profile.id))[shortcutId] else {
                    print("[WatchSync] logMeal: food \(shortcutId) not in this profile's log history — ignored")
                    return
                }
                guard Repos.addFoodLog(ctx, FoodLogEntryDTO(
                    userId: profile.id, date: dayKey, slot: slotValue,
                    foodId: shortcutId, customName: entry.name,
                    perServing: entry.perServing, timestamp: date
                )) else { return }
            }
            pushSnapshot(ctx, userId: profile.id)

        case .startLiveSession(let activityId, _, let met, let expectedMinutes, let startDate):
            guard let profile = activeProfile(ctx),
                  let state = SessionInputValidation.start(
                    activityId: activityId, suppliedMET: met, expectedMinutes: expectedMinutes,
                    startDate: startDate, profileId: profile.id, now: Date()) else { return }
            let activityName = state.activityName
            // Both devices can start a session. Keep whichever started LATER —
            // an earlier start arriving now is a stale queued action, not the
            // session the user is actually in — and say which one was dropped.
            if let existing = LiveSessionStore.active(for: profile.id) {
                guard state.startDate > existing.startDate else {
                    return
                }
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
            guard let profile = activeProfile(ctx) else { return }
            _ = LiveSessionCompletionService.finish(
                ctx, profileId: profile.id, startDate: startDate,
                elapsedSeconds: elapsedSeconds, bodyWeightLb: profile.weightLb)
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
        Task { @MainActor in
            guard let container = self.container else { return }
            let ctx = container.mainContext
            // Only the active profile — every profile would overwrite the same
            // application-context key, leaving whichever pushed last on the watch.
            guard let profile = self.activeProfile(ctx) else { return }
            self.pushSnapshot(ctx, userId: profile.id)
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
