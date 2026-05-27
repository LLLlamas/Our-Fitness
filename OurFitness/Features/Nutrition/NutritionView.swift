// Stripped-down meal log. No library, no scoring, no suggestions — just a
// custom-entry sheet (name + macros) and today's running list.

import SwiftUI
import SwiftData

struct NutritionView: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var logModels: [FoodLogEntryModel]
    @State private var showLogSheet = false

    private var today: String { Dates.dayKey() }

    private var todaysLogs: [FoodLogEntryDTO] {
        logModels.map(\.snapshot)
            .filter { $0.userId == profile.id && $0.date == today }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private var totals: DailyTotals {
        todaysLogs.reduce(into: DailyTotals.zero) { acc, e in
            let p = e.perServing
            acc.calories += p.calories
            acc.proteinG += p.proteinG
            acc.carbsG += p.carbsG
            acc.fatG += p.fatG
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("meals.")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(theme.text)
                Text("Log what you actually ate. Honesty > precision.")
                    .font(.callout).foregroundStyle(theme.dim)

                totalsCard

                Button {
                    showLogSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Log a meal")
                    }
                }
                .tactile(.primary, fullWidth: true)

                logList
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background(theme.bg.ignoresSafeArea())
        .sheet(isPresented: $showLogSheet) {
            MealLogSheet(profileId: profile.id) { dto in
                Repos.addFoodLog(ctx, dto)
                toasts.logged(dto.customName ?? "Meal", calories: dto.perServing.calories)
            }
            .themed(profile.mode)
        }
    }

    @ViewBuilder
    private var totalsCard: some View {
        let t = profile.computedTargets
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Today")
                    .font(.caption).tracking(2).textCase(.uppercase)
                    .foregroundStyle(theme.dim)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2),
                    spacing: 14
                ) {
                    ProgressBar(value: Double(totals.calories), target: Double(t.calories), label: "Calories")
                    ProgressBar(value: Double(totals.proteinG), target: Double(t.proteinG), label: "Protein", unit: "g")
                    ProgressBar(value: Double(totals.carbsG),   target: Double(t.carbsG),   label: "Carbs",   unit: "g")
                    ProgressBar(value: Double(totals.fatG),     target: Double(t.fatG),     label: "Fat",     unit: "g")
                }
            }
        }
    }

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
                        Haptics.tap()
                    }
                }
            }
        }
    }
}

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

private struct MealLogSheet: View {
    let profileId: UUID
    let onSave: (FoodLogEntryDTO) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var slot: Slot = .lunch
    @State private var calories: Int = 0
    @State private var protein: Int = 0
    @State private var carbs: Int = 0
    @State private var fat: Int = 0

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && calories > 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("log a meal.")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(theme.text)

                field("Name") {
                    TextField("e.g. Chicken bowl", text: $name)
                        .padding(10).background(theme.card)
                        .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
                        .foregroundStyle(theme.text)
                }

                slotPicker

                HStack(spacing: 10) {
                    numField("Calories", value: $calories)
                    numField("Protein g", value: $protein)
                }
                HStack(spacing: 10) {
                    numField("Carbs g", value: $carbs)
                    numField("Fat g", value: $fat)
                }

                Button {
                    let dto = FoodLogEntryDTO(
                        userId: profileId, date: Dates.dayKey(), slot: slot,
                        customName: name.trimmingCharacters(in: .whitespaces),
                        perServing: PerServing(
                            calories: calories, proteinG: protein,
                            carbsG: carbs, fatG: fat
                        )
                    )
                    onSave(dto)
                    dismiss()
                } label: {
                    Text("Save")
                }
                .tactile(.primary, fullWidth: true)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.6)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var slotPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Slot").font(.caption).tracking(2).foregroundStyle(theme.dim)
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
    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.system(size: 10)).tracking(2)
                .foregroundStyle(theme.dim)
            content()
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
