// Meal log tab. One "Add food" sheet (AddFoodSheet) covers search, free-text
// describe, recipes, favorites and recents; "What are you in the mood for?"
// covers ideas. The day strip switches between recent days; the history
// button opens MealHistorySheet — a scrollable list of every logged day.

import SwiftUI
import SwiftData

struct NutritionView: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var logModels: [FoodLogEntryModel]
    @AppStorage private var favoriteIdsString: String
    @State private var showAddFood = false
    @State private var showMealHistory = false
    @State private var entryToDetail: FoodLogEntryDTO?
    @State private var showNutritionTrend = false
    @State private var showNutritionInsight = false
    @State private var showCameraLog = false
    @State private var showMoodSheet = false
    @State private var selectedDayKey: String = Dates.dayKey()
    // Tracks the logging streak across log events so we only celebrate a milestone
    // at the moment it's crossed (set on appear; compared on each new log).
    @State private var lastLoggingStreak = 0

    // MARK: - Smarter swaps state

    private enum AlternativesState {
        case idle
        case loading
        case loaded([FoodAlternative])
        case unavailable
    }

    @State private var alternativesState: AlternativesState = .idle

    init(profile: ProfileDTO) {
        self.profile = profile
        let uid = profile.id
        _favoriteIdsString = AppStorage(wrappedValue: "", "favoriteFoodIds.\(uid.uuidString)")
        _logModels = Query(
            filter: #Predicate<FoodLogEntryModel> { $0.userId == uid },
            sort: \.timestamp,
            order: .forward
        )
    }

    private var favoriteIds: Set<String> {
        Set(favoriteIdsString.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    private var favoriteFoods: [CommonFood] {
        let ids = favoriteIds
        return CommonFoods.all.filter { ids.contains($0.id) }
    }

    private var today: String { Dates.dayKey() }

    private var allLogs: [FoodLogEntryDTO] { logModels.map(\.snapshot) }

    private var todaysLogs: [FoodLogEntryDTO] {
        allLogs.filter { $0.date == today }
    }

    private func dayPillLabel(_ key: String) -> String {
        if key == today { return "Today" }
        let yesterday = Dates.dayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        if key == yesterday { return "Yesterday" }
        return Dates.formatShort(key)
    }

    /// Day strip: the last 7 days, newest first. An older day picked from the
    /// calendar (or the weekly trend sheet) is appended so it shows as selected.
    private var recentDayKeys: [String] {
        let week = Array(Dates.lastNDays(7).reversed())
        return week.contains(selectedDayKey) ? week : week + [selectedDayKey]
    }

    // "What are you in the mood for?" — AI (or the craving-matcher fallback)
    // suggests foods/meals for a free-text craving + constraints. Logs land on the
    // selected day.
    @ViewBuilder
    private var moodMealButton: some View {
        Button { showMoodSheet = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What are you in the mood for?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.text)
                    Text("Tell me your craving and calories")
                        .font(.caption).foregroundStyle(theme.dim)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.dim)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.line, lineWidth: 1))
        }
        .tactile(.ghost)
    }

    var body: some View {
        let allLogs = logModels.map(\.snapshot)
        let selectedDayLogs = allLogs.filter { $0.date == selectedDayKey }
        let todaysLogs = allLogs.filter { $0.date == today }
        let totals = DailyTotals.totals(from: selectedDayLogs)
        let mealLoggingStreak = Streaks.loggingStreak(allLogs)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Meals")
                        .font(.system(size: 56, weight: .regular))
                        .foregroundStyle(theme.text)
                    Button {
                        showNutritionInsight = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.dim)
                    }
                    .tactile(.ghost)
                    Spacer(minLength: 0)
                }

                daySelector(allLogs: allLogs)
                totalsCard(totals: totals, mealLoggingStreak: mealLoggingStreak)
                if profile.mode == .circuit {
                    // `entries:` lets the card tell "no label data for these foods"
                    // apart from "you ate almost no sodium" — see MacroBudget.capCoverage.
                    HeartHealthCard(totals: totals, targets: profile.computedTargets,
                                    profile: profile, entries: selectedDayLogs)
                }
                weeklyNutritionCard(allLogs: allLogs)

                moodMealButton

                if selectedDayKey == today {
                    smarterSwapsSection(allLogs: allLogs)
                }

                HStack(spacing: 10) {
                    Button {
                        showAddFood = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text(selectedDayKey == today ? "Add food" : "Add to \(dayPillLabel(selectedDayKey))")
                        }
                    }
                    .tactile(.primary, fullWidth: true)

                    // Camera scanner always logs to today (CameraFoodLogSheet).
                    if selectedDayKey == today {
                        Button {
                            showCameraLog = true
                        } label: {
                            Image(systemName: "camera.fill")
                        }
                        .tactile(.ghost)
                        .accessibilityLabel("Scan food label")
                    }
                }

                logList(selectedDayLogs: selectedDayLogs)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .scrollHapticTicks()
        }
        .background(theme.bg.ignoresSafeArea())
        .onAppear { lastLoggingStreak = mealLoggingStreak }
        .onChange(of: allLogs.count) { oldCount, newCount in
            // Only react to new logs (not deletions), and only celebrate when the
            // streak actually advances to a milestone day.
            guard newCount > oldCount else {
                lastLoggingStreak = mealLoggingStreak
                return
            }
            let streak = mealLoggingStreak
            if streak > lastLoggingStreak {
                toasts.mealStreak(days: streak, mode: profile.mode)
            }
            lastLoggingStreak = streak
        }
        .sheet(isPresented: $showAddFood) {
            AddFoodSheet(profile: profile, targetDate: selectedDayKey) { dto in
                // Don't toast or prefetch off a write that didn't commit.
                guard Repos.addFoodLog(ctx, dto) else { return }
                toasts.logged(dto.customName ?? "Meal", calories: dto.perServing.calories)
                let foodName = dto.foodId ?? dto.customName ?? ""
                if !foodName.isEmpty {
                    FoodAlternativeService.shared.prefetch(for: foodName, mode: profile.mode)
                }
            }
            .themed(profile.mode)
        }
        .sheet(isPresented: $showMealHistory) {
            MealHistorySheet(logs: allLogs) { dayKey in
                selectDay(dayKey)
            }
            .themed(profile.mode)
        }
        .sheet(item: $entryToDetail) { entry in
            MealIngredientDetailSheet(
                mode: .editing(entry: entry),
                profile: profile,
                onDone: { entryToDetail = nil }
            )
            .themed(profile.mode)
        }
        .sheet(isPresented: $showNutritionTrend) {
            NutritionTrendSheet(profile: profile, logs: allLogs) { dayKey in
                selectDay(dayKey)
            }
            .themed(profile.mode)
        }
        .sheet(isPresented: $showNutritionInsight) {
            NutritionInsightSheet(profile: profile, logs: allLogs)
                .themed(profile.mode)
        }
        .sheet(isPresented: $showCameraLog) {
            CameraFoodLogSheet(profile: profile, slot: .lunch) { dto in
                guard Repos.addFoodLog(ctx, dto) else { return }
                toasts.logged(dto.customName ?? "Meal", calories: dto.perServing.calories)
                let foodName = dto.foodId ?? dto.customName ?? ""
                if !foodName.isEmpty {
                    FoodAlternativeService.shared.prefetch(for: foodName, mode: profile.mode)
                }
            }
            .themed(profile.mode)
        }
        .sheet(isPresented: $showMoodSheet) {
            MoodMealSheet(
                profile: profile, totals: totals, targetDate: selectedDayKey,
                recentLogs: allLogs, favoriteFoodIds: favoriteIds
            ) { dto in
                guard Repos.addFoodLog(ctx, dto) else { return }
                toasts.logged(dto.customName ?? "Meal", calories: dto.perServing.calories)
                showMoodSheet = false
                let foodName = dto.foodId ?? dto.customName ?? ""
                if !foodName.isEmpty {
                    FoodAlternativeService.shared.prefetch(for: foodName, mode: profile.mode)
                }
            }
            .themed(profile.mode)
        }
        // Key on profile.id + the id of the most recent today's log so the section
        // refreshes when the user logs a new food today (subject changes), but not
        // on every single entry change (e.g. edits to older days).
        .task(id: "\(profile.id)-\(todaysLogs.last?.id.uuidString ?? "none")") {
            await loadAlternatives()
        }
    }

    // MARK: - Load AI alternatives

    private func loadAlternatives() async {
        guard FoodAlternativeService.shared.isAvailable else {
            alternativesState = .unavailable
            return
        }

        // Subject: the most recently logged food today. If today has no logs,
        // fall back to the most frequent food from the last 30 days. If neither
        // is available, skip loading.
        let targetFood: String
        if let lastToday = todaysLogs.last {
            targetFood = lastToday.foodId ?? lastToday.customName ?? ""
        } else {
            let frequents = FoodAlternativeService.shared.learnedFrequents(from: allLogs)
            targetFood = frequents.first ?? ""
        }

        guard !targetFood.isEmpty else {
            alternativesState = .unavailable
            return
        }

        let frequents = FoodAlternativeService.shared.learnedFrequents(from: allLogs)
        let favNames = favoriteFoods.map { $0.name }
        alternativesState = .loading
        let results = await FoodAlternativeService.shared.alternatives(
            for: targetFood,
            mode: profile.mode,
            recentFoodNames: frequents,
            favoriteFoodNames: favNames
        )
        alternativesState = results.isEmpty ? .unavailable : .loaded(results)
    }

    // MARK: - Weekly nutrition

    @ViewBuilder
    private func weeklyNutritionCard(allLogs: [FoodLogEntryDTO]) -> some View {
        let series = NutritionHistory.calorieSeries(allLogs, days: 7)
        let logged = NutritionHistory.daysLogged(allLogs, days: 7)
        let target = Double(profile.computedTargets.calories)
        if logged > 0 {
            PressableCard(action: { showNutritionTrend = true }) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("This week")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.text)
                        Spacer()
                        Text("\(logged)/7 days logged")
                            .font(.caption).foregroundStyle(theme.dim)
                        Image(systemName: "chart.bar.xaxis")
                            .font(.caption).foregroundStyle(theme.accent)
                    }
                    WeeklyBarStrip(series: series, goal: target, height: 42, barHeight: 40)
                }
            }
        }
    }

    /// Day strip: last 7 days (newest first) with a dot on days that have logs,
    /// plus a history button that lists every logged day further back.
    @ViewBuilder
    private func daySelector(allLogs: [FoodLogEntryDTO]) -> some View {
        let loggedDays = Set(allLogs.map(\.date))
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recentDayKeys, id: \.self) { key in
                        Button {
                            selectDay(key)
                        } label: {
                            HStack(spacing: 5) {
                                Text(dayPillLabel(key))
                                    .font(.system(size: 13, weight: .medium))
                                if loggedDays.contains(key) && selectedDayKey != key {
                                    Circle()
                                        .fill(theme.accent)
                                        .frame(width: 5, height: 5)
                                }
                            }
                        }
                        .tactile(.pill, fill: selectedDayKey == key ? theme.accent : nil)
                        .accessibilityLabel(loggedDays.contains(key) ? "\(dayPillLabel(key)), has entries" : dayPillLabel(key))
                    }
                }
            }
            Button {
                showMealHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .medium))
            }
            .tactile(.pill)
            .accessibilityLabel("Meal history")
        }
    }

    // MARK: - Smarter swaps

    /// Resolves to a non-empty list of AI alternatives only when the service has
    /// returned loaded results. Returns nil when we should show nothing.
    private var aiAlternativeItems: [FoodAlternative]? {
        if case .loaded(let items) = alternativesState, !items.isEmpty {
            return Array(items.prefix(3))
        }
        return nil
    }

    @ViewBuilder
    private func smarterSwapsSection(allLogs: [FoodLogEntryDTO]) -> some View {
        // Always show the Smarter Swaps section header. When AI has results,
        // show them with the whyBetter educational line. When AI is unavailable,
        // show the variety nudges as the fallback content.
        let aiItems = aiAlternativeItems
        let nudges = FoodVarietyNudges.nudges(from: allLogs, mode: profile.mode)

        // Only render if there's something to show: AI results, nudges, or loading.
        let isLoading: Bool = {
            if case .loading = alternativesState { return true }
            return false
        }()
        let hasContent = aiItems != nil || !nudges.isEmpty || isLoading

        if hasContent || FoodAlternativeService.shared.isAvailable {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.accent)
                    Text("Smarter swaps")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.text)
                }

                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Finding healthier swaps…")
                            .font(.caption).foregroundStyle(theme.dim)
                    }
                } else if let items = aiItems {
                    // AI alternatives — each carries a whyBetter research reason.
                    ForEach(items, id: \.item.food.id) { alt in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alt.item.food.name)
                                    .font(.callout)
                                    .foregroundStyle(theme.text)
                                Text("\(alt.item.scaledCalories) cal · \(alt.item.scaledProteinG)g protein")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(theme.dim)
                                if !alt.whyBetter.isEmpty {
                                    Text(alt.whyBetter)
                                        .font(.caption2).italic()
                                        .foregroundStyle(theme.dim)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 0)
                            Button {
                                let item = alt.item
                                let dto = FoodLogEntryDTO(
                                    userId: profile.id,
                                    date: selectedDayKey,
                                    slot: .lunch,
                                    foodId: item.food.id,
                                    customName: item.food.name,
                                    perServing: PerServing(
                                        calories: item.scaledCalories,
                                        proteinG: item.scaledProteinG,
                                        carbsG: item.scaledCarbsG,
                                        fatG: item.scaledFatG,
                                        fiberG: item.scaledFiberG
                                    )
                                )
                                guard Repos.addFoodLog(ctx, dto) else { return }
                                toasts.logged(item.food.name, calories: item.scaledCalories)
                                FoodAlternativeService.shared.prefetch(for: item.food.name, mode: profile.mode)
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                            .tactile(.ghost)
                            .accessibilityLabel("Log \(alt.item.food.name)")
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                    }

                    // Apple Intelligence attribution
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                            .foregroundStyle(theme.accent)
                        Text("Suggestions from Apple Intelligence. Calories and macros come from the food database, not the model.")
                            .font(.caption2)
                            .foregroundStyle(theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if !nudges.isEmpty {
                    // Variety nudges as fallback when AI is unavailable.
                    ForEach(nudges, id: \.headline) { nudge in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(nudge.emoji)
                                    .font(.system(size: 12))
                                Text(nudge.headline)
                                    .font(.caption).fontWeight(.medium)
                                    .foregroundStyle(theme.text)
                            }
                            Text(nudge.reason)
                                .font(.caption2).italic()
                                .foregroundStyle(theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(alignment: .top, spacing: 4) {
                                Text("→")
                                    .font(.caption2)
                                    .foregroundStyle(theme.accent2)
                                Text(nudge.alternative)
                                    .font(.caption2)
                                    .foregroundStyle(theme.dim)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                    }
                }
            }
        }
    }

    // MARK: - Totals card

    @ViewBuilder
    private func totalsCard(totals: DailyTotals, mealLoggingStreak: Int) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(selectedDayKey == today ? "Today" : Dates.formatLong(selectedDayKey))
                        .font(.caption).tracking(2).textCase(.uppercase)
                        .foregroundStyle(theme.dim)
                    Spacer()
                    // One walk, not three. `mealLoggingStreak` re-reads the
                    // whole food-log history every time it is touched.
                    let streak = mealLoggingStreak
                    if streak >= 2 {
                        Label("\(streak)-day streak", systemImage: "flame.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(theme.accent.opacity(0.12))
                            .clipShape(Capsule())
                            .accessibilityLabel("\(streak) day logging streak")
                    }
                }
                MacroQuadGrid(totals: totals, targets: profile.computedTargets, profile: profile)
                if selectedDayKey == today && totals.calories > 0 { toGoLine(totals: totals) }
            }
        }
    }

    /// Plain (non-ViewBuilder) copy + symbol for the "what's left today" line.
    private func toGoSummary(totals: DailyTotals) -> (text: String, symbol: String) {
        // What's left toward today's targets (and room under the Circuit caps).
        let remaining = MacroBudget.remaining(totals: totals, targets: profile.computedTargets)
        let calLeft = remaining.calories
        let proteinLeft = remaining.proteinG
        if calLeft > 0 {
            let t = proteinLeft > 0
                ? "\(calLeft) cal · \(proteinLeft)g protein to go"
                : "\(calLeft) cal to go · protein hit"
            return (t, "target")
        }
        return (profile.mode == .build
                ? "Calorie goal reached — nice."
                : "At your calorie target for the day.",
                "checkmark.circle.fill")
    }

    /// One-line "what's left today" headline that gives a reason to come back and
    /// close the day — calories + protein remaining, or a target-reached note.
    @ViewBuilder
    private func toGoLine(totals: DailyTotals) -> some View {
        let s = toGoSummary(totals: totals)
        HStack(spacing: 6) {
            Image(systemName: s.symbol)
                .font(.system(size: 11))
                .foregroundStyle(theme.accent)
            Text(s.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.dim)
        }
        .padding(.top, 2)
    }

    /// Single place the selected day changes, from the strip, the history sheet
    /// or the weekly trend sheet — so the animation and haptic stay identical.
    private func selectDay(_ key: String) {
        guard key != selectedDayKey else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            selectedDayKey = key
        }
        Haptics.selection()
    }

    // MARK: - Log list

    @ViewBuilder
    private func logList(selectedDayLogs: [FoodLogEntryDTO]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(selectedDayKey == today ? "Today's log" : Dates.formatLong(selectedDayKey))
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.text)
            let dayLogs = selectedDayLogs
            if dayLogs.isEmpty {
                emptyLogState
            } else {
                ForEach(dayLogs) { e in
                    LogRow(entry: e, onTap: { entryToDetail = e },
                           canDelete: true) {
                        guard Repos.deleteFoodLog(ctx, id: e.id) else { return }
                        Haptics.warn()
                        toasts.show(Toast(title: "Removed", detail: e.customName ?? "Meal", accent: .warn, symbol: "minus.circle.fill"))
                    }
                }
            }
        }
    }

    /// Inviting empty state instead of a dead "Nothing logged" line — turns the
    /// blank space into a one-tap on-ramp to logging.
    @ViewBuilder
    private var emptyLogState: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedDayKey == today ? "Nothing logged yet today" : "Nothing logged this day")
                        .font(.callout).fontWeight(.medium)
                        .foregroundStyle(theme.text)
                    Text(selectedDayKey == today
                         ? "Logging takes a few seconds and keeps your day honest."
                         : "Add what you ate to fill in this day.")
                        .font(.caption).foregroundStyle(theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                showAddFood = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text(selectedDayKey == today ? "Log your first meal" : "Log a meal")
                }
            }
            .tactile(.primary, fullWidth: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.line, lineWidth: 1))
    }
}

