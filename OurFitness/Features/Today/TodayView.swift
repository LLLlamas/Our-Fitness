// Today tab — single-screen daily overview.
//
// One layout for everyone: macro rings | move | water | steps | today's food log.
// Strength, live sessions, Pilates, and the parenting movements live in the
// Train tab.
//
// Everything here is a READOUT. Steps live in exactly one card (`StepsCard`) —
// `MoveCard` deliberately shows none — and food logging lives only on the Meals
// tab, so this tab presents no add/edit affordance for either.

import SwiftUI
import SwiftData

struct TodayView: View {
    let profile: ProfileDTO
    @ObservedObject var health: HealthKitService

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter
    @State private var healthRefreshGeneration = 0

    @Query private var logModels: [FoodLogEntryModel]
    @Query private var stepModels: [StepCountModel]
    @Query private var waterModels: [WaterEntryModel]
    // For the once-a-day stall nudge (StallDetector). Sets/pilates/weights are
    // capped to the last 90 days; markers are low-volume lab entries (queried whole).
    @Query private var setModels: [WorkoutSetModel]
    @Query private var pilatesModels: [PilatesSessionModel]
    @Query private var bodyModels: [BodyMetricModel]
    @Query private var markerModels: [HealthMarkerModel]

    // Real HealthKit figures for StepsCard's pace line and week stats — loaded in
    // refreshToday(). nil / empty means "Health gave us nothing", and the card
    // hides those rows rather than showing zeros.
    @State private var intradayStepsToday: [Int] = []
    @State private var intradayStepsYesterday: [Int] = []
    @State private var activeEnergyCalThisWeek: Int?
    @State private var exerciseMinutesThisWeek: Int?

    @AppStorage("hasBackfilled.steps") private var hasBackfilledRaw: String = ""

    // One-shot-per-day flags for macro encouragement toasts. Comma-separated keys
    // stored in AppStorage so cold-launch re-fires are suppressed. Reset when the
    // day key rolls over. Same pattern as milestonesFired in StepsCard.
    // Keys: "protein-approaching", "protein-goal", "calorie-approaching", "calorie-goal"
    @AppStorage private var macroFiredRaw: String
    @AppStorage private var macroFlagDayKey: String

    // Mirror the same AppStorage keys used by StepsCard's goal picker (via
    // StepsGoalPrefs) so the streak calculation here uses the user's configured
    // goals, not the goal's defaults.
    @AppStorage private var customStepsGoalRaw: Int
    @AppStorage private var customWeeklyDaysRaw: Int

    // Water goal — mirrors the key used in WaterCard so nudges read the same value.
    @AppStorage private var waterGoalFlOz: Double

    // User-configurable nudge toggles — mirrored from SettingsView.
    @AppStorage("nudge.meal.enabled") private var mealNudgeEnabled: Bool = true
    @AppStorage("nudge.water.enabled") private var waterNudgeEnabled: Bool = true
    @AppStorage("nudge.stall.enabled") private var stallNudgeEnabled: Bool = true
    // Per-profile day key of the last stall check — fires the nudge at most once a
    // day, persisted so a cold relaunch doesn't re-fire it.
    @AppStorage private var stallNudgeDayKey: String

    // Time-based nudge state — tracks the last hour in which a nudge fired so
    // each kind fires at most once per hour. Reset on day rollover (via @State,
    // not AppStorage — a cold relaunch is fine to check again).
    @State private var lastMealNudgeHour: Int = -1
    @State private var lastWaterNudgeHour: Int = -1
    @State private var nudgeDayKey: String = ""

    // 30-minute repeating timer that triggers the periodic nudge check.
    private let nudgeTimer = Timer.publish(every: 1800, tolerance: 60, on: .main, in: .common).autoconnect()

