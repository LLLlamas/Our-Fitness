import SwiftUI
import SwiftData

struct TodayView: View {
    let profile: ProfileDTO
    @ObservedObject var health: HealthKitService

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var foodModels: [FoodModel]
    @Query private var logModels: [FoodLogEntryModel]
    @Query private var stepModels: [StepCountModel]

    @State private var slot: Slot = .lunch
    @AppStorage("hasBackfilled.steps") private var hasBackfilledRaw: String = ""

    private var today: String { Dates.dayKey() }

    private var library: [FoodDTO] {
        foodModels.map(\.snapshot).filter { $0.modeFit.contains(profile.mode) }
    }

    private var todaysLogs: [FoodLogEntryDTO] {
        logModels.map(\.snapshot).filter { $0.userId == profile.id && $0.date == today }
    }

    private var totals: DailyTotals {
        todaysLogs.reduce(into: DailyTotals.zero) { acc, e in
            let p = e.perServing
            acc.calories += p.calories
            acc.proteinG += p.proteinG
            acc.carbsG += p.carbsG
            acc.fatG += p.fatG
            acc.fiberG += p.fiberG
            acc.sodiumMg += p.sodiumMg
            acc.addedSugarG += p.addedSugarG
            acc.saturatedFatG += p.saturatedFatG
        }
    }

    private var remaining: RemainingMacros {
        Suggestions.computeRemaining(totals: totals, targets: profile.computedTargets)
    }

    private var todaysSteps: Int {
        stepModels.first(where: { $0.userId == profile.id && $0.date == today })?.steps ?? 0
    }

    private var suggestions: [ScoredFood] {
        Suggestions.suggest(
            library: library, mode: profile.mode,
            restrictions: profile.restrictions, lowAppetite: profile.lowAppetite,
            slot: slot, remaining: remaining
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if HealthAccess.shouldPromptConnect(healthGranted: profile.healthGranted) {
                    connectHealthCard
                }

                banner

                Text("today.")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(theme.text)

                macroGrid

                StepsCard(
                    steps: todaysSteps,
                    goal: profile.computedTargets.stepsDaily,
                    sourceLabel: profile.healthGranted
                        ? "Synced from Apple Health"
                        : "Manual — tap a + or grant Health access",
                    onManualSave: { n in
                        Repos.setSteps(ctx, userId: profile.id, date: today,
                                       steps: n, source: .manual)
                    }
                )

                slotPicker

                suggestionsSection

                logSection
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
        .sensoryFeedback(.selection, trigger: slot)
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

    // MARK: - Banner

    @ViewBuilder
    private var banner: some View {
        if profile.mode == .build, !profile.restrictions.isEmpty {
            Banner(tone: .warn) {
                Text("**Allergen lock:** \(profile.restrictions.joined(separator: ", "))")
            }
        } else if profile.mode == .reset {
            resetCapsSection
        }
    }

    @ViewBuilder
    private var resetCapsSection: some View {
        let t = profile.computedTargets
        VStack(alignment: .leading, spacing: 10) {
            Text("Caps today")
                .font(.caption).tracking(2).textCase(.uppercase)
                .foregroundStyle(theme.dim)
            if let sodiumMax = t.sodiumMgMax {
                CapBar(
                    value: Double(totals.sodiumMg), target: Double(sodiumMax),
                    label: "Sodium", unit: "mg", inverted: true,
                    explanation: CapExplanations.sodium
                )
            }
            if let sugarMax = t.addedSugarGMax {
                CapBar(
                    value: Double(totals.addedSugarG), target: Double(sugarMax),
                    label: "Added Sugar", unit: "g", inverted: true,
                    explanation: CapExplanations.addedSugar
                )
            }
            // Sat-fat cap is derived once in Targets.compute (% of calories → g);
            // read it from the resolved target so view + scoring stay in sync.
            if let satFatMax = t.saturatedFatGMax {
                CapBar(
                    value: Double(totals.saturatedFatG), target: Double(satFatMax),
                    label: "Saturated Fat", unit: "g", inverted: true,
                    explanation: CapExplanations.saturatedFat
                )
            }
            if let minFiber = t.fiberGMin {
                CapBar(
                    value: Double(totals.fiberG), target: Double(minFiber),
                    label: "Fiber Floor", unit: "g", inverted: false,
                    explanation: CapExplanations.fiber
                )
            }
        }
        .padding(14)
        .background(theme.card)
        .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
    }

    // MARK: - Macros

    private var macroGrid: some View {
        let t = profile.computedTargets
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2),
            spacing: 14
        ) {
            ProgressBar(value: Double(totals.calories), target: Double(t.calories), label: "Calories")
            ProgressBar(value: Double(totals.proteinG), target: Double(t.proteinG), label: "Protein", unit: "g")
            ProgressBar(value: Double(totals.carbsG),   target: Double(t.carbsG),   label: "Carbs",   unit: "g")
            ProgressBar(value: Double(totals.fatG),     target: Double(t.fatG),     label: "Fat",     unit: "g")
        }
    }

