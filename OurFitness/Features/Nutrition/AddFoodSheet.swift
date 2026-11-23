// Single "Add food" surface — replaces the separate "Log a meal" (free text) and
// "Browse" (library) sheets. One field does both jobs:
//   • empty  → "My Foods": favorites · recent (a compact scrolling list at the last portion, with
//              a heart on each) · recipes & my foods, each food shown once, + a
//              manual-entry link
//   • typed  → a "log what you described" card (FoodParser, AI-refined on open)
//              on top of matching foods (curated + USDA + restaurant items; a
//              chain in the query — "mcdonalds fries" — leads with that chain's
//              items, sizes collapsed)
// Tapping a food/recipe/recent opens MealIngredientDetailSheet (portion + slot);
// the sheet stays open so several foods can be added in a row.

import SwiftUI
import SwiftData

/// Lightweight carrier for opening MealIngredientDetailSheet from a quick pick or library row.
private struct QuickMealLog: Identifiable {
    let id = UUID()
    let name: String
    let emoji: String
    let ingredients: [MealIngredient]
}

struct AddFoodSheet: View {
    let profile: ProfileDTO
    let targetDate: String
    /// Called for entries built by the describe/manual form. Foods logged via
    /// MealIngredientDetailSheet are saved by that sheet directly.
    /// Returns whether the parent's write committed; the sheet only dismisses on true.
    let onSave: (FoodLogEntryDTO) -> Bool

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var logModels: [FoodLogEntryModel]
    @Query private var savedTemplates: [SavedMealTemplateModel]
    @AppStorage private var favoriteIdsString: String

    @State private var query: String = ""
    @State private var displayedResults: [CommonFood] = []
    /// Other sizes of a collapsed chain item, keyed by the shown row's id.
    @State private var sizeChoices: [String: [SizeChoice]] = [:]
    /// The spelling-fixed query the results are for ("Showing results for …"); nil = as typed.
    @State private var correctedQuery: String?
    /// How strongly `displayedResults` answer the query, and the query that was true for.
    @State private var strength: MatchStrength = .none
    @State private var strengthQuery: String = ""
    /// Apple Intelligence "did you mean" alternatives for the current query (empty = none / AI off).
    @State private var didYouMean: [String] = []
    /// AI answers per query (a tapped suggestion is stored as []), so each query is asked once.
    @State private var didYouMeanCache: [String: [String]] = [:]
    /// Apple Intelligence's typical pick per query (`ServingPickService`), and
    /// the queries already asked (a nil answer is remembered too).
    @State private var typicalPicks: [String: ServingPick] = [:]
    @State private var pickAsked: Set<String> = []
    @State private var mealToLog: QuickMealLog?
    @State private var templateToLog: SavedMealTemplateDTO?
    @State private var describeText: String?
    @FocusState private var searchFocused: Bool

