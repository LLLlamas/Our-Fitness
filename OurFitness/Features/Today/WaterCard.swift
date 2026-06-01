// Daily water intake — tap a cup preset to add. Daily progress + 7-day strip.
//
// Backed by SwiftData (WaterEntryModel, append-only like the other logs) via a
// profile-scoped @Query; the daily goal stays in AppStorage as a per-profile
// setting. Undo removes the most recent entry for today.
//
// Presets are custom-drawn glasses (small/medium/large) + a bottle. Users add
// their own named sizes via "Add size" — those persist in SwiftData
// (WaterCupPresetModel), the same treatment as logged reps/steps/meals.

import SwiftUI
import SwiftData

struct WaterCard: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var entryModels: [WaterEntryModel]
    @Query private var presetModels: [WaterCupPresetModel]
    @AppStorage private var goalFlOz: Double

    @State private var showAddSize = false

    init(profile: ProfileDTO) {
        self.profile = profile
        let uid = profile.id
        _entryModels = Query(
            filter: #Predicate<WaterEntryModel> { $0.userId == uid },
            sort: \.timestamp, order: .forward
        )
        _presetModels = Query(
            filter: #Predicate<WaterCupPresetModel> { $0.userId == uid },
            sort: \.createdAt, order: .forward
        )
        _goalFlOz = AppStorage(wrappedValue: Water.defaultGoalFlOz, "waterGoalFlOz.\(uid.uuidString)")
    }

    private var entries: [WaterEntryDTO] { entryModels.map(\.snapshot) }
    private var customPresets: [WaterCupPresetDTO] { presetModels.map(\.snapshot) }
    private var allPresets: [Water.CupPreset] { Water.allPresets(custom: customPresets) }
    private var today: String { Dates.dayKey() }
    private var todayOz: Double { Water.total(entries, on: today) }
    private var weekSeries: [Trends.Point] { Water.series(entries, days: 7) }
    private var weekAvg: Double { Water.average(entries, days: 7) }
    private var canUndo: Bool { entries.contains { $0.date == today } }

    // No explicit Haptics — the buttons use `.tactile(...)` (press haptic), and
    // ProgressBar fires a success haptic when the day crosses the goal (outcome).
    private func add(_ oz: Double) {
        Repos.addWater(ctx, WaterEntryDTO(userId: profile.id, date: today, flOz: oz))
        toasts.show(Toast(title: "+\(Int(oz)) oz", detail: "Water logged",
                          accent: .ok, symbol: "drop.fill"))
    }

    private func undoLast() {
        guard let last = entries.filter({ $0.date == today }).max(by: { $0.timestamp < $1.timestamp }) else { return }
        Repos.deleteWater(ctx, id: last.id)
        toasts.show(Toast(title: "Removed", detail: "Last water entry",
                          accent: .warn, symbol: "arrow.uturn.backward"))
    }

    private func adjustGoal(_ delta: Double) {
        goalFlOz = min(Water.maxGoalFlOz, max(Water.minGoalFlOz, goalFlOz + delta))
    }

    private func addCustomSize(name: String, flOz: Double, icon: Water.CupIcon) {
        let dto = WaterCupPresetDTO(
            userId: profile.id, name: name, flOz: flOz, icon: icon,
            sortOrder: customPresets.count
        )
        Repos.addWaterPreset(ctx, dto)
        toasts.show(Toast(title: "Size added", detail: "\(name) · \(Int(flOz)) oz",
                          accent: .win, symbol: "plus.circle.fill"))
    }

    private func deleteCustom(_ preset: Water.CupPreset) {
        guard preset.isCustom, let uuid = UUID(uuidString: preset.id) else { return }
        Repos.deleteWaterPreset(ctx, id: uuid)
        toasts.show(Toast(title: "Removed", detail: "\(preset.label) size",
                          accent: .warn, symbol: "trash"))
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                ProgressBar(value: todayOz, target: goalFlOz, label: "Water", unit: " oz")

                HStack {
                    if weekAvg > 0 {
                        Text("7-day avg \(Int(weekAvg)) oz")
                            .font(.caption2).foregroundStyle(theme.dim)
                    }
                    Spacer()
                    if canUndo {
                        Button { undoLast() } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.backward")
                                Text("Undo")
                            }
                            .font(.caption)
                        }
                        .tactile(.ghost)
                    }
                }

                presetRow
                goalRow

                if weekSeries.contains(where: { $0.value > 0 }) {
                    weeklyStrip
                }
            }
        }
        .sheet(isPresented: $showAddSize) {
            AddWaterSizeSheet(onSave: addCustomSize)
                .themed(theme.mode)
        }
    }

    // Horizontally scrollable so custom sizes never overflow the card width.
    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(allPresets) { preset in
                    presetButton(preset)
                }
                addSizeButton
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func presetButton(_ preset: Water.CupPreset) -> some View {
        Button { add(preset.flOz) } label: {
            VStack(spacing: 4) {
                GlassIcon(icon: preset.icon, tint: theme.accent, height: 22)
                    .frame(height: 22)
                Text(preset.label).font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text("+\(Int(preset.flOz)) oz")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(theme.dim)
            }
            .frame(minWidth: 64)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
        }
        .tactile(.bump)
        .accessibilityLabel("Add \(preset.label), \(Int(preset.flOz)) ounces")
        .contextMenu {
            if preset.isCustom {
                Button(role: .destructive) { deleteCustom(preset) } label: {
                    Label("Delete size", systemImage: "trash")
                }
            }
        }
    }

    private var addSizeButton: some View {
        Button { showAddSize = true } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 18))
                    .frame(height: 22)
                Text("Add size").font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(" ").font(.system(size: 9, design: .monospaced))
            }
            .frame(minWidth: 64)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
        }
        .tactile(.ghost)
        .accessibilityLabel("Add a custom water size")
    }

    private var goalRow: some View {
        HStack(spacing: 10) {
            Text("Goal").font(.caption).foregroundStyle(theme.dim)
            Spacer()
            Button { adjustGoal(-Water.goalStepFlOz) } label: { Image(systemName: "minus") }
                .tactile(.ghost)
                .accessibilityLabel("Lower water goal")
            Text("\(Int(goalFlOz)) oz")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(theme.text)
            Button { adjustGoal(Water.goalStepFlOz) } label: { Image(systemName: "plus") }
                .tactile(.ghost)
                .accessibilityLabel("Raise water goal")
        }
    }

    private var weeklyStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last 7 days")
                .font(.system(size: 10, weight: .medium)).tracking(2)
                .foregroundStyle(theme.dim)
            WeeklyBarStrip(series: weekSeries, goal: goalFlOz)
        }
    }
}