    // MARK: - Slot picker

    private var slotPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([Slot.breakfast, .postWorkout, .lunch, .snack, .dinner], id: \.self) { s in
                    Button {
                        slot = s
                    } label: {
                        Text(s.label)
                    }
                    .tactile(.pill, fill: slot == s ? theme.accent : nil)
                }
            }
        }
    }

    // MARK: - Suggestions (tappable cards — no separate LOG IT button)

    @ViewBuilder
    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggested for \(slot.label)")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.text)
            if suggestions.isEmpty {
                Text("No suggestions fit your remaining headroom — try another slot.")
                    .font(.callout).foregroundStyle(theme.dim)
            } else {
                ForEach(suggestions) { sc in
                    PressableCard(action: { log(sc.food) }) {
                        FoodSuggestionRow(scored: sc)
                    }
                }
            }
        }
    }

    // MARK: - Log

    @ViewBuilder
    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's log")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.text)
            if todaysLogs.isEmpty {
                Text("Nothing logged yet. Tap a card above.")
                    .font(.callout).foregroundStyle(theme.dim)
            } else {
                ForEach(todaysLogs) { e in
                    LogRow(entry: e, foodName: library.first(where: { $0.id == e.foodId })?.name)
                        { Repos.deleteFoodLog(ctx, id: e.id); Haptics.tap() }
                }
            }
        }
    }

    // MARK: - Mutations

    private func log(_ food: FoodDTO) {
        let entry = FoodLogEntryDTO(
            userId: profile.id, date: today, slot: slot,
            foodId: food.id, servings: 1,
            perServing: food.perServing
        )
        Repos.addFoodLog(ctx, entry)
        toasts.logged(food.name, calories: food.perServing.calories)
    }

    private var backfilledProfileIds: Set<String> {
        Set(hasBackfilledRaw.split(separator: ",").map(String.init))
    }

    private func backfillIfNeeded() async {
        let key = profile.id.uuidString
        guard HealthAccess.shouldBackfill(
            healthGranted: profile.healthGranted,
            hasBackfilled: backfilledProfileIds.contains(key)
        ) else { return }
        if !health.isAuthorized { await health.requestAuthorization() }
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
        if !health.isAuthorized { await health.requestAuthorization() }
        let n = await health.steps()
        if n > 0 {
            Repos.setSteps(ctx, userId: profile.id, date: today,
                           steps: n, source: .appleHealth)
        }
    }
}

// MARK: - Sub-views

private struct FoodSuggestionRow: View {
    let scored: ScoredFood
    @Environment(\.theme) private var theme

    var body: some View {
        let f = scored.food
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(f.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.text)
                Spacer()
                Text(String(format: "$%.2f", f.costUsd))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(theme.accent2)
            }
            if let r = f.recipe {
                Text(r).font(.caption).foregroundStyle(theme.dim).lineLimit(2)
            }
            HStack(spacing: 14) {
                macroPill("\(f.perServing.calories) cal", color: theme.accent)
                macroPill("\(f.perServing.proteinG)p")
                macroPill("\(f.perServing.carbsG)c")
                macroPill("\(f.perServing.fatG)f")
            }
            if !scored.reasons.isEmpty {
                Text(scored.reasons.prefix(2).joined(separator: " · "))
                    .font(.caption2).italic().foregroundStyle(theme.dim)
            }
            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.caption2)
                    .foregroundStyle(theme.accent)
                Text("Tap to log")
                    .font(.caption2).tracking(2)
                    .foregroundStyle(theme.accent)
            }
        }
    }

    @ViewBuilder
    private func macroPill(_ text: String, color: Color? = nil) -> some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced))
            .tracking(1)
            .foregroundStyle(color ?? theme.text)
    }
}

private struct LogRow: View {
    let entry: FoodLogEntryDTO
    let foodName: String?
    let onDelete: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack {
            Text(entry.customName ?? foodName ?? "Custom")
                .foregroundStyle(theme.text)
            Spacer()
            Text("\(entry.perServing.calories)")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(theme.accent)
            Button(action: onDelete) {
                Image(systemName: "xmark")
            }
            .tactile(.ghost)
        }
        .padding(10)
        .background(theme.card)
        .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
    }
}
