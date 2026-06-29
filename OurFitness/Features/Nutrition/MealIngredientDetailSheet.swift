// Build-a-meal sheet: a meal is a list of ingredients, each with a 0.5-step
// quantity. Totals are derived live from the ingredients (never stored as a
// frozen number) so editing quantities re-derives the logged macros.
//
// Two modes:
//   .logging — assembling a fresh meal (from a suggestion / scratch) to log
//   .editing — re-opening an existing FoodLogEntryDTO that carries `ingredients`
//
// Numbers stay deterministic: every ingredient's macros come from CommonFoods /
// the bundled USDA FoodDatabase (or explicit manual entry), scaled by quantity.
// Nothing is invented here.

import SwiftUI

struct MealIngredientDetailSheet: View {
    enum Mode {
        case logging(name: String, emoji: String, defaultSlot: Slot, ingredients: [MealIngredient])
        case editing(entry: FoodLogEntryDTO)
    }

    let mode: Mode
    let profile: ProfileDTO
    let targetDate: String
    var onDone: () -> Void
    var onDeleteTemplate: (() -> Void)?

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @State private var name: String
    @State private var emoji: String
    @State private var ingredients: [MealIngredient]
    @State private var slot: Slot
    @State private var isEditing: Bool   // true = opened from an existing log

    @State private var showFoodSearch = false
    @State private var showSaveTemplate = false

    init(mode: Mode, profile: ProfileDTO, targetDate: String = Dates.dayKey(), onDone: @escaping () -> Void, onDeleteTemplate: (() -> Void)? = nil) {
        self.mode = mode
        self.profile = profile
        self.targetDate = targetDate
        self.onDone = onDone
        self.onDeleteTemplate = onDeleteTemplate

        switch mode {
        case let .logging(name, emoji, defaultSlot, ingredients):
            _name = State(initialValue: name)
            _emoji = State(initialValue: emoji)
            _ingredients = State(initialValue: ingredients)
            _slot = State(initialValue: defaultSlot)
            _isEditing = State(initialValue: false)
        case let .editing(entry):
            _name = State(initialValue: entry.customName ?? "Meal")
            _emoji = State(initialValue: "🍽️")
            _ingredients = State(initialValue: entry.ingredients ?? [])
            _slot = State(initialValue: entry.slot)
            _isEditing = State(initialValue: true)
        }
    }

    private var totals: PerServing {
        ingredients.map(\.scaledPerServing).reduce(.zero, +)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    ingredientsSection
                    totalsSection
                    actions
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle(isEditing ? "Edit meal" : "Log meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .tactile(.ghost)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.bg)
        .sheet(isPresented: $showFoodSearch) {
            IngredientFoodSearchSheet(ingredients: $ingredients)
                .themed(theme.mode)
        }
        .sheet(isPresented: $showSaveTemplate) {
            SaveTemplateSheet(name: name, emoji: emoji, ingredients: ingredients, profile: profile)
                .themed(theme.mode)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Text(emoji)
                .font(.system(size: 40))

            TextField("Meal name", text: $name)
                .font(.system(size: 22, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.text)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Slot.allCases, id: \.self) { s in
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
    }

    // MARK: - Ingredients

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ingredients".uppercased())
                .font(.system(size: 10, weight: .medium)).tracking(2)
                .foregroundStyle(theme.dim)

            ForEach($ingredients) { $ingredient in
                IngredientRow(ingredient: $ingredient) {
                    ingredients.removeAll { $0.id == ingredient.id }
                    Haptics.bump()
                }
            }

            Button {
                showFoodSearch = true
            } label: {
                Label("Add ingredient", systemImage: "plus")
            }
            .tactile(.secondary, fullWidth: true)
        }
    }

    // MARK: - Totals

    private var totalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Totals".uppercased())
                .font(.system(size: 10, weight: .medium)).tracking(2)
                .foregroundStyle(theme.dim)

            if ingredients.isEmpty {
                Text("Add ingredients to see totals")
                    .font(.callout)
                    .foregroundStyle(theme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 10) {
                    MealMacroChip(label: "cal", value: totals.calories)
                    MealMacroChip(label: "protein", value: totals.proteinG, unit: "g")
                    MealMacroChip(label: "carbs", value: totals.carbsG, unit: "g")
                    MealMacroChip(label: "fat", value: totals.fatG, unit: "g")
                }
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 12) {
            if !isEditing {
                Button {
                    showSaveTemplate = true
                } label: {
                    Label("Save as My Recipe", systemImage: "bookmark")
                }
                .tactile(.ghost)
            }

            if isEditing {
                Button("Save changes") { saveChanges() }
                    .tactile(.primary, fullWidth: true)

                Button("Remove Log") { deleteEntry() }
                    .tactile(.ghost)
                    .tint(.red)
            } else {
                Button("Log meal") { logMeal() }
                    .tactile(.primary, fullWidth: true)
                    .disabled(ingredients.isEmpty)
            }

            if let deleteTemplate = onDeleteTemplate {
                Button(role: .destructive) { deleteTemplate() } label: {
                    Label("Delete recipe", systemImage: "trash")
                }
                .tactile(.ghost)
                .tint(.red)
            }
        }
        .padding(.top, 4)
    }