// MARK: - Log row

private struct LogRow: View {
    let entry: FoodLogEntryDTO
    let onTap: () -> Void
    var canDelete: Bool = true
    let onDelete: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        PressableCard(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.customName ?? "Meal")
                        .foregroundStyle(theme.text)
                    // Scaled by servings, so the row agrees with the day's totals.
                    Text("\(entry.totalNutrition.calories) cal · \(entry.totalNutrition.proteinG)g protein · \(entry.totalNutrition.carbsG)g carbs · \(entry.totalNutrition.fatG)g fat")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(theme.dim)
                }
                Spacer(minLength: 0)
                if canDelete {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                    }
                    .tactile(.ghost)
                    .accessibilityLabel("Remove \(entry.customName ?? "meal")")
                }
            }
        }
    }
}

// MARK: - Meal detail sheet

private struct MealDetailSheet: View {
    let meal: SuggestedMeal
    let onLog: (SuggestedMeal, Slot, Double) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var multiplier: Double = 1.0
    @State private var slot: Slot = .lunch

    private static let multipliers: [Double] = [0.5, 1.0, 1.5, 2.0]

    private var adjusted: PerServing {
        let ps = meal.perServing
        return PerServing(
            calories: Int(Double(ps.calories) * multiplier),
            proteinG: Int(Double(ps.proteinG) * multiplier),
            carbsG: Int(Double(ps.carbsG) * multiplier),
            fatG: Int(Double(ps.fatG) * multiplier),
            fiberG: Int(Double(ps.fiberG) * multiplier)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack(spacing: 12) {
                        Text(meal.emoji)
                            .font(.system(size: 44))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(meal.name)
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(theme.text)
                            if !meal.allergens.isEmpty {
                                Text(meal.allergens.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(theme.dim)
                            }
                        }
                    }

                    Text(meal.description)
                        .font(.callout).foregroundStyle(theme.dim)
                        .fixedSize(horizontal: false, vertical: true)

                    // Ingredients breakdown (if available)
                    let resolved = meal.resolvedIngredients()
                    if !resolved.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ingredients".uppercased())
                                .font(.system(size: 9, weight: .medium)).tracking(2)
                                .foregroundStyle(theme.dim)
                            ForEach(resolved) { ing in
                                let s = ing.scaledPerServing
                                HStack {
                                    Text(ing.name)
                                        .font(.callout).foregroundStyle(theme.text)
                                    Text(ing.servingLabel)
                                        .font(.caption).foregroundStyle(theme.dim)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text("\(s.calories) cal")
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(theme.text)
                                        Text("\(s.proteinG)g pro · \(s.carbsG)g carbs · \(s.fatG)g fat")
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(theme.dim)
                                    }
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(theme.card)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                            }
                        }
                    }

