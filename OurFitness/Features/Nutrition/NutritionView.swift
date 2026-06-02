// Meal log tab. Type what you ate; FoodParser resolves the nutrition.
// Suggestions pill surfaces curated meals from the library.

import SwiftUI
import SwiftData

/// Lightweight carrier for opening MealIngredientDetailSheet from a favorite food or recent log.
private struct QuickMealLog: Identifiable {
    let id = UUID()
    let name: String
    let emoji: String
    let ingredients: [MealIngredient]
}

struct NutritionView: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var logModels: [FoodLogEntryModel]
    @Query private var savedTemplates: [SavedMealTemplateModel]
    @AppStorage private var favoriteIdsString: String
    @State private var showLogSheet = false
    @State private var showSuggestions = false
    @State private var showLibrary = false
    @State private var mealToDetail: SuggestedMeal?
    @State private var mealToLog: QuickMealLog?
    @State private var entryToDetail: FoodLogEntryDTO?
    @State private var savedTemplateToLog: SavedMealTemplateDTO?
    @State private var showNutritionTrend = false
    @State private var showNutritionInsight = false
    @State private var selectedDayKey: String = Dates.dayKey()

    init(profile: ProfileDTO) {
        self.profile = profile
        let uid = profile.id
        _favoriteIdsString = AppStorage(wrappedValue: "", "favoriteFoodIds.\(uid.uuidString)")
        _logModels = Query(
            filter: #Predicate<FoodLogEntryModel> { $0.userId == uid },
            sort: \.timestamp,
            order: .forward
        )
        _savedTemplates = Query(
            filter: #Predicate<SavedMealTemplateModel> { $0.userId == uid },
            sort: \.createdAt, order: .reverse
        )
    }

    private var favoriteIds: Set<String> {
        Set(favoriteIdsString.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    private var favoriteFoods: [CommonFood] {
        let ids = favoriteIds
        return CommonFoods.all.filter { ids.contains($0.id) }
    }

    private var recentlyLogged: [FoodLogEntryDTO] {
        var seen = Set<String>()
        var result: [FoodLogEntryDTO] = []
        for log in allLogs.reversed() {
            let key = log.foodId ?? log.customName ?? log.id.uuidString
            if seen.insert(key).inserted {
                result.append(log)
                if result.count >= 6 { break }
            }
        }
        return result
    }

    private var today: String { Dates.dayKey() }

    private var allLogs: [FoodLogEntryDTO] { logModels.map(\.snapshot) }

    private var selectedDayLogs: [FoodLogEntryDTO] {
        allLogs.filter { $0.date == selectedDayKey }
    }

    private var todaysLogs: [FoodLogEntryDTO] {
        allLogs.filter { $0.date == today }
    }

    private var totals: DailyTotals { DailyTotals.totals(from: selectedDayLogs) }

    private func dayPillLabel(_ key: String) -> String {
        if key == today { return "Today" }
        let yesterday = Dates.dayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        if key == yesterday { return "Yesterday" }
        return Dates.formatShort(key)
    }

    private var recentDayKeys: [String] {
        Array(Dates.lastNDays(8).reversed())
    }

    private var rankedSuggestions: [SuggestedMeal] {
        SuggestedMeals.ranked(for: profile, totals: totals)
    }

    private var varietyNudges: [FoodVarietyNudge] {
        FoodVarietyNudges.nudges(from: allLogs, mode: profile.mode)
    }

    private func logMeal(_ meal: SuggestedMeal, slot: Slot = .lunch, multiplier: Double = 1.0) {
        let ps = meal.perServing
        let scaled = PerServing(
            calories: Int(Double(ps.calories) * multiplier),
            proteinG: Int(Double(ps.proteinG) * multiplier),
            carbsG: Int(Double(ps.carbsG) * multiplier),
            fatG: Int(Double(ps.fatG) * multiplier),
            fiberG: Int(Double(ps.fiberG) * multiplier)
        )
        let dto = FoodLogEntryDTO(
            userId: profile.id,
            date: today,
            slot: slot,
            customName: meal.name,
            perServing: scaled
        )
        Repos.addFoodLog(ctx, dto)
        toasts.logged(meal.name, calories: scaled.calories)
    }

    private func logCommonFood(_ food: CommonFood, slot: Slot = .lunch, multiplier: Double = 1.0) {
        let dto = FoodLogEntryDTO(
            userId: profile.id,
            date: today,
            slot: slot,
            foodId: food.id,
            customName: food.name,
            perServing: PerServing(
                calories: Int((Double(food.calories) * multiplier).rounded()),
                proteinG: Int((Double(food.proteinG) * multiplier).rounded()),
                carbsG: Int((Double(food.carbsG) * multiplier).rounded()),
                fatG: Int((Double(food.fatG) * multiplier).rounded()),
                fiberG: Int((Double(food.fiberG) * multiplier).rounded())
            )
        )
        Repos.addFoodLog(ctx, dto)
        toasts.logged(food.name, calories: dto.perServing.calories)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("meals.")
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
                    Button {
                        showSuggestions = true
                    } label: {
                        Label("suggestions", systemImage: "sparkles")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .tactile(.pill, fill: theme.accent)
                }

                totalsCard
                daySelector
                weeklyNutritionCard

                if selectedDayKey == today {
                    suggestionPillRow
                    nudgeSection
                }

                if selectedDayKey == today {
                    HStack(spacing: 10) {
                        Button {
                            showLogSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Log a meal")
                            }
                        }
                        .tactile(.primary, fullWidth: true)

                        Button {
                            showLibrary = true
                        } label: {
                            Label("Browse", systemImage: "magnifyingglass")
                        }
                        .tactile(.secondary)
                    }
                }

                logList
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .scrollHapticTicks()
        }
        .background(theme.bg.ignoresSafeArea())
        .sheet(isPresented: $showLogSheet) {
            NLMealLogSheet(profile: profile) { dto in
                Repos.addFoodLog(ctx, dto)
                toasts.logged(dto.customName ?? "Meal", calories: dto.perServing.calories)
            }
            .themed(profile.mode)
        }
        .sheet(isPresented: $showSuggestions) {
            SuggestionsSheet(profile: profile, totals: totals) { dto in
                Repos.addFoodLog(ctx, dto)
                toasts.logged(dto.customName ?? "Meal", calories: dto.perServing.calories)
                showSuggestions = false
            }
            .themed(profile.mode)
        }
        .sheet(isPresented: $showLibrary) {
            FoodLibrarySheet(profile: profile) { food, slot, multiplier in
                logCommonFood(food, slot: slot, multiplier: multiplier)
            }
            .themed(profile.mode)
        }
        .sheet(item: $mealToDetail) { meal in
            MealIngredientDetailSheet(
                mode: .logging(
                    name: meal.name,
                    emoji: meal.emoji,
                    defaultSlot: .lunch,
                    ingredients: meal.resolvedIngredients()
                ),
                profile: profile,
                onDone: { mealToDetail = nil }
            )
            .themed(profile.mode)
        }
        .sheet(item: $mealToLog) { meal in
            MealIngredientDetailSheet(
                mode: .logging(
                    name: meal.name,
                    emoji: meal.emoji,
                    defaultSlot: .lunch,
                    ingredients: meal.ingredients
                ),
                profile: profile,
                onDone: { mealToLog = nil }
            )
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
        .sheet(item: $savedTemplateToLog) { template in
            MealIngredientDetailSheet(
                mode: .logging(
                    name: template.name,
                    emoji: template.emoji,
                    defaultSlot: .lunch,
                    ingredients: template.ingredients
                ),
                profile: profile,
                onDone: { savedTemplateToLog = nil },
                onDeleteTemplate: {
                    Repos.deleteSavedTemplate(ctx, id: template.id)
                    Haptics.warn()
                    toasts.show(Toast(title: "Recipe deleted", detail: template.name, accent: .warn, symbol: "trash"))
                    savedTemplateToLog = nil
                }
            )
            .themed(profile.mode)
        }
        .sheet(isPresented: $showNutritionTrend) {
            NutritionTrendSheet(profile: profile, logs: allLogs) { dayKey in
                selectedDayKey = dayKey
            }
            .themed(profile.mode)
        }
        .sheet(isPresented: $showNutritionInsight) {
            NutritionInsightSheet(profile: profile, logs: allLogs)
                .themed(profile.mode)
        }
    }

    // MARK: - Weekly nutrition

    @ViewBuilder
    private var weeklyNutritionCard: some View {
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

    @ViewBuilder
    private var daySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(recentDayKeys, id: \.self) { key in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            selectedDayKey = key
                        }
                        Haptics.selection()
                    } label: {
                        Text(dayPillLabel(key))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .tactile(.pill, fill: selectedDayKey == key ? theme.accent : nil)
                }
            }
        }
    }

    // MARK: - Suggestion pill row

    @ViewBuilder
    private var suggestionPillRow: some View {
        let meals = rankedSuggestions
        let favorites = favoriteFoods
        let recents = recentlyLogged
        let hasContent = !savedTemplates.isEmpty || !favorites.isEmpty || !recents.isEmpty || !meals.isEmpty
        if hasContent {
            VStack(alignment: .leading, spacing: 14) {
                if !savedTemplates.isEmpty {
                    pillSection(header: "My Recipes") {
                        ForEach(savedTemplates) { template in
                            Button {
                                savedTemplateToLog = template.snapshot
                            } label: {
                                HStack(spacing: 6) {
                                    Text(template.emoji)
                                    Text(template.name)
                                }
                            }
                            .tactile(.pill)
                            .contextMenu {
                                Button(role: .destructive) {
                                    Repos.deleteSavedTemplate(ctx, id: template.id)
                                    Haptics.warn()
                                    toasts.show(Toast(title: "Recipe deleted", detail: template.name, accent: .warn, symbol: "trash"))
                                } label: {
                                    Label("Delete Recipe", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                if !favorites.isEmpty {
                    pillSection(header: "Favorites") {
                        ForEach(favorites) { food in
                            Button {
                                let ingredients: [MealIngredient] = SuggestedMeals.compositeIngredients[food.id]?
                                    .compactMap { $0.resolve() } ?? [MealIngredient.from(food)]
                                mealToLog = QuickMealLog(name: food.name, emoji: "🍽️", ingredients: ingredients)
                            } label: {
                                Text(food.name)
                            }
                            .tactile(.pill)
                        }
                    }
                }

                if !recents.isEmpty {
                    pillSection(header: "Recently Logged") {
                        ForEach(recents) { entry in
                            Button {
                                let ingredients: [MealIngredient]
                                if let ings = entry.ingredients, !ings.isEmpty {
                                    ingredients = ings
                                } else if let fid = entry.foodId,
                                          let food = CommonFoods.all.first(where: { $0.id == fid }) {
                                    ingredients = [MealIngredient.from(food)]
                                } else {
                                    ingredients = []
                                }
                                mealToLog = QuickMealLog(name: entry.customName ?? "Meal", emoji: "🍽️", ingredients: ingredients)
                            } label: {
                                Text(entry.customName ?? "Meal")
                            }
                            .tactile(.pill)
                        }
                    }
                }

                if !meals.isEmpty {
                    pillSection(header: "For You") {
                        ForEach(meals) { meal in
                            Button {
                                mealToDetail = meal
                            } label: {
                                HStack(spacing: 6) {
                                    Text(meal.emoji)
                                    Text(meal.name)
                                }
                            }
                            .tactile(.pill)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pillSection<Content: View>(header: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(header.uppercased())
                .font(.system(size: 10, weight: .medium)).tracking(2)
                .foregroundStyle(theme.dim)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    content()
                }
            }
        }
    }

    // MARK: - Variety nudges

    @ViewBuilder
    private var nudgeSection: some View {
        let nudges = varietyNudges
        if !nudges.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
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

    // MARK: - Totals card

    @ViewBuilder
    private var totalsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(selectedDayKey == today ? "Today" : Dates.formatLong(selectedDayKey))
                    .font(.caption).tracking(2).textCase(.uppercase)
                    .foregroundStyle(theme.dim)
                MacroQuadGrid(totals: totals, targets: profile.computedTargets, profile: profile)
            }
        }
    }

    // MARK: - Log list

    @ViewBuilder
    private var logList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(selectedDayKey == today ? "Today's log" : Dates.formatLong(selectedDayKey))
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.text)
            if selectedDayLogs.isEmpty {
                Text("Nothing logged \(selectedDayKey == today ? "yet" : "this day").")
                    .font(.callout).foregroundStyle(theme.dim)
            } else {
                ForEach(selectedDayLogs) { e in
                    LogRow(entry: e, onTap: { entryToDetail = e },
                           canDelete: selectedDayKey == today) {
                        Repos.deleteFoodLog(ctx, id: e.id)
                        Haptics.warn()
                        toasts.show(Toast(title: "Removed", detail: e.customName ?? "Meal", accent: .warn, symbol: "minus.circle.fill"))
                    }
                }
            }
        }
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
                    Text("\(entry.perServing.calories) cal · \(entry.perServing.proteinG)g protein · \(entry.perServing.carbsG)g carbs · \(entry.perServing.fatG)g fat")
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

// MARK: - NL Meal Log Sheet

private struct NLMealLogSheet: View {
    let profile: ProfileDTO
    let onSave: (FoodLogEntryDTO) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var input: String = ""
    @State private var parseResult: FoodParser.ParseResult? = nil
    @State private var parsedWithAI = false
    @State private var aiParsing = false
    @State private var slot: Slot = .lunch
    @State private var showManual = true

    @State private var manualCalories: Int = 0
    @State private var manualProtein: Int = 0
    @State private var manualCarbs: Int = 0
    @State private var manualFat: Int = 0

    private enum Field: Hashable { case input, cal, protein, carbs, fat }
    @FocusState private var focused: Field?

    private var resolvedPerServing: PerServing {
        if showManual {
            return PerServing(
                calories: manualCalories, proteinG: manualProtein,
                carbsG: manualCarbs, fatG: manualFat
            )
        }
        return parseResult?.totalPerServing ?? .zero
    }

    private var resolvedName: String {
        if let r = parseResult, r.hasMatches { return r.bestName }
        return input.trimmingCharacters(in: .whitespaces)
    }

    private var canSave: Bool {
        !resolvedName.isEmpty && resolvedPerServing.calories > 0
    }

    var body: some View {
        NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("log a meal.")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(theme.text)

                VStack(alignment: .leading, spacing: 6) {
                    Text("What did you eat?".uppercased())
                        .font(.system(size: 10)).tracking(2)
                        .foregroundStyle(theme.dim)
                    TextField("e.g. a bowl of rice and some grilled chicken", text: $input, axis: .vertical)
                        .lineLimit(1...3)
                        .padding(10).background(theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                        .foregroundStyle(theme.text)
                        .focused($focused, equals: .input)
                        .onSubmit { Task { await aiRefine() } }
                        .onChange(of: input) { _, _ in parseInput() }
                        .onChange(of: focused) { old, new in
                            if old == .input && new != .input { Task { await aiRefine() } }
                        }
                }

                if aiParsing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading your meal with Apple Intelligence…")
                            .font(.caption).foregroundStyle(theme.dim)
                    }
                }

                if let result = parseResult, !input.trimmingCharacters(in: .whitespaces).isEmpty {
                    parsedPreview(result)
                    if parsedWithAI { aiAttribution }
                }

                slotPicker
                nutritionSummary

                Button {
                    let mealIngredients = parseResult?.recognized.map {
                        MealIngredient.from($0.food, quantity: $0.quantity)
                    }
                    let dto = FoodLogEntryDTO(
                        userId: profile.id,
                        date: Dates.dayKey(),
                        slot: slot,
                        customName: resolvedName,
                        perServing: resolvedPerServing,
                        ingredients: mealIngredients
                    )
                    onSave(dto)
                    dismiss()
                } label: {
                    Text("Save")
                }
                .tactile(.primary, fullWidth: true)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("Log Meal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { dismiss() }
                    .tactile(.ghost)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
        }
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
    }

    /// Instant, deterministic string parse on every keystroke. Always the source of
    /// truth below iOS 26 / without Apple Intelligence, and the live preview while
    /// the user is still typing.
    private func parseInput() {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { parseResult = nil; parsedWithAI = false; return }
        parsedWithAI = false
        // Keystroke path: curated CommonFoods only — instant regardless of how large
        // the bundled USDA database grows. The full database is consulted on submit
        // (`aiRefine`) and in the library search, not on every keypress.
        applyResult(FoodParser.parse(text: trimmed, includeDatabase: false))
    }

    /// On end-editing/submit, ask the on-device model to re-parse the sentence into
    /// items, then resolve those names back through `FoodParser` so the NUMBERS stay
    /// from the food database (the model never supplies nutrition). Falls back
    /// silently to the string result already on screen on any failure / unavailability.
    private func aiRefine() async {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        // Re-entrancy guard: pressing Return fires both .onSubmit and the
        // focus-change trigger for one gesture — the second await-enqueued call
        // must no-op rather than race to overwrite the result. (@MainActor runs
        // the synchronous `aiParsing = true` before either call suspends.)
        guard !aiParsing, !trimmed.isEmpty else { return }

        // Submit path always consults the FULL database. When Apple Intelligence is
        // unavailable, do a one-shot full-DB string parse so submit still benefits
        // from USDA coverage the curated-only keystroke path skipped.
        guard MealParseService.shared.isAvailable else {
            applyResult(FoodParser.parse(text: trimmed, includeDatabase: true))
            return
        }

        aiParsing = true
        defer { aiParsing = false }
        guard let items = await MealParseService.shared.parse(trimmed) else {
            // AI ran but yielded nothing usable — fall back to the full-DB string parse.
            applyResult(FoodParser.parse(text: trimmed, includeDatabase: true))
            return
        }
        let resolved = FoodParser.resolve(items: items)
        guard resolved.hasMatches else {
            applyResult(FoodParser.parse(text: trimmed, includeDatabase: true))
            return
        }
        parsedWithAI = true
        aiParsing = false   // hide the spinner atomically with the result swap
        applyResult(resolved)
    }

    private func applyResult(_ result: FoodParser.ParseResult) {
        parseResult = result
        if result.hasMatches {
            let ps = result.totalPerServing
            manualCalories = ps.calories
            manualProtein  = ps.proteinG
            manualCarbs    = ps.carbsG
            manualFat      = ps.fatG
            showManual = false
        }
    }

    @ViewBuilder
    private var aiAttribution: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 10)).foregroundStyle(theme.accent)
            Text("Items parsed on-device by Apple Intelligence. Calories and macros come from the food database, not the model.")
                .font(.caption2).foregroundStyle(theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func parsedPreview(_ result: FoodParser.ParseResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if result.hasMatches {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recognised".uppercased())
                        .font(.system(size: 9, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                    ForEach(Array(result.recognized.enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(item.description)
                                .font(.callout).foregroundStyle(theme.text)
                            Spacer()
                            Text("\(item.scaledCalories) cal")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(theme.accent)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                    }
                }
            }
            if !result.unrecognized.isEmpty {
                Text("Not recognised: \(result.unrecognized.joined(separator: ", ")) — fill in below.")
                    .font(.caption).foregroundStyle(theme.dim)
            }
        }
    }

    @ViewBuilder
    private var nutritionSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Nutrition".uppercased())
                    .font(.system(size: 9, weight: .medium)).tracking(2)
                    .foregroundStyle(theme.dim)
                Spacer()
                if parseResult?.hasMatches == true {
                    Button {
                        showManual.toggle()
                    } label: {
                        Text(showManual ? "use parsed" : "edit")
                    }
                    .tactile(.ghost)
                }
            }

            if showManual {
                HStack(spacing: 10) {
                    numField("Calories", value: $manualCalories, field: .cal)
                    numField("Protein g", value: $manualProtein, field: .protein)
                }
                HStack(spacing: 10) {
                    numField("Carbs g", value: $manualCarbs, field: .carbs)
                    numField("Fat g", value: $manualFat, field: .fat)
                }
            } else {
                let ps = resolvedPerServing
                HStack(spacing: 8) {
                    macroChip(label: "Cal", value: ps.calories)
                    macroChip(label: "Protein", value: ps.proteinG)
                    macroChip(label: "Carbs", value: ps.carbsG)
                    macroChip(label: "Fat", value: ps.fatG)
                }
            }
        }
    }

    @ViewBuilder
    private func macroChip(label: String, value: Int) -> some View {
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

    @ViewBuilder
    private var slotPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Slot".uppercased())
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
    }

    @ViewBuilder
    private func numField(_ label: String, value: Binding<Int>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 9)).tracking(2)
                .foregroundStyle(theme.dim)
            TextField("", value: value, format: .number)
                .keyboardType(.numberPad)
                .padding(10).background(theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                .foregroundStyle(theme.text)
                .font(.system(.callout, design: .monospaced))
                .focused($focused, equals: field)
        }
    }
}

