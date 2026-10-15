// Single "Add food" surface — replaces the separate "Log a meal" (free text) and
// "Browse" (library) sheets. One field does both jobs:
//   • empty  → quick picks (recipes · favorites · recently logged) + the full
//              library, ordered favorites → most-logged (30 days) → rest
//   • typed  → matching restaurants (RestaurantCatalog — tap = that chain's menu,
//              RestaurantMenuView), then a "log what you described" card
//              (FoodParser, AI-refined on open) on top of matching library foods
//              (curated + USDA + restaurant items)
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

/// Push target for a chain's menu; `query` is what followed the chain name
/// ("shake shack fries" → "fries"), pre-filled into the menu's search.
private struct RestaurantRoute: Hashable {
    let chain: RestaurantChain
    let query: String
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
    @State private var mealToLog: QuickMealLog?
    @State private var templateToLog: SavedMealTemplateDTO?
    @State private var describeText: String?
    @State private var restaurantRoute: RestaurantRoute?
    /// False until the catalog has loaded off the main thread; until then the
    /// Restaurants row stays empty rather than blocking `body` on the load.
    @State private var restaurantsReady = false
    @FocusState private var searchFocused: Bool

    init(profile: ProfileDTO, targetDate: String, onSave: @escaping (FoodLogEntryDTO) -> Bool) {
        self.profile = profile
        self.targetDate = targetDate
        self.onSave = onSave
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

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var favoriteIds: Set<String> {
        Set(favoriteIdsString.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    private var favoriteFoods: [CommonFood] {
        let ids = favoriteIds
        return CommonFoods.all.filter { ids.contains($0.id) }
    }

    /// Last 6 distinct foods/meals logged, newest first.
    private func recentlyLogged(from allLogs: [FoodLogEntryDTO]) -> [FoodLogEntryDTO] {
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

    /// Default (empty-query) ordering for the full curated library:
    /// (a) favorites first, (b) then non-favorites the user actually logs
    /// (last 30 days) by descending frequency, (c) then everything else in
    /// `CommonFoods.all` order. Deterministic: frequency ties break by the
    /// food's existing index, and favorites order by frequency then index.
    private func defaultOrdered(_ allLogs: [FoodLogEntryDTO]) -> [CommonFood] {
        let favs = favoriteIds
        let freq = FoodAffinity.frequencyByFoodId(allLogs, days: 30)
        let ranked = CommonFoods.all.enumerated().map { idx, food -> (rank: (Int, Int, Int), food: CommonFood) in
            let f = freq[food.id] ?? 0
            // Bucket 0 = favorite, 1 = logged non-favorite, 2 = the rest.
            let bucket = favs.contains(food.id) ? 0 : (f > 0 ? 1 : 2)
            // Within a bucket: higher frequency first (negate), then existing index.
            return ((bucket, -f, idx), food)
        }
        return ranked.sorted { $0.rank < $1.rank }.map(\.food)
    }

    private func toggleFavorite(_ id: String) {
        var ids = favoriteIds
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        favoriteIdsString = ids.joined(separator: ",")
        Haptics.bump()
    }

    private func ingredients(for food: CommonFood) -> [MealIngredient] {
        SuggestedMeals.compositeIngredients[food.id]?
            .compactMap { $0.resolve() } ?? [MealIngredient.from(food)]
    }

    private func ingredients(for entry: FoodLogEntryDTO) -> [MealIngredient] {
        if let ings = entry.ingredients, !ings.isEmpty { return ings }
        if let fid = entry.foodId, let food = CommonFoods.all.first(where: { $0.id == fid }) {
            return [MealIngredient.from(food)]
        }
        return []
    }

    var body: some View {
        let allLogs = logModels.map(\.snapshot)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    searchField

                    if trimmedQuery.isEmpty {
                        quickPicks(allLogs: allLogs)
                        manualEntryRow
                        sectionHeader("All foods")
                    } else {
                        restaurantRow
                        describeCard
                        if !displayedResults.isEmpty { sectionHeader("Foods") }
                    }

                    if displayedResults.isEmpty {
                        // Empty + a real query = genuine no-match; empty + blank query
                        // is just the pre-seed moment, so stay silent.
                        if !trimmedQuery.isEmpty {
                            Text("No library matches — log it as described above.")
                                .font(.callout).foregroundStyle(theme.dim)
                        }
                    } else {
                        foodList
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .scrollDismissesKeyboard(.interactively)
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
                    if onSave(dto) { dismiss() }
                }
            }
            .navigationDestination(item: $restaurantRoute) { route in
                RestaurantMenuView(chain: route.chain, initialQuery: route.query) { item in
                    // Same confirm/log path as every other pick.
                    mealToLog = QuickMealLog(name: item.food.name, emoji: "🍽️",
                                             ingredients: [MealIngredient.from(item.food.asCommonFood)])
                }
            }
        }
        .task {
            // Read the (small) restaurant catalog off the main thread once, so the
            // first keystroke that consults it doesn't pay for the SQLite read.
            await Task.detached(priority: .userInitiated) { _ = RestaurantCatalog.shared.isEmpty }.value
            restaurantsReady = true
        }
        .debouncedFoodSearch(query: query, results: $displayedResults) {
            defaultOrdered(logModels.map(\.snapshot))
        }
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

    // MARK: - Restaurants (typed query)

    /// Chains the query names or starts to spell ("shakesha" → Shake Shack).
    /// In-memory over a few chains — cheap enough to run in `body`.
    @ViewBuilder
    private var restaurantRow: some View {
        let chains = restaurantsReady ? RestaurantCatalog.shared.chains(matching: trimmedQuery) : []
        VStack(alignment: .leading, spacing: 8) {
            if !chains.isEmpty {
                sectionHeader(chains.allSatisfy(\.isBrand) ? "Brands" : chains.contains(where: \.isBrand) ? "Restaurants & brands" : "Restaurants")
                ForEach(chains) { chain in
                    PressableCard(action: {
                        Haptics.tap()
                        searchFocused = false
                        let split = RestaurantCatalog.shared.split(trimmedQuery)
                        let rest = split?.chain.slug == chain.slug ? split?.remainder ?? "" : ""
                        restaurantRoute = RestaurantRoute(chain: chain, query: rest)
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: chain.isBrand ? "dumbbell.fill" : "fork.knife")
                                .font(.system(size: 16))
                                .foregroundStyle(theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chain.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(theme.text)
                                Text("\(chain.isBrand ? "Products" : "Menu") · \(chain.itemCount) items")
                                    .font(.caption).foregroundStyle(theme.dim)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.dim)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: chains.map(\.slug))
    }

    // MARK: - Describe card (typed query)

    /// "Log what you described": instant curated parse of the query, so a
    /// multi-food sentence ("2 eggs and toast") logs as one meal.
    @ViewBuilder
    private var describeCard: some View {
        let parsed = FoodParser.parse(text: trimmedQuery, includeDatabase: false)
        PressableCard(action: { describeText = trimmedQuery }) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 18))
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Log “\(trimmedQuery)”")
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

    // MARK: - Quick picks (empty query)

    @ViewBuilder
    private func quickPicks(allLogs: [FoodLogEntryDTO]) -> some View {
        let favorites = favoriteFoods
        let recents = recentlyLogged(from: allLogs)
        if !savedTemplates.isEmpty {
            pillSection(header: "recipes") {
                ForEach(savedTemplates) { template in
                    Button {
                        templateToLog = template.snapshot
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
                            Label("Delete recipe", systemImage: "trash")
                        }
                    }
                }
            }
        }
        if !recents.isEmpty {
            pillSection(header: "recently logged") {
                ForEach(recents) { entry in
                    Button {
                        mealToLog = QuickMealLog(name: entry.customName ?? "Meal", emoji: "🍽️", ingredients: ingredients(for: entry))
                    } label: {
                        Text(entry.customName ?? "Meal")
                    }
                    .tactile(.pill)
                }
            }
        }
        if !favorites.isEmpty {
            pillSection(header: "favorites") {
                ForEach(favorites) { food in
                    Button {
                        mealToLog = QuickMealLog(name: food.name, emoji: "🍽️", ingredients: ingredients(for: food))
                    } label: {
                        Text(food.name)
                    }
                    .tactile(.pill)
                }
            }
        }
    }

    @ViewBuilder
    private var manualEntryRow: some View {
        Button { describeText = "" } label: {
            Label("Enter calories & macros manually", systemImage: "square.and.pencil")
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
        LazyVStack(spacing: 8) {
            ForEach(displayedResults, id: \.id) { food in
                FoodResultRow(
                    food: food,
                    isFavorite: ids.contains(food.id),
                    onToggleFavorite: { toggleFavorite(food.id) }
                ) {
                    mealToLog = QuickMealLog(name: food.name, emoji: "🍽️", ingredients: ingredients(for: food))
                }
            }
        }
    }
}

// MARK: - Shared food search (AddFoodSheet + IngredientFoodSearchSheet)

extension View {
    /// The one debounced food search: each keystroke restarts the task
    /// (cancelling the prior one), and only after a 180 ms pause does
    /// `FoodSearch.combined` (curated + the USDA FTS5 scan, off the main thread)
    /// run — so typing never rescans 15–20k entries synchronously in `body`.
    /// A blank query shows `emptyResults()` immediately.
    func debouncedFoodSearch(
        query: String,
        results: Binding<[CommonFood]>,
        emptyResults: @escaping () -> [CommonFood]
    ) -> some View {
        modifier(DebouncedFoodSearch(query: query, results: results, emptyResults: emptyResults))
    }
}

private struct DebouncedFoodSearch: ViewModifier {
    let query: String
    @Binding var results: [CommonFood]
    let emptyResults: () -> [CommonFood]

    func body(content: Content) -> some View {
        content.task(id: query) {
            let q = query
            if q.trimmingCharacters(in: .whitespaces).isEmpty {
                results = emptyResults()
                return
            }
            try? await Task.sleep(nanoseconds: 180_000_000)   // 180 ms
            guard !Task.isCancelled else { return }
            let found = await FoodSearch.combined(matching: q)
            guard !Task.isCancelled else { return }
            // "shake shack fries": that chain's fries lead, ranked within its menu
            // (FTS rank alone can't promise it); the same rows aren't repeated below.
            // Off the main actor: the first call may still be loading the catalog.
            let menuHits = await Task.detached(priority: .userInitiated) {
                RestaurantCatalog.shared.menuMatches(for: q).map { $0.food.asCommonFood }
            }.value
            guard !Task.isCancelled else { return }
            let leadIds = Set(menuHits.map(\.id))
            results = menuHits + found.filter { !leadIds.contains($0.id) }
        }
    }
}

/// One food in a search / library list: name, serving, macros. The heart shows
/// only when the caller passes `onToggleFavorite` (AddFoodSheet does; the
/// ingredient picker doesn't).
struct FoodResultRow: View {
    let food: CommonFood
    var isFavorite: Bool = false
    var onToggleFavorite: (() -> Void)? = nil
    let onTap: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        PressableCard(action: onTap) {
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
    let onSave: (FoodLogEntryDTO) -> Void

    @Environment(\.theme) private var theme

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

    private enum Field: Hashable { case input, cal, protein, carbs, fat }
    @FocusState private var focused: Field?

    init(profile: ProfileDTO, targetDate: String, initialText: String,
         slot: Slot = .lunch, onSave: @escaping (FoodLogEntryDTO) -> Void) {
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
                    onSave(dto)
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