                    // How estimates are derived
                    VStack(alignment: .leading, spacing: 6) {
                        Text("About this estimate".uppercased())
                            .font(.system(size: 9, weight: .medium)).tracking(2)
                            .foregroundStyle(theme.dim)
                        Text("Macros are based on a standard single serving from curated recipe or published USDA data. If your portion was different, adjust the multiplier below.")
                            .font(.caption).foregroundStyle(theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .background(theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))

                    // Serving multiplier
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Serving size".uppercased())
                            .font(.caption).tracking(2).foregroundStyle(theme.dim)
                        HStack(spacing: 8) {
                            ForEach(Self.multipliers, id: \.self) { m in
                                Button {
                                    multiplier = m
                                } label: {
                                    Text(m == 0.5 ? "½×" : "\(Int(m))×")
                                        .font(.system(size: 14, weight: .medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                }
                                .tactile(.pill, fill: multiplier == m ? theme.accent : nil)
                            }
                        }
                    }

                    // Adjusted macros
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nutrition".uppercased())
                            .font(.caption).tracking(2).foregroundStyle(theme.dim)
                        HStack(spacing: 8) {
                            MacroChip(label: "Cal", value: adjusted.calories)
                            MacroChip(label: "Protein", value: adjusted.proteinG)
                            MacroChip(label: "Carbs", value: adjusted.carbsG)
                            MacroChip(label: "Fat", value: adjusted.fatG)
                            if adjusted.fiberG > 0 {
                                MacroChip(label: "Fiber", value: adjusted.fiberG)
                            }
                        }
                    }

                    // Slot picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Log as".uppercased())
                            .font(.caption).tracking(2).foregroundStyle(theme.dim)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach([Slot.breakfast, .lunch, .snack, .dinner, .postWorkout], id: \.self) { s in
                                    Button { slot = s } label: { Text(s.label) }
                                        .tactile(.pill, fill: slot == s ? theme.accent : nil)
                                }
                            }
                        }
                    }

                    // Log button
                    Button {
                        onLog(meal, slot, multiplier)
                        dismiss()
                    } label: {
                        Text("Log \(meal.name)")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .tactile(.primary, fullWidth: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle(meal.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") { dismiss() }
                        .tactile(.ghost)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
    }
}

// MARK: - Shared macro chip

/// Compact macro readout cell. Shared by the meal/food/logged-entry detail
/// sheets and the weekly nutrition trend sheet.
struct MacroChip: View {
    let label: String
    let value: Int
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(theme.text)
            Text(label)
                .font(.system(size: 9)).tracking(1)
                .foregroundStyle(theme.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }
}

// MARK: - Mood meal sheet

/// "What are you in the mood for?" — type a craving with loose constraints and get
/// food ideas. Apple Intelligence (when available) suggests real foods whose macros
/// are resolved from the food database; otherwise the deterministic
/// `MealCravingMatcher` ranks curated meals from history. The model never supplies
/// nutrition numbers.
private struct MoodMealSheet: View {
    let profile: ProfileDTO
    let totals: DailyTotals
    let targetDate: String
    let recentLogs: [FoodLogEntryDTO]
    let favoriteFoodIds: Set<String>
    let onPick: (FoodLogEntryDTO) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var craving: String = ""
    @State private var aiIdeas: [MealIdea] = []
    @State private var curatedMatches: [MealCravingMatcher.CravingMatch] = []
    @State private var loading = false
    @State private var usedAI = false
    @State private var hasSearched = false
    @State private var selectedMeal: SuggestedMeal?
    @FocusState private var focused: Bool

    private let examples = ["something salty", "something sweet", "high protein, ~500 cal", "light, not too hungry"]

    private var trimmed: String { craving.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Tell me your craving, how hungry you are, a rough calorie target — I'll suggest something that fits.")
                        .font(.callout).foregroundStyle(theme.dim)

                    HStack(spacing: 8) {
                        TextField("e.g. not too hungry, ~500 cal, salty", text: $craving)
                            .padding(10).background(theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                            .foregroundStyle(theme.text)
                            .focused($focused)
                            .submitLabel(.search)
                            .onSubmit { Task { await run() } }

                        Button { Task { await run() } } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(trimmed.isEmpty ? theme.dim : theme.accent)
                        }
                        .tactile(.ghost)
                        .disabled(trimmed.isEmpty)
                        .accessibilityLabel("Get ideas")
                    }

                    if !hasSearched {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(examples, id: \.self) { example in
                                Button {
                                    craving = example
                                    Task { await run() }
                                } label: {
                                    Text(example)
                                        .font(.system(size: 13))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 8).padding(.horizontal, 12)
                                        .background(theme.card)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                                        .foregroundStyle(theme.text)
                                }
                                .tactile(.ghost)
                            }
                        }
                    }

                    if loading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Finding ideas with Apple Intelligence…")
                                .font(.caption).foregroundStyle(theme.dim)
                        }
                    }

                    if !aiIdeas.isEmpty {
                        ForEach(Array(aiIdeas.enumerated()), id: \.offset) { _, idea in
                            foodIdeaRow(idea)
                        }
                    } else {
                        ForEach(curatedMatches) { match in
                            mealMatchRow(match)
                        }
                    }

                    if usedAI && !aiIdeas.isEmpty { aiAttribution }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle("In the mood…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.tactile(.ghost)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
        .sheet(item: $selectedMeal) { meal in
            MealDetailSheet(meal: meal) { m, s, multiplier in
                let ps = m.perServing
                let scaled = PerServing(
                    calories: Int(Double(ps.calories) * multiplier),
                    proteinG: Int(Double(ps.proteinG) * multiplier),
                    carbsG: Int(Double(ps.carbsG) * multiplier),
                    fatG: Int(Double(ps.fatG) * multiplier),
                    fiberG: Int(Double(ps.fiberG) * multiplier)
                )
                onPick(FoodLogEntryDTO(
                    userId: profile.id, date: targetDate, slot: s,
                    customName: m.name, perServing: scaled
                ))
                selectedMeal = nil
            }
            .themed(profile.mode)
        }
    }

    private func run() async {
        let g = trimmed
        guard !g.isEmpty else { return }
        focused = false
        hasSearched = true

        if MealIdeaService.shared.isAvailable {
            loading = true
            let recentNames = FoodAlternativeService.shared.learnedFrequents(from: recentLogs)
            let ideas = await MealIdeaService.shared.ideas(forCraving: g, mode: profile.mode, recentFoodNames: recentNames)
            loading = false
            if !ideas.isEmpty {
                aiIdeas = ideas
                curatedMatches = []
                usedAI = true
                Haptics.selection()
                return
            }
        }

        // Deterministic fallback — recommend from curated meals + the user's history.
        usedAI = false
        aiIdeas = []
        curatedMatches = MealCravingMatcher.matches(
            for: profile, craving: g, totals: totals,
            recentLogs: recentLogs, favoriteFoodIds: favoriteFoodIds
        )
        Haptics.selection()
    }

    @ViewBuilder
    private func foodIdeaRow(_ idea: MealIdea) -> some View {
        let item = idea.item
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.food.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.text)
                        Text("\(item.scaledCalories) cal · \(item.scaledProteinG)g pro · \(item.scaledCarbsG)g carbs · \(item.scaledFatG)g fat")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(theme.accent)
                    }
                    Spacer(minLength: 8)
                    Button { logFood(item) } label: {
                        Label("Log", systemImage: "plus")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .tactile(.pill, fill: theme.accent)
                }
                if !idea.why.isEmpty {
                    Text(idea.why)
                        .font(.callout).foregroundStyle(theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func mealMatchRow(_ match: MealCravingMatcher.CravingMatch) -> some View {
        let meal = match.meal
        PressableCard(action: { selectedMeal = meal }) {
            HStack(spacing: 12) {
                Text(meal.emoji).font(.system(size: 28))
                VStack(alignment: .leading, spacing: 4) {
                    Text(meal.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.text)
                    Text(match.reason)
                        .font(.caption).foregroundStyle(theme.dim)
                        .lineLimit(2)
                    Text("\(meal.perServing.calories) cal · \(meal.perServing.proteinG)g pro · \(meal.perServing.carbsG)g carbs · \(meal.perServing.fatG)g fat")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(theme.accent)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.dim)
            }
        }
    }

    private func logFood(_ item: FoodParser.ParsedItem) {
        onPick(FoodLogEntryDTO(
            userId: profile.id, date: targetDate, slot: .snack,
            foodId: item.food.id, customName: item.food.name,
            perServing: PerServing(
                calories: item.scaledCalories, proteinG: item.scaledProteinG,
                carbsG: item.scaledCarbsG, fatG: item.scaledFatG, fiberG: item.scaledFiberG
            )
        ))
    }

    @ViewBuilder
    private var aiAttribution: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 10)).foregroundStyle(theme.accent)
            Text("Ideas from Apple Intelligence, on-device. Calories and macros come from the food database, not the model.")
                .font(.caption2).foregroundStyle(theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }
}