    init(profile: ProfileDTO, health: HealthKitService) {
        self.profile = profile
        self._health = ObservedObject(wrappedValue: health)
        let uid = profile.id
        let todayKey = Dates.dayKey()
        // Bound to today. This tab renders one day — the day's macro totals,
        // its food log, and the nudge counts — so loading the user's whole
        // logging history to do it was pure cost, and cost that grew every day
        // they used the app.
        _logModels = Query(
            filter: #Predicate<FoodLogEntryModel> { $0.userId == uid && $0.date == todayKey },
            sort: \.timestamp,
            order: .forward
        )
        _stepModels = Query(
            filter: #Predicate<StepCountModel> { $0.userId == uid },
            sort: \.date,
            order: .reverse
        )
        _waterModels = Query(
            filter: #Predicate<WaterEntryModel> { $0.userId == uid },
            sort: \.timestamp,
            order: .forward
        )
        let stallCutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        _setModels = Query(
            filter: #Predicate<WorkoutSetModel> { $0.userId == uid && $0.timestamp >= stallCutoff },
            sort: \.timestamp, order: .reverse
        )
        _pilatesModels = Query(
            filter: #Predicate<PilatesSessionModel> { $0.profileId == uid && $0.date >= stallCutoff },
            sort: \.date, order: .reverse
        )
        _bodyModels = Query(
            filter: #Predicate<BodyMetricModel> { $0.userId == uid },
            sort: \.date, order: .forward
        )
        _markerModels = Query(
            filter: #Predicate<HealthMarkerModel> { $0.userId == uid },
            sort: \.date, order: .forward
        )
        _macroFiredRaw = AppStorage(wrappedValue: "", "macroFired.\(uid.uuidString)")
        _macroFlagDayKey = AppStorage(wrappedValue: "", "macroFiredDay.\(uid.uuidString)")
        _customStepsGoalRaw = AppStorage(wrappedValue: 0, StepsGoalPrefs.dailyKey(uid))
        _customWeeklyDaysRaw = AppStorage(
            wrappedValue: StepsGoalPrefs.defaultWeeklyDays, StepsGoalPrefs.weeklyDaysKey(uid)
        )
        _waterGoalFlOz = AppStorage(wrappedValue: Water.defaultGoalFlOz, "waterGoalFlOz.\(uid.uuidString)")
        _stallNudgeDayKey = AppStorage(wrappedValue: "", "stallNudgeDay.\(uid.uuidString)")
    }

    private var today: String { Dates.dayKey() }

    private var todayWaterOz: Double {
        Water.total(waterModels.map(\.snapshot), on: today)
    }

    /// Already today-only by predicate — no client-side date filter needed.
    private var todaysLogs: [FoodLogEntryDTO] { logModels.map(\.snapshot) }
    private var totals: DailyTotals { DailyTotals.totals(from: todaysLogs) }

    // Step data — StepsCard's ring, weekly strip and streak
    private var allStepsForProfile: [StepCountDTO] {
        stepModels.map(\.snapshot)
    }
    private var todaysSteps: Int {
        Steps.stepsForDay(allStepsForProfile, day: today)
    }
    private var weeklySteps: [Trends.Point] { Steps.series(allStepsForProfile, days: 7) }
    private var effectiveStepsGoal: Int {
        StepsGoalPrefs.resolve(custom: customStepsGoalRaw, goalDefault: profile.computedTargets.stepsDaily)
    }
    private var stepStreakWeeks: Int {
        Movement.stepWeeklyStreak(
            steps: allStepsForProfile,
            dailyGoal: effectiveStepsGoal,
            daysPerWeek: customWeeklyDaysRaw
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if HealthAccess.shouldPromptConnect(healthGranted: profile.healthGranted) {
                    connectHealthCard
                }

                Text("Today")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(theme.text)

                MacroQuadGrid(totals: totals, targets: profile.computedTargets, profile: profile)

                if profile.healthGranted {
                    MoveCard(profile: profile, health: health, refreshGeneration: healthRefreshGeneration)
                }

                WaterCard(profile: profile)

                // Tail: the one StepsCard, then today's food log.
                stepsCard
                recentLogs
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .scrollHapticTicks()
        }
        .background(theme.bg.ignoresSafeArea())
        .task(id: profile.id) {
            await backfillIfNeeded()
            // Anchor the profile (the source recommendations read) to the latest
            // logged body weight. No-op when nothing has been logged or it already
            // matches — also self-heals installs whose weight was logged before this
            // path existed. HealthKit sync below refreshes it further when granted.
            Repos.syncCurrentWeight(ctx, profileId: profile.id)
            await refreshToday()
            if profile.healthGranted {
                await health.syncFromHealth(profileId: profile.id, ctx: ctx)
            }
        }
        .refreshable {
            healthRefreshGeneration += 1
            await refreshToday()
            if profile.healthGranted {
                await health.syncFromHealth(profileId: profile.id, ctx: ctx)
            }
        }
        .onChange(of: totals) { _, newTotals in
            checkMacroMilestones(newTotals)
        }
        .onAppear {
            checkTimeNudges()
        }
        .onReceive(nudgeTimer) { _ in
            checkTimeNudges()
        }
    }

    // MARK: - Macro encouragement

