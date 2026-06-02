// Today tab — single-screen daily overview.
//
// Build mode:  macro rings | steps bar | recent food log
// Circuit mode: macro rings | steps ring + pilates + movements (Train absorbed here)
//
// Circuit absorbs the Train tab so the daily workout loop lives in one place.

import SwiftUI
import SwiftData

struct TodayView: View {
    let profile: ProfileDTO
    @ObservedObject var health: HealthKitService

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var logModels: [FoodLogEntryModel]
    @Query private var stepModels: [StepCountModel]

    @AppStorage("hasBackfilled.steps") private var hasBackfilledRaw: String = ""

    // One-shot-per-day flags for macro encouragement toasts. Comma-separated keys
    // stored in AppStorage so cold-launch re-fires are suppressed. Reset when the
    // day key rolls over. Same pattern as milestonesFired in StepsCardioCard.
    // Keys: "protein-approaching", "protein-goal", "calorie-approaching", "calorie-goal"
    @AppStorage private var macroFiredRaw: String
    @AppStorage private var macroFlagDayKey: String

    // Mirror the same AppStorage keys used in StepsCardioCard so the streak
    // calculation here uses the user's configured goals, not the mode defaults.
    @AppStorage private var customStepsGoalRaw: Int
    @AppStorage private var customWeeklyDaysRaw: Int

    init(profile: ProfileDTO, health: HealthKitService) {
        self.profile = profile
        self._health = ObservedObject(wrappedValue: health)
        let uid = profile.id
        _logModels = Query(
            filter: #Predicate<FoodLogEntryModel> { $0.userId == uid },
            sort: \.timestamp,
            order: .forward
        )
        _stepModels = Query(
            filter: #Predicate<StepCountModel> { $0.userId == uid },
            sort: \.date,
            order: .reverse
        )
        _macroFiredRaw = AppStorage(wrappedValue: "", "macroFired.\(uid.uuidString)")
        _macroFlagDayKey = AppStorage(wrappedValue: "", "macroFiredDay.\(uid.uuidString)")
        _customStepsGoalRaw = AppStorage(wrappedValue: 0, "stepsGoal.\(uid.uuidString)")
        _customWeeklyDaysRaw = AppStorage(wrappedValue: 5, "stepsWeeklyDays.\(uid.uuidString)")
    }

    private var today: String { Dates.dayKey() }

    private var todaysLogs: [FoodLogEntryDTO] {
        logModels.map(\.snapshot).filter { $0.date == today }
    }
    private var totals: DailyTotals { DailyTotals.totals(from: todaysLogs) }

    // Step data — used by both Build (linear bar) and Circuit (ring + strip)
    private var allStepsForProfile: [StepCountDTO] {
        stepModels.map(\.snapshot)
    }
    private var todaysSteps: Int {
        Steps.stepsForDay(allStepsForProfile, day: today)
    }
    private var weeklySteps: [Trends.Point] { Steps.series(allStepsForProfile, days: 7) }
    private var effectiveStepsGoal: Int {
        customStepsGoalRaw > 0 ? customStepsGoalRaw : profile.computedTargets.stepsDaily
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

                Text("today.")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(theme.text)

                MacroQuadGrid(totals: totals, targets: profile.computedTargets, profile: profile)

                if profile.healthGranted {
                    MoveCard(profile: profile, health: health)
                }

                WaterCard(profile: profile)

                if profile.mode == .circuit {
                    circuitContent
                } else {
                    buildContent
                }
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
            await refreshToday()
            if profile.healthGranted {
                await health.syncFromHealth(profileId: profile.id, ctx: ctx)
            }
        }
        .onChange(of: totals) { _, newTotals in
            checkMacroMilestones(newTotals)
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
                toasts.macroGoalHit(EncouragementEngine.macroGoalHitMessage(macro: "protein", mode: profile.mode))
            } else if pct >= 0.85, !fired.contains("protein-approaching") {
                markFired("protein-approaching")
                proteinFiredThisPass = true
                let remaining = max(0, targets.proteinG - totals.proteinG)
                toasts.macroApproaching(EncouragementEngine.macroApproachingMessage(
                    macro: "protein", remaining: remaining, unit: "g", mode: profile.mode))
            }
        }

        guard !proteinFiredThisPass else { return }

        if targets.calories > 0 {
            let pct = Double(totals.calories) / Double(targets.calories)
            if pct >= 1.0, !fired.contains("calorie-goal") {
                markFired("calorie-goal"); markFired("calorie-approaching")
                toasts.macroGoalHit(EncouragementEngine.macroGoalHitMessage(macro: "calories", mode: profile.mode))
            } else if pct >= 0.90, !fired.contains("calorie-approaching") {
                markFired("calorie-approaching")
                let remaining = max(0, targets.calories - totals.calories)
                toasts.macroApproaching(EncouragementEngine.macroApproachingMessage(
                    macro: "calories", remaining: remaining, unit: " cal", mode: profile.mode))
            }
        }
    }

    // MARK: - Circuit content (absorbed from Train tab)

    @ViewBuilder
    private var circuitContent: some View {
        LiveSessionCard(profile: profile)

        StepsCardioCard(
            profile: profile,
            todaysSteps: todaysSteps,
            weeklySeries: weeklySteps,
            intradayToday: [],
            intradayYesterday: [],
            activeEnergyKcalThisWeek: 0,
            exerciseMinutesThisWeek: 0,
            streakWeeks: stepStreakWeeks
        )
        focusFooter(.steps)

        Card { PilatesCard(profile: profile) }
        focusFooter(.pilates)

        BabyExercisesCard(profile: profile)
    }

    @ViewBuilder
    private func focusFooter(_ kind: Movement.CircuitFocusKind) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(Movement.circuitFocusBlurb(for: kind))
                .font(.caption).italic()
                .foregroundStyle(theme.dim)
            FocusInfoButton(kind: kind)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Build content

    @ViewBuilder
    private var buildContent: some View {
        StepsCard(
            steps: todaysSteps,
            goal: profile.computedTargets.stepsDaily,
            profileId: profile.id,
            healthGranted: profile.healthGranted,
            weightLb: profile.weightLb,
            mode: profile.mode,
            onConnectHealth: connectHealth
        )
        recentLogs
    }

    @ViewBuilder
    private var recentLogs: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's log")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.text)
            if todaysLogs.isEmpty {
                Text("Nothing logged yet. Head to Meals to add one.")
                    .font(.callout).foregroundStyle(theme.dim)
            } else {
                ForEach(todaysLogs) { e in
                    HStack {
                        Text(e.customName ?? "Meal")
                            .foregroundStyle(theme.text)
                        Spacer()
                        Text("\(e.perServing.calories) cal")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(theme.accent)
                    }
                    .padding(10)
                    .background(theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
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
    }
}

// MARK: - Focus info button (reused from Circuit context — now lives in TodayView)

private struct FocusInfoButton: View {
    let kind: Movement.CircuitFocusKind
    @State private var show = false
    @Environment(\.theme) private var theme

    var body: some View {
        Button { show = true } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(theme.dim)
        }
        .tactile(.ghost)
        .sheet(isPresented: $show) {
            FocusInfoSheet(kind: kind).themed(theme.mode)
        }
    }
}