    init(profile: ProfileDTO, targetDate: String, onSave: @escaping (FoodLogEntryDTO) -> Bool) {
        self.profile = profile
        self.targetDate = targetDate
        self.onSave = onSave
        let uid = profile.id
        _favoriteIdsString = AppStorage(wrappedValue: "", FoodFavorites.key(profileId: uid))
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

    /// The results are a confident answer (chain menu hit, or an exact / leading name match).
    private var resultsAreStrong: Bool { strength == .strong && !displayedResults.isEmpty }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var favoriteIds: Set<String> { FoodFavorites.parse(favoriteIdsString) }

    /// Favorites that aren't curated or in the user's own logs, read from the
    /// bundled database once (`SQLiteFoodDatabase.entries(ids:)`, off the main thread).
    @State private var databaseFavorites: [String: CommonFood] = [:]

    /// Favorite ids nothing local can name yet (not curated, never logged).
    private var unresolvedFavoriteIds: [String] {
        let notCurated = favoriteIds.filter { CommonFoods.byId[$0] == nil }
        guard !notCurated.isEmpty else { return [] }
        let logged = FoodAffinity.loggedFoods(logModels.reversed().map(\.snapshot))
        return notCurated.filter { logged[$0] == nil && databaseFavorites[$0] == nil }.sorted()
    }

    private func toggleFavorite(_ id: String) {
        favoriteIdsString = FoodFavorites.serialize(FoodFavorites.toggled(favoriteIds, id))
        Haptics.bump()
    }

    private func ingredients(for food: CommonFood) -> [MealIngredient] {
        SuggestedMeals.compositeIngredients[food.id]?
            .compactMap { $0.resolve() } ?? [MealIngredient.from(food)]
    }

    /// A search result as ingredients, at the typical pick's amount when the
    /// pick is this single food.
    private func ingredients(for food: CommonFood, pick: ServingPick?) -> [MealIngredient] {
        var out = ingredients(for: food)
        if let pick, pick.foodId == food.id, out.count == 1 { out[0].quantity = pick.quantity }
        return out
    }

    private func ingredients(for entry: FoodLogEntryDTO) -> [MealIngredient] {
        entry.repeatIngredients
    }

    /// "×1.5" for a single food logged at other than one serving; nil otherwise.
    private func portionLabel(for entry: FoodLogEntryDTO) -> String? {
        let ings = entry.repeatIngredients
        guard ings.count == 1, let q = ings.first?.quantity, q != 1 else { return nil }
        var s = String(format: "%.2f", q)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return "×" + s
    }

    var body: some View {
        let allLogs = logModels.map(\.snapshot)
        NavigationStack {
            VStack(spacing: 0) {
            // Pinned above the scroll area so the field stays in reach while
            // My Foods / results scroll.
            searchField
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if trimmedQuery.isEmpty {
                        myFoods(allLogs: allLogs)
                        manualEntryRow
                    } else {
                        if !resultsAreStrong { describeCard(compact: false) }
                        savedMatches
                        if let correctedQuery, !displayedResults.isEmpty {
                            Text("Showing results for “\(correctedQuery)”")
                                .font(.caption).foregroundStyle(theme.dim)
                        }
                        if !didYouMean.isEmpty { didYouMeanSection }
                        if !displayedResults.isEmpty { sectionHeader("Foods") }
                    }

                    if displayedResults.isEmpty {
                        // Only a real query can be a genuine no-match; blank shows no list.
                        if !trimmedQuery.isEmpty {
                            Text("No library matches — log it as described above.")
                                .font(.callout).foregroundStyle(theme.dim)
                        }
                    } else {
                        foodList
                    }

                    // A strong match answers the query: the describe card becomes a
                    // small "or log it as a meal" link under the results.
                    if !trimmedQuery.isEmpty && resultsAreStrong { describeCard(compact: true) }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(targetDate == Dates.dayKey() ? "Add food" : "Add food · \(Dates.formatShort(targetDate))")
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
            .navigationDestination(item: $describeText) { text in
                DescribeMealForm(profile: profile, targetDate: targetDate, initialText: text) { dto in
                    let saved = onSave(dto)
                    if saved { dismiss() }
                    return saved
                }
            }
        }
        .task {
            // Read the restaurant catalog + build the search vocabulary off the
            // main thread once, so the first keystroke doesn't pay for the SQLite read.
            await Task.detached(priority: .userInitiated) { _ = CuratedSearchIndex.shared.vocabulary }.value
        }
        .task(id: unresolvedFavoriteIds) {
            let ids = unresolvedFavoriteIds
            guard !ids.isEmpty else { return }
            for entry in await SQLiteFoodDatabase.shared.entries(ids: ids) {
                databaseFavorites[entry.id] = entry.asCommonFood
            }
        }
        .debouncedFoodSearch(query: query, results: $displayedResults, sizeChoices: $sizeChoices,
                             correctedQuery: $correctedQuery, strength: $strength,
                             strengthQuery: $strengthQuery) { [] }
        // The root ToastHost sits under this sheet, so "Logged" would be hidden
        // while the sheet stays open after a pick; host a toast layer here too.
        .onChange(of: query) { _, _ in didYouMean = [] }
        // Weak or empty results: after a pause, ask Apple Intelligence (if available)
        // for alternative queries. Re-keyed on the search outcome so a late result restarts it.
        .task(id: "\(trimmedQuery)|\(strengthQuery)|\(String(describing: strength))") {
            let q = trimmedQuery
            guard !q.isEmpty, strength != .strong, strengthQuery == q,
                  FoodQueryRewriteService.shared.isAvailable else { return }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled, q == trimmedQuery, strengthQuery == q, strength != .strong else { return }
            await checkDidYouMean(for: q)
        }
        // Results in: after a pause, ask Apple Intelligence (if available) which
        // shown result a typical person logs and how much. Never blocks the list.
        .task(id: "pick|\(strengthQuery)|\(displayedResults.first?.id ?? "")") {
            let q = trimmedQuery
            guard !q.isEmpty, strengthQuery == q, displayedResults.count >= 2, !pickAsked.contains(q),
                  ServingPickService.shared.isAvailable else { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, q == trimmedQuery, strengthQuery == q else { return }
            pickAsked.insert(q)
            let pick = await ServingPickService.shared.pick(for: q, among: displayedResults)
            if let pick { typicalPicks[q] = pick }
        }
        .overlay(alignment: .top) { ToastHost() }
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
        .sheet(item: $mealToLog) { meal in
            MealIngredientDetailSheet(
                mode: .logging(name: meal.name, emoji: meal.emoji, defaultSlot: .lunch, ingredients: meal.ingredients),
                profile: profile,
                targetDate: targetDate,
                onDone: { mealToLog = nil }
            )
        }
        .sheet(item: $templateToLog) { template in
            MealIngredientDetailSheet(
                mode: .logging(name: template.name, emoji: template.emoji, defaultSlot: .lunch, ingredients: template.ingredients),
                profile: profile,
                targetDate: targetDate,
                onDone: { templateToLog = nil },
                onDeleteTemplate: {
                    deleteTemplate(id: template.id, name: template.name)
                    templateToLog = nil
                }
            )
        }
    }

    private func deleteTemplate(id: UUID, name: String) {
        // Don't say "deleted" for a write that didn't commit.
        guard Repos.deleteSavedTemplate(ctx, id: id) else { return }
        toasts.show(Toast(title: "Recipe deleted", detail: name, accent: .warn, symbol: "trash"))
    }

    // MARK: - Search field

    @ViewBuilder
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.dim)
            TextField("Search foods or describe your meal", text: $query)
                .foregroundStyle(theme.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($searchFocused)
                .submitLabel(.done)
                .onSubmit {
                    // Return with a description and no exact library hit → go straight
                    // to the describe form (full-DB + AI parse happens there).
                    if !trimmedQuery.isEmpty && displayedResults.isEmpty { describeText = trimmedQuery }
                    else if !trimmedQuery.isEmpty && strength != .strong {
                        // Results exist but only loosely: ask AI for alternatives now.
                        let q = trimmedQuery
                        Task { await checkDidYouMean(for: q) }
                    }
                }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark") }
                    .tactile(.ghost)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(10)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }

    // MARK: - Saved foods matching the query

    /// The user's own saved recipes / foods whose name matches what's typed, above Foods.
    @ViewBuilder
    private var savedMatches: some View {
        let matches = FoodAffinity.matchingTemplates(savedTemplates.map(\.snapshot), query: trimmedQuery)
        if !matches.isEmpty {
            sectionHeader("My Foods")
            VStack(spacing: 8) {
                ForEach(matches) { template in
                    let total = template.totalPerServing
                    FoodResultRow(food: CommonFood(
                        id: "template:\(template.id.uuidString)", name: "\(template.emoji) \(template.name)",
                        aliases: [], servingLabel: template.ingredients.count > 1 ? "\(template.ingredients.count) ingredients" : "1 serving",
                        calories: total.calories, proteinG: total.proteinG, carbsG: total.carbsG,
                        fatG: total.fatG, fiberG: total.fiberG)
                    ) {
                        templateToLog = template
                    }
                }
            }
        }
    }

    // MARK: - Did you mean (Apple Intelligence)

    /// Ask the on-device model for alternative queries, once per query. Shows
    /// nothing when AI is unavailable/off, fails, or the query moved on.
    private func checkDidYouMean(for q: String) async {
        guard strengthQuery == q, strength != .strong,
              FoodQueryRewriteService.shared.isAvailable else { return }
        // Asked before (e.g. backspace + retype): reuse the answer instead of losing it.
        if let cached = didYouMeanCache[q] { didYouMean = cached; return }
        // A multi-food sentence ("2 eggs and toast") has no single library match by
        // design; the describe card already handles it, so don't second-guess it.
        if displayedResults.isEmpty, FoodParser.parse(text: q, includeDatabase: false).hasMatches { return }
        didYouMeanCache[q] = []
        let suggestions = await FoodQueryRewriteService.shared.suggestions(for: q)
        didYouMeanCache[q] = suggestions ?? []
        guard q == trimmedQuery else { return }
        didYouMean = suggestions ?? []
    }

    @ViewBuilder
    private var didYouMeanSection: some View {
        pillSection(header: "did you mean") {
            ForEach(didYouMean, id: \.self) { suggestion in
                Button {
                    // A suggestion is already a vetted query: don't run AI on it again.
                    didYouMeanCache[suggestion] = []
                    query = suggestion
                } label: {
                    Text(suggestion)
                }
                .tactile(.pill)
            }
        }
        AISearchAttribution()
    }

    // MARK: - Describe card (typed query)

    /// "Log what you described": instant curated parse of the query, so a
    /// multi-food sentence ("2 eggs and toast") logs as one meal.
    @ViewBuilder
    private func describeCard(compact: Bool) -> some View {
        // Describe what the results are for ("McDonald's fries", not the typo).
        let described = correctedQuery ?? trimmedQuery
        let parsed = FoodParser.parse(text: described, includeDatabase: false)
        if compact {
            Button { describeText = described } label: {
                Label("Or log “\(described)” as a meal", systemImage: "text.badge.plus")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .tactile(.ghost)
        } else {
        PressableCard(action: { describeText = described }) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 18))
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Log “\(described)”")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .lineLimit(2)
                    if parsed.hasMatches {
                        let ps = parsed.totalPerServing
                        Text(parsed.recognized.map(\.description).joined(separator: " · "))
                            .font(.caption).foregroundStyle(theme.dim)
                            .lineLimit(2)
                        Text("≈ \(ps.calories) cal · \(ps.proteinG)g pro · \(ps.carbsG)g carbs · \(ps.fatG)g fat")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(theme.accent)
                    } else {
                        Text("Describe it as a meal, or enter calories and macros yourself.")
                            .font(.caption).foregroundStyle(theme.dim)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.dim)
            }
        }
        }
    }

    // MARK: - My Foods (empty query)

    @ViewBuilder
    private func myFoods(allLogs: [FoodLogEntryDTO]) -> some View {
        // Newest first; a favorite resolves curated → the user's own logs → the database.
        let newest = Array(allLogs.reversed())
        let logged = FoodAffinity.loggedFoods(newest)
        let favorites = favoriteIds.compactMap { CommonFoods.byId[$0] ?? logged[$0] ?? databaseFavorites[$0] }
        let sections = FoodAffinity.myFoodsSections(
            favorites: favorites, logs: newest, templates: savedTemplates.map(\.snapshot))

        Text("My Foods")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(theme.text)
        if sections.isEmpty {
            Text("Tap ♥ on a food to keep it here")
                .font(.callout).foregroundStyle(theme.dim)
        }
        if !sections.favorites.isEmpty {
            pillSection(header: "favorites") {
                ForEach(sections.favorites) { food in foodPill(food) }
            }
        }
        if !sections.recent.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("recent")
                recentList(sections.recent)
            }
        }
        if !sections.recipes.isEmpty {
            pillSection(header: "recipes & my foods") {
                ForEach(sections.recipes) { template in
                    Button {
                        templateToLog = template
                    } label: {
                        HStack(spacing: 6) {
                            Text(template.emoji)
                            Text(template.name)
                        }
                    }
                    .tactile(.pill)
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteTemplate(id: template.id, name: template.name)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func foodPill(_ food: CommonFood) -> some View {
        Button {
            mealToLog = QuickMealLog(name: food.name, emoji: "🍽️", ingredients: ingredients(for: food))
        } label: {
            Text(food.name)
        }
        .tactile(.pill)
        .contextMenu {
            Button { toggleFavorite(food.id) } label: {
                Label("Remove from favorites", systemImage: "heart.slash")
            }
        }
    }

    /// One Recent row plus its hairline — sizes the list box before layout.
    private static let recentRowHeight: CGFloat = 59

    /// Recent as one bordered list (rows split by hairlines), as tall as its
    /// rows up to 85% of the visible area — so it runs to the bottom of the
    /// screen instead of stopping in a short box — and scrolls on its own
    /// (indicator flashed on open) only when the rows don't fit, e.g. with the
    /// keyboard up. The page keeps scrolling to the sections below it.
    private func recentList(_ entries: [FoodLogEntryDTO]) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Rectangle().fill(theme.line).frame(height: 1).padding(.leading, 14)
                    }
                    recentRow(entry)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicatorsFlash(onAppear: true)
        .containerRelativeFrame(.vertical) { height, _ in
            min(Self.recentRowHeight * CGFloat(entries.count), height * 0.85)
        }
        .background(theme.card, in: shape)
        .clipShape(shape)
        .overlay { shape.strokeBorder(theme.line, lineWidth: 1) }
    }

    /// One recent log as a compact list row: name (+ "×1.5" when logged at
    /// another portion), then calories, protein and the day it was logged;
    /// tap to reopen at that portion, heart when the entry is one known food.
    private func recentRow(_ entry: FoodLogEntryDTO) -> some View {
        let name = entry.customName ?? "Meal"
        let key = FoodAffinity.identityKey(of: entry)
        let favoritable = !key.hasPrefix("name:")
        let p = entry.totalNutrition
        return HStack(spacing: 10) {
            Button {
                mealToLog = QuickMealLog(name: name, emoji: "🍽️", ingredients: ingredients(for: entry))
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                        if let portion = portionLabel(for: entry) {
                            Text(portion).font(.caption).foregroundStyle(theme.dim)
                        }
                    }
                    HStack(spacing: 0) {
                        Text("\(p.calories) cal · \(p.proteinG)g pro")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(theme.accent)
                        Text(" · \(loggedDayLabel(entry.date))")
                            .font(.caption2).foregroundStyle(theme.dim)
                    }
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: Self.recentRowHeight - 18, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("\(p.carbsG)g carbs, \(p.fatG)g fat. Logged \(loggedDayLabel(entry.date))")
            if favoritable {
                let isFavorite = favoriteIds.contains(key)
                Button { toggleFavorite(key) } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? theme.accent : theme.dim)
                        .font(.system(size: 16))
                }
                .tactile(.ghost)
                .accessibilityLabel(isFavorite ? "Remove \(name) from favorites" : "Add \(name) to favorites")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 9)
    }

    /// "today" / "yesterday" / "Mon, Nov 17" — lowercase, unlike `MealHistoryDay.label`.
    private func loggedDayLabel(_ key: String) -> String {
        if key == Dates.dayKey() { return "today" }
        let yesterday = Dates.dayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        if key == yesterday { return "yesterday" }
        guard let d = Dates.date(fromDayKey: key) else { return key }
        return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    @ViewBuilder
    private var manualEntryRow: some View {
        Button { describeText = "" } label: {
            Label("Enter numbers manually", systemImage: "square.and.pencil")
                .font(.system(size: 13, weight: .medium))
        }
        .tactile(.ghost)
    }

    @ViewBuilder
    private func pillSection<Content: View>(header: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(header)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    content()
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .medium)).tracking(2)
            .foregroundStyle(theme.dim)
    }

    // MARK: - Food list

    @ViewBuilder
    private var foodList: some View {
        let ids = favoriteIds
        let pick = strengthQuery == trimmedQuery ? typicalPicks[trimmedQuery] : nil
        LazyVStack(spacing: 8) {
            ForEach(ServingPick.reordered(displayedResults, pick: pick), id: \.id) { food in
                FoodResultRow(
                    food: food,
                    note: pick?.foodId == food.id ? typicalPickNote(pick!) : nil,
                    isFavorite: ids.contains(food.id),
                    onToggleFavorite: { toggleFavorite(food.id) },
                    sizes: sizeChoices[food.id] ?? [],
                    onPickSize: { picked in
                        mealToLog = QuickMealLog(name: picked.name, emoji: "🍽️", ingredients: ingredients(for: picked))
                    }
                ) {
                    mealToLog = QuickMealLog(name: food.name, emoji: "🍽️", ingredients: ingredients(for: food, pick: pick))
                }
            }
        }
    }

    /// "✦ Typical pick" plus the usual amount when it isn't one serving.
    private func typicalPickNote(_ pick: ServingPick) -> String {
        guard pick.quantity != 1 else { return "✦ Typical pick" }
        let amount = pick.quantity.formatted(.number.precision(.fractionLength(0...2)))
        return "✦ Typical pick · usually ×\(amount)"
    }
}