    /// Fires approaching / goal-hit toasts for protein and calories, once per day
    /// each. Protein takes priority over calories when both would fire at once.
    /// Fired keys are stored in AppStorage so a cold launch on the same day does
    /// not re-fire toasts the user already saw.
    private func checkMacroMilestones(_ totals: DailyTotals) {
        // Reset the fired set when the calendar day rolls over.
        if macroFlagDayKey != today {
            macroFlagDayKey = today
            macroFiredRaw = ""
        }

        var fired = Set(macroFiredRaw.split(separator: ",").map(String.init))

        func markFired(_ key: String) { fired.insert(key); macroFiredRaw = fired.joined(separator: ",") }

        let targets = profile.computedTargets

        // Protein takes priority — if a protein toast fires this pass, skip calories.
        var proteinFiredThisPass = false
        if targets.proteinG > 0 {
            let pct = Double(totals.proteinG) / Double(targets.proteinG)
            if pct >= 1.0, !fired.contains("protein-goal") {
                markFired("protein-goal"); markFired("protein-approaching")
                proteinFiredThisPass = true
                toasts.macroGoalHit(EncouragementEngine.macroGoalHitMessage(macro: "protein", fitnessGoal: profile.fitnessGoal))
            } else if pct >= 0.85, !fired.contains("protein-approaching") {
                markFired("protein-approaching")
                proteinFiredThisPass = true
                let remaining = max(0, targets.proteinG - totals.proteinG)
                toasts.macroApproaching(EncouragementEngine.macroApproachingMessage(
                    macro: "protein", remaining: remaining, unit: "g", fitnessGoal: profile.fitnessGoal))
            }
        }

        guard !proteinFiredThisPass else { return }

        if targets.calories > 0 {
            let pct = Double(totals.calories) / Double(targets.calories)
            if pct >= 1.0, !fired.contains("calorie-goal") {
                markFired("calorie-goal"); markFired("calorie-approaching")
                toasts.macroGoalHit(EncouragementEngine.macroGoalHitMessage(macro: "calories", fitnessGoal: profile.fitnessGoal))
            } else if pct >= 0.90, !fired.contains("calorie-approaching") {
                markFired("calorie-approaching")
                let remaining = max(0, targets.calories - totals.calories)
                toasts.macroApproaching(EncouragementEngine.macroApproachingMessage(
                    macro: "calories", remaining: remaining, unit: " cal", fitnessGoal: profile.fitnessGoal))
            }
        }
    }

    // MARK: - Time-based nudges

    /// Fires meal-logging and water nudges at most once per hour per kind.
    /// Called on .onAppear and on the 30-minute nudgeTimer tick.
    private func checkTimeNudges() {
        let hour = Calendar.current.component(.hour, from: Date())
        let dayKey = today

        // Reset per-hour counters when the calendar day rolls over.
        if nudgeDayKey != dayKey {
            nudgeDayKey = dayKey
            lastMealNudgeHour = -1
            lastWaterNudgeHour = -1
        }

        let mealCount = todaysLogs.count

        // Meal nudge — ask the engine first so we only advance the guard when a
        // message would actually fire. This avoids marking the hour "used" during
        // quiet periods (e.g. before 11 AM) when the engine returns nil.
        if mealNudgeEnabled,
           hour != lastMealNudgeHour,
           EncouragementEngine.mealLoggingNudge(
               mealsLoggedToday: mealCount,
               hourOfDay: hour,
               fitnessGoal: profile.fitnessGoal
           ) != nil {
            toasts.mealNudge(mealsLoggedToday: mealCount, hourOfDay: hour, fitnessGoal: profile.fitnessGoal)
            lastMealNudgeHour = hour
        }

        // Water nudge — same pattern; separate hour guard from meal nudge.
        if waterNudgeEnabled,
           hour != lastWaterNudgeHour,
           EncouragementEngine.waterNudge(
               currentOz: todayWaterOz,
               goalOz: waterGoalFlOz,
               hourOfDay: hour
           ) != nil {
            toasts.waterReminder(currentOz: todayWaterOz, goalOz: waterGoalFlOz, hourOfDay: hour)
            lastWaterNudgeHour = hour
        }

        // Keep-going (stall) nudge — at most once per calendar day, lowest priority.
        // `detect` returns nil for active users, so most days this is a no-op. The day
        // key is set regardless of outcome (not only when a nudge fires): every stall
        // threshold is day-granular, so a stall can't newly flip true later the same
        // day, and this keeps the 30-min timer ticks from re-running detect all day.
        if stallNudgeEnabled, stallNudgeDayKey != dayKey {
            stallNudgeDayKey = dayKey
            if let stall = StallDetector.detect(
                fitnessGoal: profile.fitnessGoal,
                steps: allStepsForProfile,
                sets: setModels.map(\.snapshot),
                pilates: pilatesModels.map(\.snapshot),
                weights: bodyModels.map(\.snapshot),
                markers: markerModels.map(\.snapshot)
            ) {
                toasts.stallNudge(EncouragementEngine.stallMessage(stall, fitnessGoal: profile.fitnessGoal))
            }
        }
    }