// MARK: - Suggestions Sheet

private struct SuggestionsSheet: View {
    let profile: ProfileDTO
    let totals: DailyTotals
    let onPick: (FoodLogEntryDTO) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMeal: SuggestedMeal?

    private var suggestions: [SuggestedMeal] {
        SuggestedMeals.ranked(for: profile, totals: totals, limit: 10)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Tap any meal to see info and adjust your portion.")
                        .font(.callout).foregroundStyle(theme.dim)

                    ForEach(suggestions) { meal in
                        PressableCard(action: { selectedMeal = meal }) {
                            HStack(spacing: 12) {
                                Text(meal.emoji)
                                    .font(.system(size: 28))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(meal.name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(theme.text)
                                    Text(meal.description)
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
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle("Suggestions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .tactile(.ghost)
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
                let dto = FoodLogEntryDTO(
                    userId: profile.id,
                    date: Dates.dayKey(),
                    slot: s,
                    customName: m.name,
                    perServing: scaled
                )
                onPick(dto)
                selectedMeal = nil
            }
            .themed(profile.mode)
        }
    }

}

// MARK: - Food Library Sheet

private struct FoodLibrarySheet: View {
    let profile: ProfileDTO
    let onLog: (CommonFood, Slot, Double) -> Void

    @AppStorage private var favoriteIdsString: String
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var displayedResults: [CommonFood] = CommonFoods.all
    @State private var foodToDetail: CommonFood?
    @FocusState private var searchFocused: Bool

    init(profile: ProfileDTO, onLog: @escaping (CommonFood, Slot, Double) -> Void) {
        self.profile = profile
        self.onLog = onLog
        _favoriteIdsString = AppStorage(wrappedValue: "", "favoriteFoodIds.\(profile.id.uuidString)")
    }

    private var favoriteIds: Set<String> {
        Set(favoriteIdsString.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    private func toggleFavorite(_ id: String) {
        var ids = favoriteIds
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        favoriteIdsString = ids.joined(separator: ",")
        Haptics.bump()
    }

    /// Pure search over curated + USDA foods. Static so the `.task` debounce can call
    /// it off the render path without capturing view state beyond the query string.
    private static func search(_ query: String) -> [CommonFood] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return CommonFoods.all }
        let curated = CommonFoods.all.filter { food in
            food.name.lowercased().contains(q)
                || food.aliases.contains { $0.lowercased().contains(q) }
        }
        // Broaden with the offline USDA database; curated entries win on name.
        // SQLite FTS5 query on disk — called off the render path by the debounced
        // `.task`, so it never scans synchronously in `body`.
        let curatedNames = Set(curated.map { $0.name.lowercased() })
        let usda = SQLiteFoodDatabase.shared.search(query: q, limit: 40)
            .map { $0.asCommonFood }
            .filter { !curatedNames.contains($0.name.lowercased()) }
        return curated + usda
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Search common foods. Tap one for details and to log.")
                        .font(.callout).foregroundStyle(theme.dim)

                    searchField

                    if displayedResults.isEmpty {
                        Text("No matches. Try a simpler term.")
                            .font(.callout).foregroundStyle(theme.dim)
                            .padding(.top, 8)
                    } else {
                        let ids = favoriteIds
                        VStack(spacing: 8) {
                            ForEach(displayedResults, id: \.id) { food in
                                PressableCard(action: { foodToDetail = food }) {
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(food.name)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(theme.text)
                                            Text(food.servingLabel)
                                                .font(.caption).foregroundStyle(theme.dim)
                                            Text("\(food.calories) cal · \(food.proteinG)g pro · \(food.carbsG)g carbs · \(food.fatG)g fat")
                                                .font(.system(.caption2, design: .monospaced))
                                                .foregroundStyle(theme.accent)
                                        }
                                        Spacer(minLength: 0)
                                        Button {
                                            toggleFavorite(food.id)
                                        } label: {
                                            Image(systemName: ids.contains(food.id) ? "heart.fill" : "heart")
                                                .foregroundStyle(ids.contains(food.id) ? theme.accent : theme.dim)
                                                .font(.system(size: 16))
                                        }
                                        .tactile(.ghost)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .tactile(.ghost)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { searchFocused = false }
                }
            }
        }
        // Debounce the USDA scan off the hot render path: each keystroke restarts this
        // task (cancelling the prior one); only after a short pause does the heavy
        // search run, so typing never rescans 15–20k entries synchronously in `body`.
        .task(id: query) {
            let q = query
            try? await Task.sleep(nanoseconds: 180_000_000)   // 180 ms
            guard !Task.isCancelled else { return }
            displayedResults = Self.search(q)
        }
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
        .sheet(item: $foodToDetail) { food in
            let ingredients: [MealIngredient] = SuggestedMeals.compositeIngredients[food.id]?
                .compactMap { $0.resolve() } ?? [MealIngredient.from(food)]
            MealIngredientDetailSheet(
                mode: .logging(
                    name: food.name,
                    emoji: "🍽️",
                    defaultSlot: .lunch,
                    ingredients: ingredients
                ),
                profile: profile,
                onDone: { foodToDetail = nil }
            )
            .themed(profile.mode)
        }
    }

    @ViewBuilder
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.dim)
            TextField("Search foods", text: $query)
                .foregroundStyle(theme.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($searchFocused)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark") }
                    .tactile(.ghost)
            }
        }
        .padding(10)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
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
                    Text("nutrition goals.")
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
