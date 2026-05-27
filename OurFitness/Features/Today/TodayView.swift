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

    private var today: String { Dates.dayKey() }

    private var todaysLogs: [FoodLogEntryDTO] {
        logModels.map(\.snapshot).filter { $0.userId == profile.id && $0.date == today }
    }
    private var totals: DailyTotals { DailyTotals.totals(from: todaysLogs) }

    // Step data — used by both Build (linear bar) and Circuit (ring + strip)
    private var allStepsForProfile: [StepCountDTO] {
        stepModels.map(\.snapshot).filter { $0.userId == profile.id }
    }
    private var todaysSteps: Int {
        Steps.stepsForDay(allStepsForProfile, day: today)
    }
    private var weeklySteps: [Trends.Point] { Steps.series(allStepsForProfile, days: 7) }
    private var stepStreakWeeks: Int {
        Movement.stepWeeklyStreak(
            steps: allStepsForProfile,
            dailyGoal: profile.computedTargets.stepsDaily
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

                MacroQuadGrid(totals: totals, targets: profile.computedTargets)

                if profile.mode == .circuit {
                    circuitContent
                } else {
                    buildContent
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background(theme.bg.ignoresSafeArea())
        .task(id: profile.id) {
            await backfillIfNeeded()
            await refreshToday()
        }
        .refreshable { await refreshToday() }
    }

    // MARK: - Circuit content (absorbed from Train tab)

    @ViewBuilder
    private var circuitContent: some View {
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
                    .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
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
        if !health.isAuthorized { _ = await health.requestAuthorization() }
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
        if !health.isAuthorized { _ = await health.requestAuthorization() }
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
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
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
            return "Walking is dose-responsive: every additional 2,000 steps/day reduces cardiovascular mortality risk by ~8–11%. Even modest increases (3,000–5,000 → 7,000–10,000) measurably lower LDL, systolic BP, and fasting insulin — without structured exercise.\n\nMuscles worked: calves, quads, glutes, hip flexors, core stabilisers. Long-term: cardiovascular system, metabolic rate, bone density."
        case .pilates:
            return "Core and postural strength from Pilates reduces lower-back pain, improves balance, and lowers resting BP through parasympathetic activation. ≥8 weeks of consistent training reduces systolic BP by 4–8 mmHg on average.\n\nMuscles worked: transverse abdominis, obliques, erector spinae, glutes, hip flexors — depends on focus area."
        case .cardio:
            return "Zone-2 cardio (conversational pace) trains mitochondrial density, raises HDL, lowers triglycerides, and improves insulin sensitivity. As little as 150 min/week of moderate activity reduces cardiovascular disease risk by ~35%.\n\nMuscles worked: heart (cardiac output), lower body (quads, hamstrings, calves), core stabilisers."
        }
    }

    var citation: String {
        switch self {
        case .steps:
            return "Source: Paluch et al., JAMA Network Open, 2021. Steps-per-day and all-cause mortality."
        case .pilates:
            return "Source: Kloubec JA, J Strength Cond Res, 2010; Bernardo LM, Clin J Oncol Nurs, 2007."
        case .cardio:
            return "Source: U.S. Physical Activity Guidelines Advisory Committee, 2018."
        }
    }
}