    // MARK: - Steps

    // The one steps card (ring + weekly strip + week-to-date Health stats).
    // The only steps surface on Today — MoveCard shows none.
    @ViewBuilder
    private var stepsCard: some View {
        StepsCard(
            profile: profile,
            steps: todaysSteps,
            weeklySeries: weeklySteps,
            streakWeeks: stepStreakWeeks,
            intradayToday: intradayStepsToday,
            intradayYesterday: intradayStepsYesterday,
            activeEnergyKcalThisWeek: activeEnergyCalThisWeek,
            exerciseMinutesThisWeek: exerciseMinutesThisWeek
        )
    }

    /// Read-only. Adding, editing and deleting food all live on the Meals tab —
    /// one logging surface, not two — so these rows are plain `Card`s with no tap
    /// target and there is no add button. `todaysLogs` still feeds `MacroQuadGrid`
    /// and the meal nudge, so the day's food-log query stays.
    @ViewBuilder
    private var recentLogs: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's log")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.text)
            if todaysLogs.isEmpty {
                Card {
                    HStack(spacing: 12) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 22))
                            .foregroundStyle(theme.dim)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nothing logged yet")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(theme.text)
                            Text("Food is logged on the Meals tab.")
                                .font(.caption)
                                .foregroundStyle(theme.dim)
                        }
                        Spacer(minLength: 0)
                    }
                }
            } else {
                ForEach(todaysLogs) { e in
                    Card {
                        HStack {
                            Text(e.customName ?? "Meal")
                                .foregroundStyle(theme.text)
                            Spacer()
                            // Scaled by servings, matching the Meals row and the
                            // macro rings above. `perServing` here made the same
                            // entry read differently on Today than on Meals.
                            Text("\(e.totalNutrition.calories) cal")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(theme.accent)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Connect Apple Health

    @ViewBuilder
    private var connectHealthCard: some View {
        PressableCard(action: connectHealth) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(HealthAccess.statusLabel(healthGranted: profile.healthGranted))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.text)
                    Text("Steps, weight, RHR, and active energy. Apple Watch included.")
                        .font(.caption).foregroundStyle(theme.dim)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func connectHealth() {
        Task {
            let ok = await health.connectAndPersist(profileId: profile.id, ctx: ctx, toasts: toasts)
            if ok {
                await backfillIfNeeded()
                await refreshToday()
            }
        }
    }

    // MARK: - HealthKit sync

    private var backfilledProfileIds: Set<String> {
        Set(hasBackfilledRaw.split(separator: ",").map(String.init))
    }

    private func backfillIfNeeded() async {
        let key = profile.id.uuidString
        guard HealthAccess.shouldBackfill(
            healthGranted: profile.healthGranted,
            hasBackfilled: backfilledProfileIds.contains(key)
        ) else { return }
        // No requestAuthorization() here — see refreshToday(). Authorization
        // persists across launches; reads work without it, and auto-requesting
        // on launch risks an uncatchable Obj-C exception / SIGABRT.
        let map = await health.dailySteps(days: 30)
        for (date, count) in map where count > 0 {
            Repos.setSteps(ctx, userId: profile.id, date: date,
                           steps: count, source: .appleHealth)
        }
        var ids = backfilledProfileIds
        ids.insert(key)
        hasBackfilledRaw = ids.sorted().joined(separator: ",")
    }

    private func refreshToday() async {
        guard profile.healthGranted else { return }
        // Do NOT call requestAuthorization() here. HealthKit authorization
        // persists across launches, so reads work without re-requesting — and
        // requestAuthorization can raise a synchronous Obj-C NSException that
        // Swift try/catch cannot catch, which would crash on launch. Auth is
        // established only via the explicit, user-initiated Connect flow.
        let n = await health.steps()
        if n > 0 {
            Repos.setSteps(ctx, userId: profile.id, date: today,
                           steps: n, source: .appleHealth)
        }
        await refreshStepsCardExtras()
    }

    /// StepsCard's pace-vs-yesterday line and week-to-date stats. Reads
    /// only — no requestAuthorization on this path (see refreshToday()).
    private func refreshStepsCardExtras() async {
        intradayStepsToday = await health.hourlyCumulativeSteps()
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) {
            intradayStepsYesterday = await health.hourlyCumulativeSteps(for: yesterday)
        }
        activeEnergyCalThisWeek = await health.activeEnergyThisWeekCal()
        exerciseMinutesThisWeek = await health.exerciseMinutesThisWeek()
    }
}