// MARK: - Nutrition Insight Sheet

private struct NutritionInsightSheet: View {
    let profile: ProfileDTO
    let logs: [FoodLogEntryDTO]

    @Environment(\.theme) private var theme
    @Query private var markerModels: [HealthMarkerModel]
    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial

    init(profile: ProfileDTO, logs: [FoodLogEntryDTO]) {
        self.profile = profile
        self.logs = logs
        let uid = profile.id
        // HealthMarkerModel.date is a "yyyy-MM-dd" String; lexicographic sort == chronological for this format.
        _markerModels = Query(
            filter: #Predicate<HealthMarkerModel> { $0.userId == uid },
            sort: \.date, order: .reverse
        )
    }

    private var targets: MacroTargets { profile.computedTargets }

    private var avg7: DailyTotals { NutritionHistory.averagePerLoggedDay(logs, days: 7) }
    private var logged7: Int { NutritionHistory.daysLogged(logs, days: 7) }

    private var latestLDL: HealthMarkerDTO? {
        markerModels.map(\.snapshot).first { $0.kind == .ldl }
    }
    private var latestBP: HealthMarkerDTO? {
        markerModels.map(\.snapshot).first { $0.kind == .bpSystolic }
    }

    private var proteinStatus: String {
        guard logged7 > 0 else { return "No data yet — log a few days to see your average." }
        let pct = Int(Double(avg7.proteinG) / Double(targets.proteinG) * 100)
        if pct >= 90 { return "You're hitting your protein target — great for muscle support." }
        if pct >= 70 { return "Protein is a bit under target. Try adding eggs, Greek yogurt, or chicken." }
        return "Protein is well below target. Prioritise protein-dense foods at each meal."
    }