// MARK: - Shared food search (AddFoodSheet + IngredientFoodSearchSheet)

extension View {
    /// The one debounced food search: each keystroke restarts the task
    /// (cancelling the prior one), and only after a 180 ms pause does
    /// `FoodSearch.search` (curated + the USDA FTS5 scan + chain menus, off the
    /// main thread) run — so typing never rescans ~290k entries synchronously
    /// in `body`. A blank query shows `emptyResults()` immediately.
    func debouncedFoodSearch(
        query: String,
        results: Binding<[CommonFood]>,
        emptyResults: @escaping () -> [CommonFood]
    ) -> some View {
        modifier(DebouncedFoodSearch(query: query, results: results, sizeChoices: nil, correctedQuery: nil,
                                     strength: nil, strengthQuery: nil, emptyResults: emptyResults))
    }

    /// Same search, also reporting the size choices of collapsed chain items
    /// (keyed by the shown row's id) and the spelling-corrected query, if any.
    func debouncedFoodSearch(
        query: String,
        results: Binding<[CommonFood]>,
        sizeChoices: Binding<[String: [SizeChoice]]>,
        correctedQuery: Binding<String?>,
        strength: Binding<MatchStrength>,
        strengthQuery: Binding<String>,
        emptyResults: @escaping () -> [CommonFood]
    ) -> some View {
        modifier(DebouncedFoodSearch(query: query, results: results, sizeChoices: sizeChoices,
                                     correctedQuery: correctedQuery, strength: strength,
                                     strengthQuery: strengthQuery, emptyResults: emptyResults))
    }
}