// MARK: - Add custom size sheet

private struct AddWaterSizeSheet: View {
    let onSave: (_ name: String, _ flOz: Double, _ icon: Water.CupIcon) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var ozText: String = ""
    @State private var icon: Water.CupIcon = .glassLarge
    @FocusState private var ozFocused: Bool

    private var parsedOz: Double? {
        guard let v = Double(ozText), v >= Water.minCustomFlOz, v <= Water.maxCustomFlOz else { return nil }
        return v
    }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && parsedOz != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("add size.")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("NAME · AMOUNT · ICON")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }

                field("Name") {
                    TextField("e.g. My tumbler", text: $name)
                        .foregroundStyle(theme.text)
                }

                field("Amount (fl oz)") {
                    TextField("e.g. 24", text: $ozText)
                        .keyboardType(.decimalPad)
                        .focused($ozFocused)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(theme.text)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Icon")
                        .font(.caption).tracking(2).textCase(.uppercase)
                        .foregroundStyle(theme.dim)
                    HStack(spacing: 10) {
                        ForEach(Water.CupIcon.allCases) { option in
                            iconChoice(option)
                        }
                    }
                }

                Button {
                    if let oz = parsedOz {
                        onSave(name.trimmingCharacters(in: .whitespaces), oz, icon)
                        dismiss()
                    }
                } label: {
                    Text("Save size").frame(maxWidth: .infinity)
                }
                .tactile(.primary, fullWidth: true)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)

                Button { dismiss() } label: { Text("Cancel") }
                    .tactile(.ghost)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.bg)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { ozFocused = false }
            }
        }
    }

    @ViewBuilder
    private func iconChoice(_ option: Water.CupIcon) -> some View {
        let selected = option == icon
        Button { icon = option } label: {
            GlassIcon(icon: option, tint: selected ? theme.accent : theme.dim, height: 26)
                .frame(width: 44, height: 36)
                .background(theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(selected ? theme.accent : theme.line, lineWidth: selected ? 2 : 1)
                )
        }
        .tactile(.ghost)
        .accessibilityLabel(option.pickerLabel)
    }

    @ViewBuilder
    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption).tracking(2).textCase(.uppercase)
                .foregroundStyle(theme.dim)
            content()
                .padding(10)
                .background(theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
        }
    }
}
