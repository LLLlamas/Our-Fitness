// Daily water intake — tap a cup preset to add. Daily progress + 7-day strip.
//
// Backed by SwiftData (WaterEntryModel, append-only like the other logs) via a
// profile-scoped @Query; the daily goal stays in AppStorage as a per-profile
// setting. Undo removes the most recent entry for today.

import SwiftUI
import SwiftData

struct WaterCard: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var entryModels: [WaterEntryModel]
    @AppStorage private var goalFlOz: Double

    init(profile: ProfileDTO) {
        self.profile = profile
        let uid = profile.id
        _entryModels = Query(
            filter: #Predicate<WaterEntryModel> { $0.userId == uid },
            sort: \.timestamp, order: .forward
        )
        _goalFlOz = AppStorage(wrappedValue: Water.defaultGoalFlOz, "waterGoalFlOz.\(uid.uuidString)")
    }

    private var entries: [WaterEntryDTO] { entryModels.map(\.snapshot) }
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
    }

    private var presetRow: some View {
        HStack(spacing: 8) {
            ForEach(Water.presets) { preset in
                Button { add(preset.flOz) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: preset.symbol).font(.system(size: 18))
                        Text(preset.label).font(.system(size: 11, weight: .medium))
                        Text("+\(Int(preset.flOz)) oz")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(theme.dim)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .tactile(.bump)
                .accessibilityLabel("Add \(preset.label) cup, \(Int(preset.flOz)) ounces")
            }
        }
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