private struct DebouncedFoodSearch: ViewModifier {
    let query: String
    @Binding var results: [CommonFood]
    let sizeChoices: Binding<[String: [SizeChoice]]>?
    let correctedQuery: Binding<String?>?
    /// How strongly the results answer the query, and the query it was computed for.
    let strength: Binding<MatchStrength>?
    let strengthQuery: Binding<String>?
    let emptyResults: () -> [CommonFood]

    func body(content: Content) -> some View {
        content.task(id: query) {
            let q = query
            if q.trimmingCharacters(in: .whitespaces).isEmpty {
                results = emptyResults()
                sizeChoices?.wrappedValue = [:]
                correctedQuery?.wrappedValue = nil
                strength?.wrappedValue = .none
                strengthQuery?.wrappedValue = ""
                return
            }
            try? await Task.sleep(nanoseconds: 180_000_000)   // 180 ms
            guard !Task.isCancelled else { return }
            // "shake shack fries": that chain's fries lead, sizes collapsed
            // (FTS rank alone can't promise it) — see `FoodSearch.search`.
            let outcome = await FoodSearch.search(q)
            guard !Task.isCancelled else { return }
            results = outcome.foods
            sizeChoices?.wrappedValue = outcome.sizeChoices
            correctedQuery?.wrappedValue = outcome.correctedQuery
            strength?.wrappedValue = outcome.strength
            strengthQuery?.wrappedValue = q.trimmingCharacters(in: .whitespaces)
        }
    }
}

