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

    private var todaysSteps: Int {
        stepModels.first(where: { $0.userId == profile.id && $0.date == today })?.steps ?? 0
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

                StepsCard(
                    steps: todaysSteps,
                    goal: profile.computedTargets.stepsDaily,
                    profileId: profile.id,
                    healthGranted: profile.healthGranted,
                    onConnectHealth: connectHealth
                )

                recentLogs
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

    // MARK: - Recent logs

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
                        Text("\(e.perServing.calories)")
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