    private func logMeal() {
        let perServing = totals
        let dto = FoodLogEntryDTO(
            userId: profile.id,
            date: targetDate,
            slot: slot,
            customName: name.isEmpty ? nil : name,
            perServing: perServing,
            ingredients: ingredients
        )
        Repos.addFoodLog(ctx, dto)
        Haptics.success()
        toasts.show(Toast(title: "Logged", detail: name, accent: .ok, symbol: "checkmark.circle.fill"))
        onDone()
        dismiss()
    }

    private func saveChanges() {
        guard case let .editing(entry) = mode else { return }
        var updated = entry
        updated.customName = name.isEmpty ? nil : name
        updated.slot = slot
        updated.ingredients = ingredients
        updated.perServing = totals
        Repos.updateFoodLog(ctx, updated)
        Haptics.success()
        toasts.show(Toast(title: "Updated", detail: name, accent: .ok, symbol: "checkmark.circle.fill"))
        onDone()
        dismiss()
    }

    private func deleteEntry() {
        guard case let .editing(entry) = mode else { return }
        Repos.deleteFoodLog(ctx, id: entry.id)
        Haptics.warn()
        toasts.show(Toast(title: "Removed", detail: name, accent: .warn, symbol: "minus.circle.fill"))
        onDone()
        dismiss()
    }
}

// MARK: - Macro chip

private struct MealMacroChip: View {
    let label: String
    let value: Int
    var unit: String = ""

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)\(unit)")
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.text)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium)).tracking(1.5)
                .foregroundStyle(theme.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.line, lineWidth: 1))
    }
}

// MARK: - Ingredient row

private struct IngredientRow: View {
    @Binding var ingredient: MealIngredient
    var onDelete: () -> Void

    @Environment(\.theme) private var theme

    private var formattedQty: String {
        String(format: "%.1f", ingredient.quantity)
    }

    private func adjust(by delta: Double) {
        let next = (ingredient.quantity + delta)
        ingredient.quantity = min(10.0, max(0.5, next))
        Haptics.bump()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ingredient.name)
                        .font(.callout)
                        .foregroundStyle(theme.text)
                    Text(ingredient.servingLabel)
                        .font(.caption)
                        .foregroundStyle(theme.dim)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    let s = ingredient.scaledPerServing
                    Text("\(s.calories) cal")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(theme.text)
                    Text("\(s.proteinG)g pro · \(s.carbsG)g carbs · \(s.fatG)g fat")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(theme.dim)
                }
            }

            HStack(spacing: 10) {
                Button {
                    adjust(by: -0.5)
                } label: {
                    Image(systemName: "minus")
                }
                .tactile(.bump)
                .disabled(ingredient.quantity <= 0.5)

                Text("×\(formattedQty)")
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(theme.text)
                    .frame(minWidth: 44)

                Button {
                    adjust(by: 0.5)
                } label: {
                    Image(systemName: "plus")
                }
                .tactile(.bump)
                .disabled(ingredient.quantity >= 10.0)

                Spacer()

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .tactile(.ghost)
                .tint(.red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.line, lineWidth: 1))
    }
}

// MARK: - Ingredient food search

struct IngredientFoodSearchSheet: View {
    @Binding var ingredients: [MealIngredient]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var query = ""
    @State private var searchResults: [CommonFood] = Array(CommonFoods.all.prefix(30))
    @State private var showManual = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(theme.dim)
                    TextField("Search foods", text: $query)
                        .foregroundStyle(theme.text)
                        .focused($searchFocused)
                        .autocorrectionDisabled()
                }
                .padding(12)
                .background(theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(searchResults) { food in
                            PressableCard {
                                ingredients.append(MealIngredient.from(food, quantity: 1.0))
                                Haptics.bump()
                                dismiss()
                            } content: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(food.name)
                                        .font(.callout)
                                        .foregroundStyle(theme.text)
                                    Text("\(food.servingLabel) · \(food.calories) cal · \(food.proteinG)g protein")
                                        .font(.caption)
                                        .foregroundStyle(theme.dim)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }

                Button {
                    showManual = true
                } label: {
                    Label("Add manually", systemImage: "square.and.pencil")
                }
                .tactile(.secondary, fullWidth: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle("Add ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .tactile(.ghost)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.bg)
        // Debounce the USDA FTS5 scan off the main thread — mirrors FoodLibrarySheet.
        // Empty query shows curated-only immediately; non-empty waits 180 ms then
        // suspends the main actor while the SQLite query runs on the background queue.
        .task(id: query) {
            let q = query.lowercased().trimmingCharacters(in: .whitespaces)
            if q.isEmpty {
                searchResults = Array(CommonFoods.all.prefix(30))
                return
            }
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }

            let curated = CommonFoods.all.filter { food in
                food.name.lowercased().contains(q)
                    || food.aliases.contains { $0.lowercased().contains(q) }
            }
            let curatedNames = Set(curated.map { $0.name.lowercased() })
            let usda = await SQLiteFoodDatabase.shared.searchAsync(query: q, limit: 40)
                .filter { !curatedNames.contains($0.name.lowercased()) }
                .map { $0.asCommonFood }

            guard !Task.isCancelled else { return }
            searchResults = curated + usda
        }
        .onAppear { searchFocused = true }
        .sheet(isPresented: $showManual) {
            ManualIngredientSheet(ingredients: $ingredients)
                .themed(theme.mode)
        }
    }
}