/// One food in a search / library list: name, serving, macros. The heart shows
/// only when the caller passes `onToggleFavorite` (AddFoodSheet does; the
/// ingredient picker doesn't).
struct FoodResultRow: View {
    let food: CommonFood
    /// Small accent line above the name (AddFoodSheet's AI typical pick).
    var note: String? = nil
    var isFavorite: Bool = false
    var onToggleFavorite: (() -> Void)? = nil
    /// Other sizes of this item (chain results). Shown as small inline pills;
    /// tapping one picks that size's own row via `onPickSize`.
    var sizes: [SizeChoice] = []
    var onPickSize: ((CommonFood) -> Void)? = nil
    let onTap: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        PressableCard(action: onTap) {
            // The size pills sit under the whole row (not inside the text column)
            // so their horizontal scroll can't push the heart or clip the text.
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let note {
                            Text(note)
                                .font(.system(size: 10, weight: .medium)).tracking(1)
                                .foregroundStyle(theme.accent)
                        }
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
                    if let onToggleFavorite {
                        Button(action: onToggleFavorite) {
                            Image(systemName: isFavorite ? "heart.fill" : "heart")
                                .foregroundStyle(isFavorite ? theme.accent : theme.dim)
                                .font(.system(size: 16))
                        }
                        .tactile(.ghost)
                        .accessibilityLabel(isFavorite ? "Remove \(food.name) from favorites" : "Add \(food.name) to favorites")
                    }
                }
                if sizes.count > 1, let onPickSize { sizePills(onPickSize) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One small pill per size ("Small 230"); the shown row's size is filled.
    @ViewBuilder
    private func sizePills(_ pick: @escaping (CommonFood) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(sizes) { size in
                    let isShown = size.food.id == food.id
                    Button {
                        if !isShown { pick(size.food) }
                    } label: {
                        Text("\(size.label) \(size.food.calories)")
                            .font(.system(size: 11, weight: isShown ? .semibold : .regular))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .foregroundStyle(isShown ? theme.bg : theme.text)
                            .background(isShown ? theme.accent : theme.card2, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(size.label), \(size.food.calories) calories")
                }
            }
        }
    }
}

// MARK: - Describe / manual form

/// Free-text meal logging, pushed from AddFoodSheet. Keystrokes parse against the
/// curated foods; on open/submit the full USDA DB (and Apple Intelligence when
/// available) refines the parse. Numbers always come from the food database —
/// the model only splits the sentence into items. Empty `initialText` = manual entry.
/// Also the camera label scanner's type-it-instead screen (`CameraFoodLogSheet`),
/// so there is one free-text meal logger.
struct DescribeMealForm: View {
    let profile: ProfileDTO
    let targetDate: String
    let initialText: String
    /// Returns whether the log write committed (rule 9: nothing else happens on false).
    let onSave: (FoodLogEntryDTO) -> Bool

    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var ctx
    @EnvironmentObject private var toasts: ToastCenter