    private var calorieStatus: String {
        guard logged7 > 0 else { return "Log meals consistently to track your calorie pattern." }
        let pct = Int(Double(avg7.calories) / Double(targets.calories) * 100)
        switch profile.mode {
        case .build:
            if pct >= 95 { return "Calorie intake looks solid for muscle gain." }
            if pct >= 80 { return "Slightly under target — add a snack or larger portion to hit your surplus." }
            return "Calories are low for a building phase. Aim for the full \(targets.calories) cal daily."
        case .circuit:
            if pct <= 95 && pct >= 70 { return "Nice deficit — you're in the right calorie range for fat loss." }
            if pct > 95 { return "You're near maintenance. A small additional reduction helps the deficit." }
            return "Calories look very low. Make sure you're still fueling activity and recovery."
        }
    }

    private var modeBlurb: String {
        // Personalized to the user's own maintenance + surplus/deficit numbers.
        TargetRationale.goalLine(for: profile.mode) + "\n\n" + TargetRationale.calorieWhy(for: profile)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nutrition goals")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("YOUR TARGETS · PLAIN ENGLISH")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }

                infoBlock(icon: "target", title: "Your daily targets") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("**\(targets.calories) calories** — \(profile.mode == .build ? "surplus" : "slight deficit") from your maintenance")
                            .font(.callout).foregroundStyle(theme.text)
                        Text(unitSystem == .metric
                             ? "**\(targets.proteinG)g protein** — \(String(format: "%.1f", Double(targets.proteinG) / (profile.weightLb * Units.kgPerLb)))g per kilogram of body weight"
                             : "**\(targets.proteinG)g protein** — \(String(format: "%.1f", Double(targets.proteinG) / profile.weightLb))g per pound of body weight")
                            .font(.callout).foregroundStyle(theme.text)
                        Text("**\(targets.carbsG)g carbs** — primary fuel for movement and brain function")
                            .font(.callout).foregroundStyle(theme.text)
                        Text("**\(targets.fatG)g fat** — supports hormones, joint health, and fat-soluble vitamins")
                            .font(.callout).foregroundStyle(theme.text)
                    }
                }

                infoBlock(icon: "flame.fill", title: "What this means for you") {
                    Text(modeBlurb)
                        .font(.callout).foregroundStyle(theme.text)
                }

                if logged7 > 0 {
                    infoBlock(icon: "chart.bar.fill", title: "Your last \(logged7) logged days") {
                        VStack(alignment: .leading, spacing: 8) {
                            statRow(label: "Average calories", value: "\(avg7.calories) cal", target: "\(targets.calories) cal")
                            statRow(label: "Average protein", value: "\(avg7.proteinG)g", target: "\(targets.proteinG)g")
                            statRow(label: "Average carbs", value: "\(avg7.carbsG)g", target: "\(targets.carbsG)g")
                            statRow(label: "Average fat", value: "\(avg7.fatG)g", target: "\(targets.fatG)g")
                        }
                    }

                    infoBlock(icon: "person.fill", title: "Reading your data") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(calorieStatus).font(.callout).foregroundStyle(theme.text)
                            Text(proteinStatus).font(.callout).foregroundStyle(theme.text)
                        }
                    }
                }

                if latestLDL != nil || latestBP != nil {
                    infoBlock(icon: "heart.fill", title: "Dietary tips for your markers") {
                        VStack(alignment: .leading, spacing: 8) {
                            if latestLDL != nil {
                                Text("**Cholesterol on file** — limit saturated fat, choose oats, legumes, and fatty fish. Soluble fiber (oats, beans) actively lowers LDL.")
                                    .font(.callout).foregroundStyle(theme.text)
                            }
                            if latestBP != nil {
                                Text("**Blood pressure on file** — reduce sodium, increase potassium-rich foods (bananas, sweet potato, spinach). DASH diet pattern is well-supported.")
                                    .font(.callout).foregroundStyle(theme.text)
                            }
                        }
                    }
                }

                Text("Targets are estimated from your height, weight, age, activity level, and mode. Log consistently for the most accurate picture.")
                    .font(.caption).foregroundStyle(theme.dim)
                    .padding(10)
                    .background(theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
    }

    @ViewBuilder
    private func infoBlock<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.accent)
                Text(title.uppercased())
                    .font(.caption).tracking(2)
                    .foregroundStyle(theme.dim)
            }
            content()
        }
        .padding(14)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private func statRow(label: String, value: String, target: String) -> some View {
        HStack {
            Text(label).font(.callout).foregroundStyle(theme.text)
            Spacer()
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(theme.accent)
            Text("/ \(target)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(theme.dim)
        }
    }
}
