import SwiftUI
import SwiftData

struct NutritionView: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter
    @Query private var foodModels: [FoodModel]

    @State private var search: String = ""
    @State private var category: FoodCategory? = nil
    @State private var slot: Slot = .lunch

    private var allCategories: [FoodCategory] {
        [.smoothie, .breakfast, .main, .bowl, .soup, .snack, .side, .drink]
    }

    private var filtered: [FoodDTO] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return foodModels.map(\.snapshot)
            .filter { $0.modeFit.contains(profile.mode) }
            .filter { food in
                if let category, food.category != category { return false }
                if !profile.restrictions.allSatisfy({ !food.allergens.contains($0) }) { return false }
                if !q.isEmpty {
                    let inName = food.name.lowercased().contains(q)
                    let inIng = food.ingredients.contains { $0.contains(q) }
                    if !inName && !inIng { return false }
                }
                return true
            }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("library.")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(theme.text)
                Text(profile.mode == .build
                     ? "Foods you already love — calorie-dense, picky-friendly."
                     : "DASH + Mediterranean leaning — fiber, lean protein, low sodium.")
                    .font(.callout).foregroundStyle(theme.dim)

                searchBar
                slotPicker
                categoryRow

                LazyVStack(spacing: 12) {
                    ForEach(filtered) { food in
                        PressableCard(action: { log(food) }) {
                            FoodLibraryRow(food: food, modeIsReset: profile.mode == .reset, slot: slot)
                        }
                    }
                    if filtered.isEmpty {
                        Text("No matches. Try clearing filters.")
                            .font(.callout).foregroundStyle(theme.dim)
                            .padding(.top, 24)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background(theme.bg.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: slot)
        .sensoryFeedback(.selection, trigger: category)
    }

    private var searchBar: some View {
        TextField("Search…", text: $search)
            .textInputAutocapitalization(.never)
            .padding(10)
            .background(theme.card)
            .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
            .foregroundStyle(theme.text)
    }

    private var slotPicker: some View {
        HStack(spacing: 6) {
            Text("LOG TO:").font(.caption2).tracking(2).foregroundStyle(theme.dim)
            Picker("", selection: $slot) {
                ForEach([Slot.breakfast, .postWorkout, .lunch, .snack, .dinner], id: \.self) { s in
                    Text(s.label.capitalized).tag(s)
                }
            }
            .pickerStyle(.menu)
            .tint(theme.accent)
        }
    }

    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pill(nil, "All")
                ForEach(allCategories, id: \.self) { c in
                    pill(c, c.rawValue.capitalized)
                }
            }
        }
    }

    @ViewBuilder
    private func pill(_ c: FoodCategory?, _ label: String) -> some View {
        Button {
            category = c
        } label: {
            Text(label)
        }
        .tactile(.pill, fill: category == c ? theme.accent : nil)
    }

    private func log(_ food: FoodDTO) {
        let entry = FoodLogEntryDTO(
            userId: profile.id, date: Dates.dayKey(), slot: slot,
            foodId: food.id, servings: 1, perServing: food.perServing
        )
        Repos.addFoodLog(ctx, entry)
        toasts.logged(food.name, calories: food.perServing.calories)
    }
}

// MARK: - Library row

private struct FoodLibraryRow: View {
    let food: FoodDTO
    let modeIsReset: Bool
    let slot: Slot

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(food.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.text)
                Spacer()
                Text(String(format: "$%.2f", food.costUsd))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(theme.accent2)
            }
            if let r = food.recipe {
                Text(r).font(.caption).foregroundStyle(theme.dim).lineLimit(2)
            }
            HStack(spacing: 12) {
                Text("\(food.perServing.calories) cal").foregroundStyle(theme.accent)
                Text("\(food.perServing.proteinG)p")
                Text("\(food.perServing.carbsG)c")
                Text("\(food.perServing.fatG)f")
                if modeIsReset {
                    Text("\(food.perServing.fiberG)fib")
                    Text("\(food.perServing.sodiumMg)mg na").foregroundStyle(theme.dim)
                }
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(theme.text)

            if !food.tags.isEmpty {
                Text(food.tags.prefix(3).joined(separator: " · "))
                    .font(.caption2).italic().foregroundStyle(theme.dim)
            }
            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.caption2)
                    .foregroundStyle(theme.accent)
                Text("Tap to log to \(slot.label)")
                    .font(.caption2).tracking(2)
                    .foregroundStyle(theme.accent)
            }
        }
    }
}