    @State private var input: String = ""
    @State private var parseResult: FoodParser.ParseResult? = nil
    @State private var parsedWithAI = false
    @State private var aiParsing = false
    @State private var slot: Slot
    @State private var showManual = true
    @State private var didSeed = false

    @State private var manualCalories: Int = 0
    @State private var manualProtein: Int = 0
    @State private var manualCarbs: Int = 0
    @State private var manualFat: Int = 0
    /// Manual entry only: also keep this food in My Foods after the log commits.
    @State private var saveToMyFoods = false

    private enum Field: Hashable { case input, cal, protein, carbs, fat }
    @FocusState private var focused: Field?

    init(profile: ProfileDTO, targetDate: String, initialText: String,
         slot: Slot = .lunch, onSave: @escaping (FoodLogEntryDTO) -> Bool) {
        self.profile = profile
        self.targetDate = targetDate
        self.initialText = initialText
        self.onSave = onSave
        _slot = State(initialValue: slot)
    }

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

                if showManual {
                    Toggle("Save to My Foods", isOn: $saveToMyFoods)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.text)
                        .tint(theme.accent)
                        .disabled(!canSave)
                }

                Button {
                    let mealIngredients = parseResult?.recognized.map {
                        MealIngredient.from($0.food, quantity: $0.quantity)
                    }
                    let dto = FoodLogEntryDTO(
                        userId: profile.id,
                        date: targetDate,
                        slot: slot,
                        customName: resolvedName,
                        perServing: resolvedPerServing,
                        ingredients: mealIngredients
                    )
                    let name = resolvedName, perServing = resolvedPerServing
                    guard onSave(dto) else { return }
                    // The log committed; keeping the food is a second write with its own result.
                    guard showManual, saveToMyFoods else { return }
                    guard Repos.addSavedTemplate(
                        ctx, .singleFood(userId: profile.id, name: name, perServing: perServing)
                    ) else {
                        toasts.show(Toast(title: "Logged, but not saved to My Foods", detail: name, accent: .warn,
                                          symbol: "exclamationmark.triangle"))
                        return
                    }
                    // Re-show the log confirmation with the save noted, so it isn't replaced.
                    toasts.logged(name, perServing: perServing, note: "saved to My Foods")
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
        .navigationTitle(initialText.isEmpty ? "Manual entry" : "Log meal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
        .task {
            // Seed once from the search field, then run the full-DB / AI pass
            // immediately so the user lands on the best parse.
            guard !didSeed else { return }
            didSeed = true
            input = initialText
            if initialText.isEmpty {
                focused = .input
            } else {
                parseInput()
                await aiRefine()
            }
        }
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
                    Text("Recognized".uppercased())
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
                Text("Not recognized: \(result.unrecognized.joined(separator: ", ")) — fill in below.")
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
                    MacroChip(label: "Cal", value: ps.calories)
                    MacroChip(label: "Protein", value: ps.proteinG, unit: "g")
                    MacroChip(label: "Carbs", value: ps.carbsG, unit: "g")
                    MacroChip(label: "Fat", value: ps.fatG, unit: "g")
                }
            }
        }
    }

    @ViewBuilder
    private var slotPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Slot".uppercased())
                .font(.caption).tracking(2).foregroundStyle(theme.dim)
            SlotPicker(selection: $slot)
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

/// Credit line under the AI-suggested searches. Same look as the describe form's
/// attribution (that one is private to `DescribeMealForm`).
private struct AISearchAttribution: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 10)).foregroundStyle(theme.accent)
            Text("Search ideas from Apple Intelligence, on this device. Foods and numbers come from the food database.")
                .font(.caption2).foregroundStyle(theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
