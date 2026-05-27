// Meal log tab. Type what you ate; FoodParser resolves the nutrition.
// Suggestions pill surfaces curated meals from the library.

import SwiftUI
import SwiftData

struct NutritionView: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var logModels: [FoodLogEntryModel]
    @State private var showLogSheet = false

    init(profile: ProfileDTO) {
        self.profile = profile
        let uid = profile.id
        _logModels = Query(
            filter: #Predicate<FoodLogEntryModel> { $0.userId == uid },
            sort: \.timestamp,
            order: .forward
        )
    }
    @State private var showSuggestions = false
    @State private var showLibrary = false

    private var today: String { Dates.dayKey() }

    private var todaysLogs: [FoodLogEntryDTO] {
        logModels.map(\.snapshot).filter { $0.date == today }
    }
    private var allLogs: [FoodLogEntryDTO] { logModels.map(\.snapshot) }

    private var totals: DailyTotals { DailyTotals.totals(from: todaysLogs) }

    private var rankedSuggestions: [SuggestedMeal] {
        SuggestedMeals.ranked(for: profile, totals: totals)
    }

    private var varietyNudges: [FoodVarietyNudge] {
        FoodVarietyNudges.nudges(from: allLogs, mode: profile.mode)
    }

    private func logSuggested(_ meal: SuggestedMeal, slot: Slot = .lunch) {
        let dto = FoodLogEntryDTO(
            userId: profile.id,
            date: today,
            slot: slot,
            customName: meal.name,
            perServing: meal.perServing
        )
        Repos.addFoodLog(ctx, dto)
        toasts.logged(meal.name, calories: meal.perServing.calories)
    }

    private func logCommonFood(_ food: CommonFood) {
        let dto = FoodLogEntryDTO(
            userId: profile.id,
            date: today,
            slot: .lunch,
            foodId: food.id,
            customName: food.name,
            perServing: PerServing(
                calories: food.calories, proteinG: food.proteinG,
                carbsG: food.carbsG, fatG: food.fatG, fiberG: food.fiberG
            )
        )
        Repos.addFoodLog(ctx, dto)
        toasts.logged(food.name, calories: food.calories)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header: "meals." + suggestions pill
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("meals.")
                        .font(.system(size: 56, weight: .regular))
                        .foregroundStyle(theme.text)
                    Button {
                        showSuggestions = true
                    } label: {
                        Label("suggestions", systemImage: "sparkles")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .tactile(.pill, fill: theme.accent)
                    Spacer(minLength: 0)
                }

                totalsCard

                suggestionPillRow
                nudgeSection

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

                logList
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
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
            FoodLibrarySheet { food in
                logCommonFood(food)
                showLibrary = false
            }
            .themed(profile.mode)
        }
    }

    // MARK: - Suggestion pill row

    @ViewBuilder
    private var suggestionPillRow: some View {
        let meals = rankedSuggestions
        if !meals.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("For you".uppercased())
                    .font(.system(size: 10)).tracking(2)
                    .foregroundStyle(theme.dim)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(meals) { meal in
                            Button {
                                logSuggested(meal)
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

    // MARK: - Variety nudges

    @ViewBuilder
    private var nudgeSection: some View {
        let nudges = varietyNudges
        if !nudges.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(nudges, id: \.message) { nudge in
                    HStack(alignment: .top, spacing: 6) {
                        Text(nudge.emoji)
                            .font(.system(size: 12))
                        Text(nudge.message)
                            .font(.caption).italic()
                            .foregroundStyle(theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Totals card

    @ViewBuilder
    private var totalsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Today")
                    .font(.caption).tracking(2).textCase(.uppercase)
                    .foregroundStyle(theme.dim)
                MacroQuadGrid(totals: totals, targets: profile.computedTargets)
            }
        }
    }

    // MARK: - Log list

    @ViewBuilder
    private var logList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's log")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.text)
            if todaysLogs.isEmpty {
                Text("Nothing logged yet.")
                    .font(.callout).foregroundStyle(theme.dim)
            } else {
                ForEach(todaysLogs) { e in
                    LogRow(entry: e) {
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
    let onDelete: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.customName ?? "Meal")
                    .foregroundStyle(theme.text)
                Text("\(entry.perServing.calories) cal · \(entry.perServing.proteinG)p · \(entry.perServing.carbsG)c · \(entry.perServing.fatG)f")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(theme.dim)
            }
            Spacer(minLength: 0)
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

// MARK: - NL Meal Log Sheet

private struct NLMealLogSheet: View {
    let profile: ProfileDTO
    let onSave: (FoodLogEntryDTO) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var input: String = ""
    @State private var parseResult: FoodParser.ParseResult? = nil
    @State private var slot: Slot = .lunch
    // showManual starts true so the user can always enter values directly.
    // It flips to false (show parsed summary) once the parser finds a match.
    @State private var showManual = true

    // Manual fields (also used as the editable override after parsing)
    @State private var manualCalories: Int = 0
    @State private var manualProtein: Int = 0
    @State private var manualCarbs: Int = 0
    @State private var manualFat: Int = 0

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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("log a meal.")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(theme.text)

                // Natural language input
                VStack(alignment: .leading, spacing: 6) {
                    Text("What did you eat?".uppercased())
                        .font(.system(size: 10)).tracking(2)
                        .foregroundStyle(theme.dim)
                    TextField("e.g. a bowl of rice and some grilled chicken", text: $input, axis: .vertical)
                        .lineLimit(1...3)
                        .padding(10).background(theme.card)
                        .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
                        .foregroundStyle(theme.text)
                        .onSubmit { parseInput() }
                        .onChange(of: input) { _, _ in
                            // Auto-parse while typing (debounce effect: parse on each character)
                            parseInput()
                        }
                }

                // Parse results
                if let result = parseResult, !input.trimmingCharacters(in: .whitespaces).isEmpty {
                    parsedPreview(result)
                }

                slotPicker

                nutritionSummary

                // Save
                Button {
                    let dto = FoodLogEntryDTO(
                        userId: profile.id,
                        date: Dates.dayKey(),
                        slot: slot,
                        customName: resolvedName,
                        perServing: resolvedPerServing
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
        .presentationDetents([.large])
    }

    private func parseInput() {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { parseResult = nil; return }
        let result = FoodParser.parse(text: trimmed)
        parseResult = result
        if result.hasMatches {
            let ps = result.totalPerServing
            manualCalories = ps.calories
            manualProtein  = ps.proteinG
            manualCarbs    = ps.carbsG
            manualFat      = ps.fatG
            // Switch to parsed summary view automatically when we have matches
            showManual = false
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
                        .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
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
                    numField("Calories", value: $manualCalories)
                    numField("Protein g", value: $manualProtein)
                }
                HStack(spacing: 10) {
                    numField("Carbs g", value: $manualCarbs)
                    numField("Fat g", value: $manualFat)
                }
            } else {
                let ps = resolvedPerServing
                HStack(spacing: 14) {
                    macroChip(label: "Cal", value: ps.calories)
                    macroChip(label: "P", value: ps.proteinG)
                    macroChip(label: "C", value: ps.carbsG)
                    macroChip(label: "F", value: ps.fatG)
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
        .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
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
    private func numField(_ label: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 9)).tracking(2)
                .foregroundStyle(theme.dim)
            TextField("", value: value, format: .number)
                .keyboardType(.numberPad)
                .padding(10).background(theme.card)
                .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
                .foregroundStyle(theme.text)
                .font(.system(.callout, design: .monospaced))
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

    @State private var slot: Slot = .lunch

    private var suggestions: [SuggestedMeal] {
        SuggestedMeals.ranked(for: profile, totals: totals, limit: 10)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("suggestions.")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(theme.text)
                Text("Tap any meal to log it instantly.")
                    .font(.callout).foregroundStyle(theme.dim)

                slotPicker

                ForEach(suggestions) { meal in
                    PressableCard(action: { log(meal) }) {
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
                                Text("\(meal.perServing.calories) cal · \(meal.perServing.proteinG)p · \(meal.perServing.carbsG)c · \(meal.perServing.fatG)f")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(theme.accent)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.large])
    }

    private func log(_ meal: SuggestedMeal) {
        let dto = FoodLogEntryDTO(
            userId: profile.id,
            date: Dates.dayKey(),
            slot: slot,
            customName: meal.name,
            perServing: meal.perServing
        )
        onPick(dto)
    }

    @ViewBuilder
    private var slotPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Logging as".uppercased())
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
}

// MARK: - Food Library Sheet

private struct FoodLibrarySheet: View {
    let onPick: (CommonFood) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    private var results: [CommonFood] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return CommonFoods.all }
        return CommonFoods.all.filter { food in
            food.name.lowercased().contains(q)
                || food.aliases.contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("library.")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(theme.text)
                Text("Search common foods. Tap to log one serving.")
                    .font(.callout).foregroundStyle(theme.dim)

                searchField

                if results.isEmpty {
                    Text("No matches. Try a simpler term.")
                        .font(.callout).foregroundStyle(theme.dim)
                        .padding(.top, 8)
                } else {
                    VStack(spacing: 8) {
                        ForEach(results, id: \.id) { food in
                            PressableCard(action: { onPick(food) }) {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(food.name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(theme.text)
                                        Text(food.servingLabel)
                                            .font(.caption).foregroundStyle(theme.dim)
                                        Text("\(food.calories) cal · \(food.proteinG)p · \(food.carbsG)c · \(food.fatG)f")
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(theme.accent)
                                    }
                                    Spacer(minLength: 0)
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
        .presentationDetents([.large])
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
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark") }
                    .tactile(.ghost)
            }
        }
        .padding(10)
        .background(theme.card)
        .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
    }
}
