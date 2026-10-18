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
    /// An add tapped while a past day is selected waits here for confirmation.
    private enum PendingAdd { case food, mood }
    @State private var pendingAdd: PendingAdd?
    @Environment(\.scenePhase) private var scenePhase
    @State private var wasBackgrounded = false
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

    private func dayPillLabel(_ key: String) -> String {
        if key == today { return "Today" }
        let yesterday = Dates.dayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        if key == yesterday { return "Yesterday" }
        return Dates.formatShort(key)
    }

    private var isPastDay: Bool { selectedDayKey != today }

    /// The tint every past-day surface shares (page, selected pill, add button,
    /// history sheet) so "not today" reads at a glance.
    private var pastTint: Color { theme.accent2 }

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
        Button { requestAdd(.mood) } label: {
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
                if isPastDay { pastDayBanner }
                // Logging first: the two ways in, then the day's log. Rings and
                // targets follow as the read-back.
                HStack(spacing: 10) {
                    Button {
                        requestAdd(.food)
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text(selectedDayKey == today ? "Add food" : "Add to \(dayPillLabel(selectedDayKey))")
                        }
                    }
                    .tactile(.primary, fill: isPastDay ? pastTint : nil, fullWidth: true)

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

                moodMealButton

                logList(selectedDayLogs: selectedDayLogs)

                totalsCard(totals: totals, mealLoggingStreak: mealLoggingStreak)
                // `entries:` lets the card tell "no label data for these foods"
                // apart from "you ate almost no sodium" — see MacroBudget.capCoverage.
                HeartHealthCard(totals: totals, targets: profile.computedTargets,
                                profile: profile, entries: selectedDayLogs)
                weeklyNutritionCard(allLogs: allLogs)

                if selectedDayKey == today {
                    smarterSwapsSection(allLogs: allLogs)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .scrollHapticTicks()
        }
        .background {
            ZStack {
                theme.bg
                if isPastDay { pastTint.opacity(0.12) }
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.25), value: isPastDay)
        }
        .onAppear {
            lastLoggingStreak = mealLoggingStreak
            // Coming back to the tab always lands on today.
            returnToToday()
        }
        .onChange(of: scenePhase) { _, new in
            // A fresh foreground is a fresh session: don't leave the log on a
            // past day from hours ago. iOS goes background → inactive → active
            // in two steps, so remember the background rather than pair phases.
            if new == .background { wasBackgrounded = true }
            if new == .active, wasBackgrounded {
                wasBackgrounded = false
                returnToToday()
            }
        }
        .confirmationDialog(
            "Add to \(dayPillLabel(selectedDayKey))?",
            isPresented: Binding(get: { pendingAdd != nil }, set: { if !$0 { pendingAdd = nil } }),
            titleVisibility: .visible
        ) {
            Button("Add to \(dayPillLabel(selectedDayKey))") { confirmPendingAdd() }
            Button("Add to today instead") {
                let kind = pendingAdd
                returnToToday()
                pendingAdd = nil
                if let kind { open(kind) }
            }
            Button("Cancel", role: .cancel) { pendingAdd = nil }
        } message: {
            Text("You're on \(Dates.formatLong(selectedDayKey)), not today.")
        }
        .onChange(of: allLogs.count) { oldCount, newCount in
            // Only react to new logs (not deletions), and only celebrate when the
            // streak actually advances to a milestone day.
            guard newCount > oldCount else {
                lastLoggingStreak = mealLoggingStreak
                return
            }
            let streak = mealLoggingStreak
            if streak > lastLoggingStreak {
                toasts.mealStreak(days: streak, fitnessGoal: profile.fitnessGoal)
            }
            lastLoggingStreak = streak
        }
        .sheet(isPresented: $showAddFood) {
            AddFoodSheet(profile: profile, targetDate: selectedDayKey) { dto in
                // Don't toast or prefetch off a write that didn't commit.
                guard Repos.addFoodLog(ctx, dto) else { return false }
                toasts.logged(dto.customName ?? "Meal", calories: dto.perServing.calories)
                let foodName = dto.foodId ?? dto.customName ?? ""
                if !foodName.isEmpty {
                    FoodAlternativeService.shared.prefetch(for: foodName, fitnessGoal: profile.fitnessGoal)
                }
                return true
            }
        }
        .sheet(isPresented: $showMealHistory) {
            MealHistorySheet(logs: allLogs) { dayKey in
                selectDay(dayKey)
            }
        }
        .sheet(item: $entryToDetail) { entry in
            MealIngredientDetailSheet(
                mode: .editing(entry: entry),
                profile: profile,
                onDone: { entryToDetail = nil }
            )
        }
        .sheet(isPresented: $showNutritionTrend) {
            NutritionTrendSheet(profile: profile, logs: allLogs) { dayKey in
                selectDay(dayKey)
            }
        }
        .sheet(isPresented: $showNutritionInsight) {
            NutritionInsightSheet(profile: profile, logs: allLogs)
        }
        .sheet(isPresented: $showCameraLog) {
            CameraFoodLogSheet(profile: profile, slot: .lunch) { dto in
                guard Repos.addFoodLog(ctx, dto) else { return false }
                toasts.logged(dto.customName ?? "Meal", calories: dto.perServing.calories)
                let foodName = dto.foodId ?? dto.customName ?? ""
                if !foodName.isEmpty {
                    FoodAlternativeService.shared.prefetch(for: foodName, fitnessGoal: profile.fitnessGoal)
                }
                return true
            }
        }
        .sheet(isPresented: $showMoodSheet) {
            MoodMealSheet(
                profile: profile, totals: totals, targetDate: selectedDayKey,
                recentLogs: allLogs, favoriteFoodIds: favoriteIds,
                onPick: { dto in
                    guard Repos.addFoodLog(ctx, dto) else { return }
                    toasts.logged(dto.customName ?? "Meal", calories: dto.perServing.calories)
                    showMoodSheet = false
                    let foodName = dto.foodId ?? dto.customName ?? ""
                    if !foodName.isEmpty {
                        FoodAlternativeService.shared.prefetch(for: foodName, fitnessGoal: profile.fitnessGoal)
                    }
                },
                onMealLogged: { mealName in
                    // The detail sheet already wrote, checked and toasted.
                    showMoodSheet = false
                    FoodAlternativeService.shared.prefetch(for: mealName, fitnessGoal: profile.fitnessGoal)
                }
            )
        }
        // Key on profile.id + the id of the most recent today's log so the section
        // refreshes when the user logs a new food today (subject changes), but not
        // on every single entry change (e.g. edits to older days).
        //
        // Both the id and the work take the snapshots `body` already built. Read
        // off computed properties, this line re-mapped the user's entire food-log
        // history into DTOs on every single pass of this view.
        .task(id: "\(profile.id)-\(todaysLogs.last?.id.uuidString ?? "none")") {
            await loadAlternatives(allLogs: allLogs, todaysLogs: todaysLogs)
        }
    }

    // MARK: - Load AI alternatives

    private func loadAlternatives(allLogs: [FoodLogEntryDTO], todaysLogs: [FoodLogEntryDTO]) async {
        guard FoodAlternativeService.shared.isAvailable else {
            alternativesState = .unavailable
            return
        }

        // One pass over the history: this is also the fallback subject below, and
        // it used to be derived twice in the no-logs-today path.
        let frequents = FoodAlternativeService.shared.learnedFrequents(from: allLogs)

        // Subject: the most recently logged food today. If today has no logs,
        // fall back to the most frequent food from the last 30 days. If neither
        // is available, skip loading.
        let targetFood: String
        if let lastToday = todaysLogs.last {
            targetFood = lastToday.foodId ?? lastToday.customName ?? ""
        } else {
            targetFood = frequents.first ?? ""
        }

        guard !targetFood.isEmpty else {
            alternativesState = .unavailable
            return
        }

        let favNames = favoriteFoods.map { $0.name }
        alternativesState = .loading
        let results = await FoodAlternativeService.shared.alternatives(
            for: targetFood,
            fitnessGoal: profile.fitnessGoal,
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
                        .tactile(.pill, fill: selectedDayKey == key ? (key == today ? theme.accent : pastTint) : nil)
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
        let nudges = FoodVarietyNudges.nudges(from: allLogs, fitnessGoal: profile.fitnessGoal)

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
                                FoodAlternativeService.shared.prefetch(for: item.food.name, fitnessGoal: profile.fitnessGoal)
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
                    // Passed in, not recomputed: `Streaks.loggingStreak` re-reads
                    // the whole food-log history, so `body` walks it once.
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
        // What's left toward today's targets (and room under the heart-health caps).
        let remaining = MacroBudget.remaining(totals: totals, targets: profile.computedTargets)
        let calLeft = remaining.calories
        let proteinLeft = remaining.proteinG
        if calLeft > 0 {
            let t = proteinLeft > 0
                ? "\(calLeft) cal · \(proteinLeft)g protein to go"
                : "\(calLeft) cal to go · protein hit"
            return (t, "target")
        }
        return (profile.fitnessGoal == .gain
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

    /// Banner under the day strip while a past day is selected: says where new
    /// food will land and offers the one-tap way back.
    @ViewBuilder
    private var pastDayBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(pastTint)
            Text("Viewing \(dayPillLabel(selectedDayKey)) — new food goes here")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Back to today") { returnToToday() }
                .font(.system(size: 13, weight: .semibold))
                .tactile(.pill)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(pastTint.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(pastTint, lineWidth: 1))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Every way into logging goes through here: on today it opens straight away;
    /// on a past day it asks first, so a log never lands on yesterday by habit.
    private func requestAdd(_ kind: PendingAdd) {
        if isPastDay { pendingAdd = kind } else { open(kind) }
    }

    private func confirmPendingAdd() {
        guard let kind = pendingAdd else { return }
        pendingAdd = nil
        open(kind)
    }

    private func open(_ kind: PendingAdd) {
        switch kind {
        case .food: showAddFood = true
        case .mood: showMoodSheet = true
        }
    }

    /// Snap the selection back to today with a short toast. The toast carries the
    /// haptic, so this doesn't go through `selectDay`. No-op when already on today.
    private func returnToToday() {
        guard isPastDay else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            selectedDayKey = today
        }
        toasts.show(Toast(title: "Back to today", accent: .info, symbol: "arrow.uturn.backward"), for: 1.0)
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
                    LogRow(entry: e, onTap: { entryToDetail = e }) {
                        guard Repos.deleteFoodLog(ctx, id: e.id) else { return }
                        // ToastCenter fires the .warn accent's haptic already.
                        toasts.show(Toast(title: "Removed", detail: e.customName ?? "Meal", accent: .warn, symbol: "minus.circle.fill"))
                    }
                }
            }
        }
    }

    /// Inviting empty state instead of a dead "Nothing logged" line. No button of
    /// its own: "Add food" sits directly above it, and two CTAs for one job is the
    /// duplicate rule 8 forbids.
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
                         : "Tap Add food to fill in this day.")
                        .font(.caption).foregroundStyle(theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                }
                .tactile(.ghost)
                .accessibilityLabel("Remove \(entry.customName ?? "meal")")
            }
        }
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
    /// A single AI-suggested food, logged straight from its row.
    let onPick: (FoodLogEntryDTO) -> Void
    /// A curated meal idea, already written by `MealIngredientDetailSheet`.
    let onMealLogged: (String) -> Void

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
        // A meal idea confirms in the one build-a-meal sheet, like every other
        // pick. That sheet does the guarded write + toast itself and calls
        // `onDone` only after a successful log.
        .sheet(item: $selectedMeal) { meal in
            MealIngredientDetailSheet(
                mode: .logging(name: meal.name, emoji: meal.emoji, defaultSlot: .lunch,
                               ingredients: ingredients(for: meal)),
                profile: profile,
                targetDate: targetDate,
                onDone: {
                    selectedMeal = nil
                    onMealLogged(meal.name)
                }
            )
        }
    }

    /// The meal's editable ingredients. A meal whose templates resolve to nothing
    /// in `CommonFoods` still logs — as one ingredient carrying the meal's own
    /// published per-serving numbers, which is what was logged before.
    private func ingredients(for meal: SuggestedMeal) -> [MealIngredient] {
        let resolved = meal.resolvedIngredients()
        guard resolved.isEmpty else { return resolved }
        return [MealIngredient(name: meal.name, servingLabel: "1 serving", perServing: meal.perServing)]
    }

    private func run() async {
        let g = trimmed
        guard !g.isEmpty else { return }
        focused = false
        hasSearched = true

        if MealIdeaService.shared.isAvailable {
            loading = true
            let recentNames = FoodAlternativeService.shared.learnedFrequents(from: recentLogs)
            let ideas = await MealIdeaService.shared.ideas(forCraving: g, fitnessGoal: profile.fitnessGoal, recentFoodNames: recentNames)
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
    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial

    private var targets: MacroTargets { profile.computedTargets }

    private var goalBlurb: String {
        TargetRationale.calorieWhy(for: profile)
    }

    var body: some View {
        let targets = self.targets
        let avg7 = NutritionHistory.averagePerLoggedDay(logs, days: 7)
        let logged7 = NutritionHistory.daysLogged(logs, days: 7)
        InfoSheetScaffold(title: "Nutrition goals", subtitle: "YOUR TARGETS · PLAIN ENGLISH") {
            InfoSection(title: "Your daily targets") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("**\(targets.calories) calories** — \(profile.fitnessGoal == .gain ? "surplus" : "slight deficit") from maintenance")
                        .font(.callout).foregroundStyle(theme.text)
                    Text(unitSystem == .metric
                         ? "**\(targets.proteinG)g protein** — \(String(format: "%.1f", Double(targets.proteinG) / (profile.weightLb * Units.kgPerLb)))g per kg"
                         : "**\(targets.proteinG)g protein** — \(String(format: "%.1f", Double(targets.proteinG) / profile.weightLb))g per lb")
                        .font(.callout).foregroundStyle(theme.text)
                    Text("**\(targets.carbsG)g carbs**")
                        .font(.callout).foregroundStyle(theme.text)
                    Text("**\(targets.fatG)g fat**")
                        .font(.callout).foregroundStyle(theme.text)
                }
            }

            Text(goalBlurb)
                .font(.callout).foregroundStyle(theme.text)

            if logged7 > 0 {
                InfoSection(title: "Your last \(logged7) logged days") {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoCalcRow(label: "Average calories", detail: "\(avg7.calories) cal / \(targets.calories) cal")
                        InfoCalcRow(label: "Average protein", detail: "\(avg7.proteinG)g / \(targets.proteinG)g")
                        InfoCalcRow(label: "Average carbs", detail: "\(avg7.carbsG)g / \(targets.carbsG)g")
                        InfoCalcRow(label: "Average fat", detail: "\(avg7.fatG)g / \(targets.fatG)g")
                    }
                }
            }
        }
    }
}