// MARK: - Manual ingredient entry

struct ManualIngredientSheet: View {
    @Binding var ingredients: [MealIngredient]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var name = ""
    @State private var servingDesc = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""

    @FocusState private var fieldFocused: Bool

    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    field("Name", text: $name, keyboard: .default)
                    field("Serving (optional)", text: $servingDesc, keyboard: .default)
                    field("Calories", text: $calories, keyboard: .numberPad)
                    field("Protein (g)", text: $protein, keyboard: .numberPad)
                    field("Carbs (g)", text: $carbs, keyboard: .numberPad)
                    field("Fat (g)", text: $fat, keyboard: .numberPad)

                    Button("Add") { add() }
                        .tactile(.primary, fullWidth: true)
                        .disabled(!canAdd)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle("Manual ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .tactile(.ghost)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { fieldFocused = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.bg)
    }

    @ViewBuilder
    private func field(_ label: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium)).tracking(2)
                .foregroundStyle(theme.dim)
            TextField(label, text: text)
                .keyboardType(keyboard)
                .focused($fieldFocused)
                .foregroundStyle(theme.text)
                .padding(12)
                .background(theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
        }
    }

    private func add() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let ingredient = MealIngredient(
            id: UUID(),
            foodId: nil,
            name: trimmed,
            servingLabel: servingDesc.isEmpty ? "1 serving" : servingDesc,
            quantity: 1.0,
            perServing: PerServing(
                calories: Int(calories) ?? 0,
                proteinG: Int(protein) ?? 0,
                carbsG: Int(carbs) ?? 0,
                fatG: Int(fat) ?? 0
            )
        )
        ingredients.append(ingredient)
        Haptics.bump()
        dismiss()
    }
}

// MARK: - Save recipe template

struct SaveTemplateSheet: View {
    let name: String
    let emoji: String
    let ingredients: [MealIngredient]
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @State private var templateName: String
    @State private var templateEmoji: String

    @FocusState private var fieldFocused: Bool

    init(name: String, emoji: String, ingredients: [MealIngredient], profile: ProfileDTO) {
        self.name = name
        self.emoji = emoji
        self.ingredients = ingredients
        self.profile = profile
        _templateName = State(initialValue: name)
        _templateEmoji = State(initialValue: emoji)
    }

    private var canSave: Bool {
        !templateName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Emoji".uppercased())
                            .font(.system(size: 9, weight: .medium)).tracking(2)
                            .foregroundStyle(theme.dim)
                        TextField("🍽️", text: $templateEmoji)
                            .focused($fieldFocused)
                            .foregroundStyle(theme.text)
                            .padding(12)
                            .background(theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recipe name".uppercased())
                            .font(.system(size: 9, weight: .medium)).tracking(2)
                            .foregroundStyle(theme.dim)
                        TextField("Recipe name", text: $templateName)
                            .focused($fieldFocused)
                            .foregroundStyle(theme.text)
                            .padding(12)
                            .background(theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                    }

                    Button("Save Recipe") { save() }
                        .tactile(.primary, fullWidth: true)
                        .disabled(!canSave)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle("Save recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .tactile(.ghost)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { fieldFocused = false }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.bg)
    }

    private func save() {
        let trimmedName = templateName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        let template = SavedMealTemplateDTO(
            userId: profile.id,
            name: trimmedName,
            emoji: templateEmoji.isEmpty ? "🍽️" : templateEmoji,
            ingredients: ingredients
        )
        Repos.addSavedTemplate(ctx, template)
        Haptics.success()
        toasts.show(Toast(title: "Recipe saved", detail: trimmedName, accent: .ok, symbol: "bookmark.fill"))
        dismiss()
    }
}