private struct FocusInfoSheet: View {
    let kind: Movement.CircuitFocusKind
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(kind.title.uppercased())
                    .font(.caption).tracking(2).foregroundStyle(theme.dim)
                Text(kind.infoDetail)
                    .font(.callout).foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Divider().background(theme.line)
                Text(kind.citation)
                    .font(.caption2).foregroundStyle(theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.bg)
    }
}

private extension Movement.CircuitFocusKind {
    var title: String {
        switch self {
        case .steps:   return "Why steps?"
        case .pilates: return "Why pilates?"
        case .cardio:  return "Why cardio?"
        }
    }

    var infoDetail: String {
        switch self {
        case .steps:
            return "Walking is the easiest health win there is, and more is better. Every extra 1,000–2,000 steps a day lowers your risk of dying early, with most of the payoff landing by about 7,000–8,000 steps. Walking reliably brings blood pressure down a few points; effects on cholesterol and blood sugar are smaller and show up best when you also do some cardio.\n\nWorks: calves, thighs (quads), glutes (your seat muscles), hip flexors, and the deep core muscles that keep you upright. Over time: your heart, your everyday calorie burn, and your bones."
        case .pilates:
            return "Pilates builds core and posture strength, helps your balance, and eases lower-back pain. Doing it consistently for two months or more lowers the top blood-pressure number by about 4–5 points on average.\n\nWorks: the deep stomach muscle that acts like a built-in belt (transverse abdominis), the side-of-waist muscles (obliques), the muscles running up your spine (erector spinae), your glutes, and hip flexors — which ones depend on the focus area."
        case .cardio:
            return "Easy, steady cardio — a pace where you can still hold a conversation — strengthens your heart, nudges your 'good' cholesterol (HDL) up a couple of points, and lowers the fat circulating in your blood (triglycerides). Hitting the recommended 150 minutes a week lowers heart-disease risk by roughly 15–20%, with bigger drops as you do more.\n\nWorks: your heart most of all, plus your lower body (thighs, hamstrings, calves) and core."
        }
    }

    var citation: String {
        switch self {
        case .steps:
            return "Sources: Saint-Maurice et al., JAMA, 2020; Ding et al., Lancet Public Health, 2025 (steps and mortality); Hanson & Jones, Br J Sports Med, 2015 (blood pressure)."
        case .pilates:
            return "Source: Pilates and blood pressure meta-analysis, J Hum Hypertens, 2024."
        case .cardio:
            return "Sources: Sattelmair et al., Circulation, 2011; U.S. Physical Activity Guidelines, 2nd ed., 2018."
        }
    }
}
